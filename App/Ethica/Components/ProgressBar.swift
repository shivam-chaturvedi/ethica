//
//  ProgressBar.swift
//  Ethica
//
//  Animated progress bar
//

import SwiftUI

struct ProgressBar: View {
    let progress: Double // 0.0 to 1.0
    let height: CGFloat
    let backgroundColor: Color
    let foregroundColor: Color

    init(
        progress: Double,
        height: CGFloat = 6,
        backgroundColor: Color = Color.white.opacity(0.1),
        foregroundColor: Color = Theme.primary
    ) {
        self.progress = min(max(progress, 0), 1)
        self.height = height
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(backgroundColor)

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(foregroundColor)
                    .frame(width: geometry.size.width * progress)
                    .animation(AnimationSystem.springSmooth, value: progress)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(progress * 100)) percent")
        .accessibilityLabel("Progress")
    }
}
