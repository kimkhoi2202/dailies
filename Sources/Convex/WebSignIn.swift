import AuthenticationServices
import UIKit

// Signing in with Apple or Google. The system's sign-in sheet opens the provider's page, the backend
// sends the answer back on a degen:// address, and the code in it goes to the backend to finish.

@MainActor
final class WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebSignIn()
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    /// Takes the person through `provider` ("apple" or "google") and returns what the backend needs to finish:
    /// the state the sign-in began with and the code it ended with. nil when they close the sheet.
    func proof(for provider: String) async throws -> [String: String]? {
        let site = ConvexConfig.deploymentURL.replacingOccurrences(of: ".convex.cloud", with: ".convex.site")
        let path = provider == "apple" ? "auth:startSignInWithApple" : "auth:startSignInWithGoogle"
        let start = try await DeviceAuth.call(path, ["redirectTo": site + "/auth/done"]) as? [String: Any] ?? [:]
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
            if items.first(where: { $0.name == "convexAuthError" })?.value == "access_denied" { return nil }
            throw DeviceAuthError.refused("INVALID_CODE")
        }
        return ["state": state, "code": code]
    }
}
