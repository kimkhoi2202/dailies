import SwiftUI
import Combine

// ACCOUNT: create an account or log in, with a username and password, with Apple or with Google.
// Closing the screen keeps the silent guest account the phone made for itself.

private struct AccountMethods: Decodable {
    let apple: Bool
    let google: Bool
}

struct AccountScreen: View {
    /// Set once this screen has been shown, so it only opens by itself on the first launch.
    static let seenKey = "dailies.account.seen"

    @State private var creating = true
    @State private var username = ""
    @State private var password = ""
    @State private var problem: String?
    @State private var busy = false
    @State private var methods = AccountMethods(apple: false, google: false)
    @State private var methodsWatch: AnyCancellable?

    var body: some View {
        DLPage(spacing: 12) {
            HStack {
                DLLogo(height: 28)
                Spacer()
                DLIconButton(symbol: "xmark").goesBack().accessibilityLabel("Close")
            }
            DLHeader(title: creating ? "Create account" : "Log in").padding(.top, 18)
            Text(creating ? "Pick a username and a password. Your gold follows you to any phone." : "Your gold is where you left it.")
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
            Text("Play as a guest")
                .font(DL.text(15, .medium)).foregroundStyle(DL.ink2)
                .frame(maxWidth: .infinity).frame(height: 40)
                .goesBack()
        }
        .onAppear {
            UserDefaults.standard.set(true, forKey: Self.seenKey)
            guard LiveMode.on, methodsWatch == nil else { return }
            methodsWatch = ConvexLink.shared.watch("auth:methods", as: AccountMethods.self) { methods = $0 }
        }
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
            try await LiveStore.shared.switchAccount { try await $0.prepare(username: name, password: secret, create: create) }
            // A new account starts with a made-up name. Give it the one the person picked.
            if create { try? await ConvexLink.shared.mutate("users:update", ["name": name]) }
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
