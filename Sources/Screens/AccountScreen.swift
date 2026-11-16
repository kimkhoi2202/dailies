import SwiftUI
import Combine

// ACCOUNT: create an account or log in, with a username and password, with Apple or with Google.
// It opens when a guest does something that needs an account, and from Settings. Closing it keeps the guest account.

/// The ways to sign in that the backend has switched on besides a username and password.
final class AccountMethods: ObservableObject {
    static let shared = AccountMethods()

    @Published private(set) var apple = false
    @Published private(set) var google = false
    private var watch: AnyCancellable?

    private struct Row: Decodable {
        let apple: Bool
        let google: Bool
    }

    /// Starts listening the first time a screen asks.
    func listen() {
        guard LiveMode.on, watch == nil else { return }
        watch = ConvexLink.shared.watch("auth:methods", as: Row.self) { [weak self] row in
            self?.apple = row.apple
            self?.google = row.google
        }
    }
}

struct AccountScreen: View {
    /// What the account is for, when a guest was sent here by something that needs one.
    var reason: String? = nil

    @State private var creating = true
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var busy = false
    @ObservedObject private var methods = AccountMethods.shared

    var body: some View {
        DLPage(spacing: 12) {
            HStack {
                DLLogo(height: 28)
                Spacer()
                DLIconButton(symbol: "xmark").goesBack().accessibilityLabel("Close")
            }
            DLHeader(title: creating ? "Create account" : "Log in").padding(.top, 18)
            Text(creating ? (reason ?? "Pick a username and a password.") + " Your gold and scores stay with it." : "Your gold is where you left it.")
                .font(DL.text(15)).foregroundStyle(DL.ink2)
                .padding(.bottom, 6)
            field("Username", text: $username, secret: false)
            field(creating ? "Password, 10 characters or more" : "Password", text: $password, secret: true)
            if let problem {
                Text(problem).font(DL.text(14, .medium)).foregroundStyle(DL.danger).padding(.horizontal, 4)
            }
            DLTextKey(title: busy ? "One moment" : creating ? "Create account" : "Log in")
                .tap(submit)
                .opacity(busy ? 0.6 : 1)
                .padding(.top, 4)
            Text(creating ? "Have an account? Log in" : "New here? Create account")
                .font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                .frame(maxWidth: .infinity).frame(height: 40)
                .tap {
                    creating.toggle()
                    problem = nil
                }
            if methods.apple || methods.google {
                HStack(spacing: 10) {
                    Rectangle().fill(DL.line).frame(height: 1)
                    Text("or").dlLabel(10.5)
                    Rectangle().fill(DL.line).frame(height: 1)
                }
                .padding(.vertical, 2)
                if methods.apple {
                    DLTextKey(title: "Continue with Apple", symbol: "apple.logo", style: .ink).tap { web("apple") }
                }
                if methods.google {
                    DLTextKey(title: "Continue with Google", symbol: "g.circle.fill", style: .neutral).tap { web("google") }
                }
            }
            Text("Not now")
                .font(DL.text(15, .medium)).foregroundStyle(DL.ink2)
                .frame(maxWidth: .infinity).frame(height: 40)
                .goesBack()
        }
        .onAppear { methods.listen() }
    }

    private func field(_ title: String, text: Binding<String>, secret: Bool) -> some View {
        Group {
            if secret {
                SecureField(title, text: text).textContentType(.password)
            } else {
                TextField(title, text: text).textContentType(.username)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(DL.text(17, .medium))
        .foregroundStyle(DL.ink)
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func submit() {
        let name = username.trimmingCharacters(in: .whitespaces), secret = password, create = creating
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        if create, name.count < 3 || name.count > 20 || name.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            problem = "A username is 3 to 20 letters, numbers, dots or underscores."
            return
        }
        guard !name.isEmpty, !secret.isEmpty else {
            problem = "Type your username and your password."
            return
        }
        run {
            if create {
                // The guest account on this phone becomes the new account, so what it has is kept.
                try await ConvexLink.shared.claim(username: name, password: secret)
            } else {
                try await LiveStore.shared.switchAccount { try await $0.prepare(username: name, password: secret) }
            }
        }
    }

    private func web(_ provider: String) {
        run {
            guard let tokens = try await WebSignIn.shared.tokens(for: provider) else { throw CancellationError() }
            try await LiveStore.shared.switchAccount { await $0.prepare(tokens: tokens, kind: provider) }
        }
    }

    /// Runs one way of signing in. When it works the screen closes; when it does not, the reason shows under the fields.
    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy, LiveMode.on else { return }
        busy = true
        problem = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await work()
                LiveNav.shared.back()
                LiveNav.shared.say("You are signed in")
            } catch is CancellationError {
            } catch DeviceAuthError.refused(let code) {
                problem = Self.message(for: code)
            } catch {
                problem = "Could not reach DEGEN. Try again."
            }
        }
    }

    private static func message(for code: String) -> String {
        switch code {
        case "USERNAME_TAKEN": return "That username is taken."
        case "USERNAME_INVALID": return "A username is 3 to 20 letters, numbers, dots or underscores."
        case "USER_NOT_FOUND": return "No account has that username."
        case "INVALID_CREDENTIALS": return "That password is not right."
        case "PASSWORD_TOO_SHORT": return "A password is 10 characters or more."
        case "PASSWORD_TOO_LONG": return "That password is too long."
        case "PASSWORD_HAS_SURROUNDING_WHITESPACE": return "A password cannot start or end with a space."
        case "RATE_LIMITED": return "Too many tries. Wait a minute and try again."
        case "INVALID_CODE": return "That sign-in ran out. Try again."
        default: return "That did not work. Try again."
        }
    }
}
