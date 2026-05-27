//
//  EthicaApp.swift
//  Ethica
//
//  Created on 11/11/2025
//

import SwiftUI
import AppIntents

@main
struct EthicaApp: App {
    @StateObject private var authService = AuthenticationService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        // Pre-warm haptic generators for responsive first-scan feedback
        _ = HapticManager.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    // Show onboarding once per install, regardless of sign-in state.
                    OnboardingView(
                        preferencesManager: PreferencesManager.shared,
                        onComplete: {
                            withAnimation(AnimationSystem.springSmooth) {
                                hasCompletedOnboarding = true
                            }
                        }
                    )
                } else if !authService.isAuthenticated {
                    // Onboarding already completed, need sign-in
                    SignInView()
                        .environmentObject(authService)
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
            .preferredColorScheme(.dark)
        }
    }
}
