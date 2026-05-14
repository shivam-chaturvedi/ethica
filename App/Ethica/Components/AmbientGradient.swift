//
//  AmbientGradient.swift
//  Ethica
//
//  Subtle animated radial gradient for verdict backgrounds
//

import SwiftUI

struct AmbientGradient: View {
    let verdict: AmbientVerdict

    enum AmbientVerdict {
        case safe, caution, unsafe

        var color: Color {
            switch self {
            case .safe: return Theme.success
            case .caution: return Theme.warning
            case .unsafe: return Theme.error
            }
        }

        var speed: Double {
            switch self {
            case .safe: return 3.0    // Slow breathing
            case .caution: return 2.0  // Slightly faster
            case .unsafe: return 1.5   // Pulse
            }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: AnimationSystem.prefersReducedMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breathe = AnimationSystem.prefersReducedMotion ? 0.5 : (sin(time / verdict.speed) * 0.5 + 0.5)

            RadialGradient(
                colors: [
                    verdict.color.opacity(0.08 + breathe * 0.04),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
        }
        .allowsHitTesting(false)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

// MARK: - View Modifier

extension View {
    func ambientVerdict(_ verdict: AmbientGradient.AmbientVerdict) -> some View {
        self.background(AmbientGradient(verdict: verdict))
    }
}
