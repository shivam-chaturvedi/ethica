//
//  PrimaryButton.swift
//  Ethica
//
//  Premium button component with animations and variants
//  Consistent button styling across the app
//

import SwiftUI

/// Premium button with gradient, glass, or outline styles
struct PrimaryButton: View {

    // MARK: - Properties

    let title: String
    let icon: String?
    let iconPosition: IconPosition
    let style: ButtonStyle
    let size: ButtonSize
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    // MARK: - Initializers

    init(
        _ title: String,
        icon: String? = nil,
        iconPosition: IconPosition = .leading,
        style: ButtonStyle = .primary,
        size: ButtonSize = .standard,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.iconPosition = iconPosition
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        Button(action: {
            if !isDisabled && !isLoading {
                action()
            }
        }) {
            HStack(spacing: Spacing.sm) {
                // Leading icon
                if iconPosition == .leading, let icon = icon, !isLoading {
                    Image(systemName: icon)
                        .font(size.iconFont)
                }

                // Loading spinner
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                        .scaleEffect(0.8)
                }

                // Title
                if !isLoading {
                    Text(title)
                        .font(size.font)
                        .foregroundColor(style.foregroundColor)
                }

                // Trailing icon
                if iconPosition == .trailing, let icon = icon, !isLoading {
                    Image(systemName: icon)
                        .font(size.iconFont)
                }
            }
            .frame(maxWidth: style.fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, size.padding.leading)
            .background(backgroundView)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .disabled(isDisabled || isLoading)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(AnimationSystem.springBouncy, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isDisabled && !isLoading {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            // Gradient background
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Theme.gradientHero)
                .shadow(color: Theme.primary.opacity(0.3), radius: 8, y: 4)

        case .secondary:
            // Glass morphism background
            ZStack {
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(Color.white.opacity(0.05))
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: Theme.shadowSubtle.color, radius: 6, y: 2)

        case .tertiary:
            // Outline only
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(Theme.primary, lineWidth: 2)

        case .destructive:
            // Error gradient
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Theme.gradientError)
                .shadow(color: Theme.error.opacity(0.3), radius: 8, y: 4)

        case .accent:
            // Accent gradient
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Theme.gradientAccent)
                .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 4)

        case .success:
            // Success gradient
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Theme.gradientSuccess)
                .shadow(color: Theme.success.opacity(0.3), radius: 8, y: 4)
        }
    }
}

// MARK: - Button Styles

extension PrimaryButton {
    enum ButtonStyle {
        case primary
        case secondary
        case tertiary
        case destructive
        case accent
        case success

        var foregroundColor: Color {
            switch self {
            case .primary, .destructive, .accent, .success:
                return .white
            case .secondary:
                return Theme.textPrimary
            case .tertiary:
                return Theme.primary
            }
        }

        var fullWidth: Bool {
            switch self {
            case .primary, .destructive:
                return true
            case .secondary, .tertiary, .accent, .success:
                return false
            }
        }
    }

    enum IconPosition {
        case leading
        case trailing
    }
}

// MARK: - Convenience Initializers

extension PrimaryButton {
    /// Create primary gradient button (most common)
    static func primary(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> PrimaryButton {
        PrimaryButton(title, icon: icon, style: .primary, isLoading: isLoading, isDisabled: isDisabled, action: action)
    }

    /// Create secondary glass button
    static func secondary(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> PrimaryButton {
        PrimaryButton(title, icon: icon, style: .secondary, isLoading: isLoading, isDisabled: isDisabled, action: action)
    }

    /// Create tertiary outline button
    static func tertiary(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> PrimaryButton {
        PrimaryButton(title, icon: icon, style: .tertiary, isLoading: isLoading, isDisabled: isDisabled, action: action)
    }

    /// Create destructive button
    static func destructive(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> PrimaryButton {
        PrimaryButton(title, icon: icon, style: .destructive, isLoading: isLoading, isDisabled: isDisabled, action: action)
    }
}

// MARK: - Preview

#Preview("Button Styles") {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            // Primary buttons
            VStack(spacing: Spacing.md) {
                Text("Primary Buttons")
                    .textStyleH3()
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton.primary("Scan Product", icon: "camera.fill") {}
                PrimaryButton.primary("Analyze Ingredients") {}
                PrimaryButton.primary("Loading...", isLoading: true) {}
                PrimaryButton.primary("Disabled", isDisabled: true) {}
            }

            Divider()

            // Secondary buttons
            VStack(spacing: Spacing.md) {
                Text("Secondary Buttons")
                    .textStyleH3()
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton.secondary("View Details", icon: "info.circle") {}
                PrimaryButton.secondary("Share Results", icon: "square.and.arrow.up") {}
            }

            Divider()

            // Tertiary buttons
            VStack(spacing: Spacing.md) {
                Text("Tertiary Buttons")
                    .textStyleH3()
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton.tertiary("Cancel") {}
                PrimaryButton("Learn More", icon: "arrow.right", iconPosition: .trailing, style: .tertiary) {}
            }

            Divider()

            // Accent button
            VStack(spacing: Spacing.md) {
                Text("Accent Button")
                    .textStyleH3()
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Plate Check", icon: "camera.viewfinder", style: .accent) {}
            }

            Divider()

            // Success button
            VStack(spacing: Spacing.md) {
                Text("Success Button")
                    .textStyleH3()
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Safe to Consume", icon: "checkmark.circle.fill", style: .success) {}
            }

            Divider()

            // Destructive button
            VStack(spacing: Spacing.md) {
                Text("Destructive Button")
                    .textStyleH3()
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton.destructive("Delete Scan", icon: "trash") {}
            }

            Divider()

            // Button sizes
            VStack(spacing: Spacing.md) {
                Text("Button Sizes")
                    .textStyleH3()
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Large Button", size: .large) {}
                PrimaryButton("Standard Button", size: .standard) {}
                PrimaryButton("Small Button", size: .small) {}
            }
        }
        .padding(Spacing.screenHorizontal)
    }
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Interactive Test") {
    VStack(spacing: Spacing.xl) {
        Text("Tap buttons to test press animation")
            .textStyleH3()

        PrimaryButton.primary("Press Me", icon: "hand.tap.fill") {
            AppLogger.debug("Button tapped!")
        }

        PrimaryButton.secondary("Glass Button", icon: "sparkles") {
            AppLogger.debug("Glass button tapped!")
        }
    }
    .padding(Spacing.screenHorizontal)
    .background(Theme.backgroundPrimary)
    .preferredColorScheme(.dark)
}
