//
//  AuthenticationService.swift
//  Ethica
//
//  Firebase Authentication Service with Google Sign-In
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

@MainActor
class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authToken: String?

    /// Tracks when token was last fetched to avoid redundant getIDToken() calls
    private var tokenFetchedAt: Date?
    /// Firebase tokens expire after 60 min; refresh at 50 min to stay ahead
    private let tokenCacheDuration: TimeInterval = 50 * 60

    /// Deduplicates concurrent token fetch calls
    private var activeTokenTask: Task<Void, Never>?

    /// Convenience: current user's UID as a plain String (no FirebaseAuth import needed by callers)
    var currentUserId: String? { currentUser?.uid }
    /// Convenience: current user's display name as a plain String
    var currentDisplayName: String? { currentUser?.displayName }

    static let shared = AuthenticationService()

    private init() {
        // Check if user is already signed in
        if let user = Auth.auth().currentUser {
            self.isAuthenticated = true
            self.currentUser = user
            Task { await self.fetchAuthToken() }
        }

        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isAuthenticated = user != nil
            self?.currentUser = user
            if user != nil {
                Task { [weak self] in await self?.fetchAuthToken() }
            }
        }
    }

    // MARK: - Sign In Methods

    func signInWithEmail(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        await MainActor.run {
            self.currentUser = result.user
            self.isAuthenticated = true
        }
        await fetchAuthToken()
    }

    func signUpWithEmail(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        await MainActor.run {
            self.currentUser = result.user
            self.isAuthenticated = true
        }
        await fetchAuthToken()
    }

    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        await MainActor.run {
            self.currentUser = result.user
            self.isAuthenticated = true
        }
        await fetchAuthToken()
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async throws {
        // Get the client ID from Firebase config
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "AuthError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Firebase client ID not found"])
        }

        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // Get the root view controller on the main thread
        let rootViewController = try await MainActor.run { () -> UIViewController in
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                throw NSError(domain: "AuthError", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not find root view controller"])
            }
            // Walk to the topmost presented controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            return topVC
        }

        // Present the Google Sign-In flow
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "AuthError", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Google Sign-In did not return an ID token"])
        }

        // Create Firebase credential from Google tokens
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )

        // Sign in to Firebase with the Google credential
        let authResult = try await Auth.auth().signIn(with: credential)

        await MainActor.run {
            self.currentUser = authResult.user
            self.isAuthenticated = true
        }
        await fetchAuthToken()
    }

    // MARK: - Sign Out

    func signOut() throws {
        // Sign out of Google if signed in via Google
        GIDSignIn.sharedInstance.signOut()

        try Auth.auth().signOut()
        self.isAuthenticated = false
        self.currentUser = nil
        self.authToken = nil
        self.tokenFetchedAt = nil
        self.activeTokenTask?.cancel()
        self.activeTokenTask = nil

        // Clear all user-specific caches to prevent data leaking between accounts
        Task {
            await AIResultsCacheService.shared.clearAll()
        }
        HistoryService.shared.clearAllHistory()
        AppLogger.debug("Cleared all caches on sign-out")
    }

    // MARK: - Get Auth Token

    func fetchAuthToken() async {
        guard let user = Auth.auth().currentUser else {
            return
        }

        // Skip if token was fetched recently and is still valid
        if let fetchedAt = tokenFetchedAt,
           authToken != nil,
           Date().timeIntervalSince(fetchedAt) < tokenCacheDuration {
            return
        }

        // Deduplicate: if a fetch is already in flight, wait for it instead of spawning another
        if let existing = activeTokenTask {
            await existing.value
            return
        }

        let task = Task {
            do {
                let token = try await user.getIDToken()
                await MainActor.run {
                    self.authToken = token
                    self.tokenFetchedAt = Date()
                }
            } catch {
                AppLogger.error("Token refresh failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.authToken = nil
                    self.tokenFetchedAt = nil
                }
            }
            await MainActor.run {
                self.activeTokenTask = nil
            }
        }
        activeTokenTask = task
        await task.value
    }

    // MARK: - Auth Token Injection

    /// Injects the current Firebase Bearer token into the given request.
    func addAuthToken(to request: inout URLRequest) async {
        await fetchAuthToken()
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Account Deletion (Apple Guideline 5.1.1)

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AuthError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }

        let userId = user.uid

        // 1. Delete backend user data
        do {
            try await NetworkService.shared.deleteUserData(userId: userId)
        } catch {
            AppLogger.warning("Backend data deletion failed (continuing): \(error.localizedDescription)")
        }

        // 2. Clear all local data
        HistoryService.shared.clearAllHistory()
        await AIResultsCacheService.shared.clearAll()
        AppLogger.debug("Cleared all local caches for account deletion")

        // 3. Reset onboarding state
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set("", forKey: "onboardingCompletedByUser")

        // 4. Sign out of Google if applicable
        GIDSignIn.sharedInstance.signOut()

        // 5. Delete Firebase Auth account (must be last — invalidates the user object)
        try await user.delete()

        // 6. Update local state
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil
            self.authToken = nil
            self.tokenFetchedAt = nil
            self.activeTokenTask?.cancel()
            self.activeTokenTask = nil
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }
}
