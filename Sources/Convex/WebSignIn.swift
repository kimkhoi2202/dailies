import AuthenticationServices
import UIKit

// Signing in with Apple or Google. The system's sign-in sheet opens the provider's page, the backend
// sends the answer back on a degen:// address, and the code in it is traded for a session.

@MainActor
final class WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebSignIn()
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    /// A session for the account the person picks with `provider` ("apple" or "google"), or nil when they close the sheet.
    func tokens(for provider: String) async throws -> DeviceTokens? {
        let name = provider == "apple" ? "Apple" : "Google"
        let site = ConvexConfig.deploymentURL.replacingOccurrences(of: ".convex.cloud", with: ".convex.site")
        let start = try await DeviceAuth.call("auth:startSignInWith" + name, ["redirectTo": site + "/auth/done"]) as? [String: Any] ?? [:]
        guard let page = (start["redirect"] as? String).flatMap({ URL(string: $0) }), let state = start["state"] as? String else {
            throw DeviceAuthError.server("No sign-in page")
        }
        let answer: URL? = try await withCheckedThrowingContinuation { waiting in
            let session = ASWebAuthenticationSession(url: page, callbackURLScheme: "degen") { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    waiting.resume(returning: nil)
                } else if let error {
                    waiting.resume(throwing: error)
                } else {
                    waiting.resume(returning: url)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
        session = nil
        guard let answer else { return nil }
        let items = URLComponents(url: answer, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "convexAuthCode" })?.value else {
            let problem = items.first(where: { $0.name == "convexAuthError" })?.value
            if problem == "access_denied" { return nil }
            throw DeviceAuthError.refused("INVALID_CODE")
        }
        let done = try await DeviceAuth.call("auth:completeSignInWith" + name, ["state": state, "code": code]) as? [String: Any] ?? [:]
        guard let tokens = DeviceAuth.tokens(in: done) else { throw DeviceAuthError.refused("INVALID_CODE") }
        return tokens
    }
}
