import AuthenticationServices
import UIKit

@MainActor
final class WebAuthSessionPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthSessionPresenter()

    /// Captured from SwiftUI via a tiny `UIViewRepresentable` so we always have a valid anchor.
    var window: UIWindow?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window, window.windowScene != nil {
            return window
        }

        // Best-effort fallback: find any visible window in the active foreground scene.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        if let candidate = scenes
            .flatMap(\.windows)
            .first(where: { !$0.isHidden && $0.alpha > 0 }) {
            self.window = candidate
            return candidate
        }

        // Returning a brand new anchor can cause `presentationContextNotProvided` / invalid context errors.
        // If we genuinely have no window, fail gracefully by returning an empty anchor.
        return ASPresentationAnchor()
    }
}

