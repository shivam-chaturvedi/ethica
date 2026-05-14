//
//  HapticManager.swift
//  Ethica
//
//  Created by Claude on 2026-02-05
//  Centralized haptic feedback management
//

import UIKit

class HapticManager {
    static let shared = HapticManager()
    private var isEnabled = true

    // Pre-created feedback generators for performance
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // Prevent direct initialization - use shared instance
    private init() {
        // Prepare all generators for immediate use
        notificationGenerator.prepare()
        selectionGenerator.prepare()
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
    }

    enum HapticType {
        case success
        case warning
        case error
        case selectionChanged
        case impactLight
        case impactMedium
        case impactHeavy
    }

    /// Trigger a haptic feedback
    /// - Parameter type: The type of haptic to trigger
    func trigger(_ type: HapticType) {
        guard isEnabled else { return }

        switch type {
        case .success:
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        case .error:
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        case .selectionChanged:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .impactLight:
            lightImpactGenerator.impactOccurred()
            lightImpactGenerator.prepare()
        case .impactMedium:
            mediumImpactGenerator.impactOccurred()
            mediumImpactGenerator.prepare()
        case .impactHeavy:
            heavyImpactGenerator.impactOccurred()
            heavyImpactGenerator.prepare()
        }
    }

    /// Enable or disable haptic feedback globally
    /// - Parameter enabled: Whether haptics should be enabled
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Check if haptics are currently enabled
    var areEnabled: Bool {
        return isEnabled
    }

    // MARK: - Haptic Sequences

    enum HapticPattern {
        case scoreReveal
        case celebration
        case warningPulse
        case scanComplete
    }

    /// Play a multi-step haptic sequence using cancellable Tasks
    func sequence(_ pattern: HapticPattern) {
        guard isEnabled else { return }
        Task { @MainActor in
            switch pattern {
            case .scoreReveal:
                trigger(.impactLight)
                try? await Task.sleep(nanoseconds: 150_000_000)
                trigger(.impactMedium)
                try? await Task.sleep(nanoseconds: 200_000_000)
                trigger(.impactHeavy)
                try? await Task.sleep(nanoseconds: 200_000_000)
                trigger(.success)

            case .celebration:
                trigger(.success)
                try? await Task.sleep(nanoseconds: 200_000_000)
                trigger(.impactLight)
                try? await Task.sleep(nanoseconds: 150_000_000)
                trigger(.impactLight)
                try? await Task.sleep(nanoseconds: 150_000_000)
                trigger(.impactMedium)

            case .warningPulse:
                trigger(.warning)
                try? await Task.sleep(nanoseconds: 250_000_000)
                trigger(.impactMedium)
                try? await Task.sleep(nanoseconds: 250_000_000)
                trigger(.warning)

            case .scanComplete:
                trigger(.impactMedium)
                try? await Task.sleep(nanoseconds: 120_000_000)
                trigger(.impactLight)
                try? await Task.sleep(nanoseconds: 130_000_000)
                trigger(.success)
            }
        }
    }
}
