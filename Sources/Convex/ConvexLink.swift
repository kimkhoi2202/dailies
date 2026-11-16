import Foundation
import Combine
import ConvexMobile

// The app's one connection to the Convex backend: signs the phone in, keeps trying until that works,
// and gives the store live queries and mutations.

final class ConvexLink {
    static let shared = ConvexLink()

    private let provider = DeviceAuthProvider()
    private let client: ConvexClientWithAuth<DeviceTokens>
    private let signedInSubject = CurrentValueSubject<Bool, Never>(false)
    private var signInTask: Task<Void, Never>?

    /// true once this phone is signed in. Delivered on the main thread.
    var signedIn: AnyPublisher<Bool, Never> {
        signedInSubject.removeDuplicates().receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    var isSignedIn: Bool { signedInSubject.value }

    private init() {
        client = ConvexClientWithAuth(deploymentUrl: ConvexConfig.deploymentURL, authProvider: provider)
    }

    /// Signs the phone in, making its account the first time. Tries again every few seconds until it works.
    func start() {
        guard signInTask == nil else { return }
        signInTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if case .success = await self.client.login(), !Task.isCancelled {
                    self.signedInSubject.send(true)
                    return
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// Leaves this phone's account behind and signs in with a brand new one.
    func startOver() {
        let previous = signInTask
        signInTask = nil
        signedInSubject.send(false)
        Task {
            previous?.cancel()
            await previous?.value
            await client.logout()
            await provider.auth.startOver()
            start()
        }
    }

    /// Turns the guest account on this phone into one with a username and password, keeping everything it has.
    func claim(username: String, password: String) async throws {
        try await provider.auth.claim(username: username, password: password)
    }

    /// Moves this phone to another account. `prepare` signs in to it and throws if that fails, in which
    /// case nothing changes. Otherwise the old session ends and the phone reconnects as the new account.
    func switchAccount(_ prepare: @escaping (DeviceAuth) async throws -> Void) async throws {
        try await prepare(provider.auth)
        let previous = signInTask
        signInTask = nil
        signedInSubject.send(false)
        previous?.cancel()
        await previous?.value
        await client.logout()
        await provider.auth.switchOver()
        start()
    }

    /// Takes the person through Apple or Google ("apple" or "google") and ties that to the account on this
    /// phone, so either way in opens it. false when they close the sign-in sheet.
    /// When the Apple or Google account already opens another account here, `other` gets that account's
    /// session to switch to; without `other` it is refused.
    func connect(_ name: String, other: ((DeviceTokens) async throws -> Void)? = nil) async throws -> Bool {
        let mine = try await provider.auth.validTokens(onToken: nil)
        guard var proof = try await WebSignIn.shared.proof(for: name) else { return false }
        proof["provider"] = name
        let answer = try await DeviceAuth.call("users:connect", proof, as: mine.accessToken) as? [String: Any] ?? [:]
        switch answer["status"] as? String {
        case "connected":
            if DeviceAccount.kind == nil { await provider.auth.mark(kind: name) }
            return true
        case "other":
            guard let theirs = DeviceAuth.tokens(in: answer) else { throw DeviceAuthError.refused("INVALID_CODE") }
            guard let other else {
                _ = try? await DeviceAuth.call("auth:signOut", ["refreshToken": theirs.refreshToken])
                throw DeviceAuthError.refused("ALREADY_CONNECTED")
            }
            try await other(theirs)
            return true
        default:
            throw DeviceAuthError.refused("INVALID_CODE")
        }
    }

    /// Waits until the phone is signed in.
    func ready() async {
        if signedInSubject.value { return }
        for await value in signedInSubject.values where value { return }
    }

    /// A live query. `onValue` runs on the main thread with the first result and again whenever it changes.
    /// If the subscription breaks it is opened again. Cancel the returned token to stop.
    func watch<Value: Decodable>(_ name: String, _ args: [String: ConvexEncodable?] = [:], as type: Value.Type,
                                 onValue: @escaping (Value) -> Void) -> AnyCancellable {
        let watcher = Watcher(client: client, name: name, args: args, onValue: onValue)
        watcher.open()
        return AnyCancellable { watcher.close() }
    }

    /// Runs a mutation once the phone is signed in and returns its answer.
    func mutate<Value: Decodable>(_ name: String, _ args: [String: ConvexEncodable?] = [:], as type: Value.Type) async throws -> Value {
        var attempt = 0
        while true {
            await ready()
            do {
                return try await client.mutation(name, with: args)
            } catch let error as ClientError {
                // A session that lapsed between the check and the call: wait for the fresh token and go again.
                guard case .ConvexError(let data) = error, data.contains("Not signed in"), attempt < 4 else { throw error }
                attempt += 1
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    /// Runs an action once the phone is signed in and returns its answer.
    func act<Value: Decodable>(_ name: String, _ args: [String: ConvexEncodable?] = [:], as type: Value.Type) async throws -> Value {
        await ready()
        return try await client.action(name, with: args)
    }

    /// Runs a mutation that has no answer.
    func mutate(_ name: String, _ args: [String: ConvexEncodable?] = [:]) async throws {
        let _: String? = try await mutate(name, args, as: String?.self)
    }
}

/// One live query that reopens itself when it fails.
private final class Watcher<Value: Decodable> {
    private let client: ConvexClient
    private let name: String
    private let args: [String: ConvexEncodable?]
    private let onValue: (Value) -> Void
    private var stream: AnyCancellable?
    private var closed = false

    init(client: ConvexClient, name: String, args: [String: ConvexEncodable?], onValue: @escaping (Value) -> Void) {
        self.client = client
        self.name = name
        self.args = args
        self.onValue = onValue
    }

    func open() {
        guard !closed else { return }
        stream = client.subscribe(to: name, with: args, yielding: Value.self)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard case .failure = completion else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.open() }
            }, receiveValue: { [weak self] value in
                guard let self, !self.closed else { return }
                self.onValue(value)
            })
    }

    func close() {
        closed = true
        stream?.cancel()
        stream = nil
    }
}
