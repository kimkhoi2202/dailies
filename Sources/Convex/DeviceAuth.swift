import Foundation
import Security
import ConvexMobile

// Each phone has its own account: a random username and password made on first launch and kept in
// the Keychain. Signing in gives a short-lived access token and a refresh token; this file keeps a
// fresh access token available for as long as the app runs.

/// The tokens for one signed-in session.
struct DeviceTokens: Equatable {
    var accessToken: String
    var refreshToken: String
    var userId: String

    /// When the access token stops working, read from the token itself.
    var accessExpiry: Date {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return Date().addingTimeInterval(30) }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double else { return Date().addingTimeInterval(30) }
        return Date(timeIntervalSince1970: exp)
    }
}

enum DeviceAuthError: Error {
    case server(String)
    case refused(String)
}

/// What the phone remembers between launches.
private struct DeviceSecrets: Codable {
    var username: String
    var password: String
    var refreshToken: String?
    /// How the person signed in: "password", "apple" or "google". nil is the silent account the phone made for itself.
    var kind: String?

    static func make() -> DeviceSecrets {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return DeviceSecrets(username: "device" + id, password: UUID().uuidString + UUID().uuidString, refreshToken: nil)
    }
}

/// How this phone is signed in, for screens to read: "password", "apple", "google", or nil for the silent guest account.
enum DeviceAccount {
    fileprivate static let kindKey = "dailies.device.kind"
    static var kind: String? { UserDefaults.standard.string(forKey: kindKey) }
}

/// Keychain first. A build that cannot use the Keychain, like an unsigned simulator build, falls back to app storage.
private enum SecretBox {
    private static let service = "com.kimkhoi2202.dailies.device"
    private static let account = "account"
    private static let fallbackKey = "dailies.device.account"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() -> DeviceSecrets? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
           let secrets = try? JSONDecoder().decode(DeviceSecrets.self, from: data) {
            return secrets
        }
        if let data = UserDefaults.standard.data(forKey: fallbackKey) {
            return try? JSONDecoder().decode(DeviceSecrets.self, from: data)
        }
        return nil
    }

    static func save(_ secrets: DeviceSecrets) {
        guard let data = try? JSONEncoder().encode(secrets) else { return }
        UserDefaults.standard.set(secrets.kind, forKey: DeviceAccount.kindKey)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        // Only trust the Keychain if what was written can be read back.
        var check = query
        check[kSecReturnData as String] = true
        check[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if status == errSecSuccess, SecItemCopyMatching(check as CFDictionary, &out) == errSecSuccess, out as? Data == data {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        } else {
            UserDefaults.standard.set(data, forKey: fallbackKey)
        }
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        UserDefaults.standard.removeObject(forKey: DeviceAccount.kindKey)
    }
}

