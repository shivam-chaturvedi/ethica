//
//  EthicaApp.swift
//  Ethica
//
//  Created on 11/11/2025
//

import SwiftUI
import AppIntents
import FirebaseCore
import GoogleSignIn

@main
struct EthicaApp: App {
    @StateObject private var authService = AuthenticationService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingCompletedByUser") private var onboardingCompletedByUser = ""

    init() {
        // Initialize Firebase
        FirebaseApp.configure()

        // Print backend configuration on app launch
        AppConfig.printConfiguration()

        // Pre-warm haptic generators for responsive first-scan feedback
        _ = HapticManager.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    // First-time user: onboard before sign-in
                    OnboardingView(
                        preferencesManager: PreferencesManager.shared,
                        onComplete: {
                            withAnimation(AnimationSystem.springSmooth) {
                                hasCompletedOnboarding = true
                            }
                        }
                    )
                } else if !authService.isAuthenticated {
                    // Onboarding done, need sign-in
                    SignInView()
                        .environmentObject(authService)
                } else if onboardingCompletedByUser.isEmpty {
                    // Just signed in after fresh onboarding — auto-stamp and go to main app
                    ContentView()
                        .environmentObject(authService)
                        .onAppear {
                            onboardingCompletedByUser = authService.currentUserId ?? ""
                            Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                PreferencesManager.shared.pullFromBackendIfNeeded()
                                HistoryService.shared.pullFromBackendIfNeeded()
                            }
                        }
                } else if onboardingCompletedByUser != (authService.currentUserId ?? "") {
                    // Different user signed in — re-onboard
                    OnboardingView(
                        preferencesManager: PreferencesManager.shared,
                        onComplete: {
                            withAnimation(AnimationSystem.springSmooth) {
                                onboardingCompletedByUser = authService.currentUserId ?? ""
                            }
                        }
                    )
                } else {
                    // Returning user, all set
                    ContentView()
                        .environmentObject(authService)
                        .task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            PreferencesManager.shared.pullFromBackendIfNeeded()
                            HistoryService.shared.pullFromBackendIfNeeded()
                        }
                }
            }
            .withToasts()
            .onOpenURL { url in
                // Handle the Google Sign-In redirect URL when the app is reopened
                GIDSignIn.sharedInstance.handle(url)
            }
            .preferredColorScheme(.dark)
        }
    }
}