/// Signs the phone in and keeps the session fresh. Every call is serialised, because a refresh token
/// works once: two refreshes at the same moment would cancel each other.
actor DeviceAuth {
    private var secrets: DeviceSecrets
    private var tokens: DeviceTokens?
    private var inFlight: Task<DeviceTokens, Error>?
    private var push: (@Sendable (String?) -> Void)?
    private var keeper: Task<Void, Never>?
    /// An account the person has just signed in to, not yet this phone's account.
    private var waiting: (DeviceSecrets, DeviceTokens)?

    /// How long before an access token runs out a new one is fetched.
    private static let margin: TimeInterval = 20

    init() {
        if let saved = SecretBox.load() {
            secrets = saved
        } else {
            secrets = .make()
            SecretBox.save(secrets)
        }
    }

    /// Tokens whose access token is good for a while yet, signing in or refreshing when needed.
    func validTokens(onToken: (@Sendable (String?) -> Void)?) async throws -> DeviceTokens {
        if let onToken { push = onToken }
        if let tokens, tokens.accessExpiry.timeIntervalSinceNow > Self.margin { return tokens }
        return try await renew()
    }

    /// Forgets this phone's account. The next sign-in makes a new one.
    func startOver() async {
        keeper?.cancel()
        keeper = nil
        _ = try? await inFlight?.value
        if let token = secrets.refreshToken { _ = try? await Self.call("auth:signOut", ["refreshToken": token]) }
        tokens = nil
        SecretBox.clear()
        secrets = .make()
        SecretBox.save(secrets)
    }

    func signOut() async {
        keeper?.cancel()
        keeper = nil
        if let token = secrets.refreshToken { _ = try? await Self.call("auth:signOut", ["refreshToken": token]) }
        tokens = nil
        secrets.refreshToken = nil
        SecretBox.save(secrets)
    }

    /// Gives this phone's silent account the person's own username and password. The account and its
    /// session carry on, so nothing kept for it is lost.
    func claim(username: String, password: String) async throws {
        let mine = try await validTokens(onToken: nil)
        let answer = try await Self.call("users:claim", ["username": username, "password": password], as: mine.accessToken)
        if let problem = answer as? String { throw DeviceAuthError.refused(problem) }
        secrets.username = username
        secrets.password = password
        secrets.kind = "password"
        SecretBox.save(secrets)
    }

    /// Checks the username and password of an existing account with the server.
    /// Nothing changes on the phone until `switchOver`.
    func prepare(username: String, password: String) async throws {
        let login = ["username": username, "password": password]
        let answer = try await Self.call("auth:signInWithUsernamePassword", login) as? [String: Any] ?? [:]
        guard let fresh = Self.tokens(in: answer) else {
            throw DeviceAuthError.refused((answer["userError"] as? [String: Any])?["error"] as? String ?? "UNKNOWN")
        }
        waiting = (DeviceSecrets(username: username, password: password, refreshToken: fresh.refreshToken, kind: "password"), fresh)
    }

    /// Takes a session that Apple or Google sign-in ended with. Nothing changes on the phone until `switchOver`.
    func prepare(tokens fresh: DeviceTokens, kind: String) {
        waiting = (DeviceSecrets(username: "", password: "", refreshToken: fresh.refreshToken, kind: kind), fresh)
    }

    /// Makes the prepared account this phone's account. The old session is signed out first.
    func switchOver() async {
        guard let (next, fresh) = waiting else { return }
        waiting = nil
        _ = try? await inFlight?.value
        secrets = next
        tokens = fresh
        SecretBox.save(next)
        keepFresh()
    }

    private func renew() async throws -> DeviceTokens {
        if let inFlight { return try await inFlight.value }
        let secrets = self.secrets
        let task = Task { try await Self.session(for: secrets) }
        inFlight = task
        defer { inFlight = nil }
        let fresh: DeviceTokens
        do {
            fresh = try await task.value
        } catch DeviceAuthError.refused(let why) where why == "SESSION_ENDED" {
            // An Apple or Google session that ran out cannot be renewed quietly. The phone carries on as a guest.
            SecretBox.clear()
            self.secrets = .make()
            SecretBox.save(self.secrets)
            fresh = try await Self.session(for: self.secrets)
        }
        tokens = fresh
        self.secrets.refreshToken = fresh.refreshToken
        SecretBox.save(self.secrets)
        keepFresh()
        return fresh
    }

    /// Fetches the next access token shortly before the current one runs out, for as long as the app runs.
    private func keepFresh() {
        keeper?.cancel()
        keeper = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let expiry = await self.tokens?.accessExpiry else { return }
                let wait = max(1, expiry.timeIntervalSinceNow - Self.margin)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { return }
                await self.renewQuietly()
            }
        }
    }

    private func renewQuietly() async {
        if let tokens, tokens.accessExpiry.timeIntervalSinceNow > Self.margin { return }
        let current = keeper
        do {
            let fresh = try await renew()
            push?(fresh.accessToken)
        } catch {
            // No network, most likely. Try again soon; the old token stays in place meanwhile.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if current == keeper, !Task.isCancelled { keepFresh() }
        }
    }

    /// A session for these secrets: refresh the old one, or sign in, or make the account.
    private static func session(for secrets: DeviceSecrets) async throws -> DeviceTokens {
        if let refreshToken = secrets.refreshToken,
           let answer = try await call("auth:refreshSession", ["refreshToken": refreshToken]) as? [String: Any],
           answer["kind"] as? String == "rotated", let tokens = tokens(in: answer) {
            return tokens
        }
        // Only an account with a username and password can sign in again by itself.
        guard secrets.kind == nil || secrets.kind == "password" else { throw DeviceAuthError.refused("SESSION_ENDED") }
        let login = ["username": secrets.username, "password": secrets.password]
        let signIn = try await call("auth:signInWithUsernamePassword", login) as? [String: Any] ?? [:]
        if let tokens = tokens(in: signIn) { return tokens }
        let problem = (signIn["userError"] as? [String: Any])?["error"] as? String ?? "UNKNOWN"
        // Only the phone's own silent account is made on the spot.
        guard problem == "USER_NOT_FOUND", secrets.kind == nil else { throw DeviceAuthError.refused(problem) }
        let signUp = try await call("auth:signUpWithUsernamePassword", login) as? [String: Any] ?? [:]
        if let tokens = tokens(in: signUp) { return tokens }
        throw DeviceAuthError.refused((signUp["userError"] as? [String: Any])?["error"] as? String ?? "UNKNOWN")
    }

    static func tokens(in answer: [String: Any]) -> DeviceTokens? {
        guard let bundle = answer["tokens"] as? [String: Any],
              let access = bundle["accessToken"] as? String,
              let refresh = bundle["refreshToken"] as? String,
              let userId = bundle["userId"] as? String else { return nil }
        return DeviceTokens(accessToken: access, refreshToken: refresh, userId: userId)
    }

    /// Runs one of the backend's sign-in functions over plain HTTPS, so signing in never waits on the live connection.
    /// With `token`, the call is made as the account that access token belongs to.
    static func call(_ path: String, _ args: [String: Any], as token: String? = nil) async throws -> Any {
        guard let url = URL(string: ConvexConfig.deploymentURL + "/api/mutation") else { throw DeviceAuthError.server("Bad address") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "args": args, "format": "json"])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceAuthError.server("Unreadable answer")
        }
        guard answer["status"] as? String == "success", let value = answer["value"] else {
            throw DeviceAuthError.server(answer["errorMessage"] as? String ?? "The server said no")
        }
        return value
    }
}

/// Hands the device session to the Convex client.
final class DeviceAuthProvider: AuthProvider, @unchecked Sendable {
    let auth = DeviceAuth()

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> DeviceTokens {
        try await auth.validTokens(onToken: onIdToken)
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> DeviceTokens {
        try await auth.validTokens(onToken: onIdToken)
    }

    func logout() async throws {
        await auth.signOut()
    }

    func extractIdToken(from authResult: DeviceTokens) -> String {
        authResult.accessToken
    }
}
