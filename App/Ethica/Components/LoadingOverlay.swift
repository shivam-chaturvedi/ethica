//
//  LoadingOverlay.swift
//  Ethica
//
//  Full-screen loading overlay with animated steps
//  Used during product analysis, scanning, etc.
//

import SwiftUI

/// Full-screen loading overlay with progress and steps
struct LoadingOverlay: View {

    // MARK: - Properties

    let title: String
    let currentStep: String
    let progress: Double
    let productPreview: LoadingProductPreview?
    let canCancel: Bool
    let onCancel: (() -> Void)?

    @State private var isAnimating = false

    // MARK: - Initializers

    init(
        title: String = "Analyzing...",
        currentStep: String,
        progress: Double = 0.0,
        productPreview: LoadingProductPreview? = nil,
        canCancel: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.currentStep = currentStep
        self.progress = progress
        self.productPreview = productPreview
        self.canCancel = canCancel
        self.onCancel = onCancel
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            // Content
            VStack(spacing: Spacing.xl) {
                // Product preview (if available)
                if let preview = productPreview {
                    productPreviewCard(preview)
                        .transition(.scaleAndFade)
                }

                // Loading card
                loadingCard
                    .transition(.scaleAndFade)

                // Cancel button (if allowed)
                if canCancel {
                    cancelButton
                        .transition(.scaleAndFade)
                }
            }
            .padding(Spacing.screenHorizontal)
        }
        .onAppear {
            withAnimation(AnimationSystem.springSmooth) {
                isAnimating = true
            }
        }
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        GlassCard.primary {
            VStack(spacing: Spacing.lg) {
                // Animated spinner with shimmer effect
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            Theme.gradientHero,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(
                            .linear(duration: 1.5).repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }
                .padding(.top, Spacing.sm)

                // Title
                Text(title)
                    .textStyleH2()

                // Current step
                Text(currentStep)
                    .textStyleBody()
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 40)
                    .animation(AnimationSystem.fade, value: currentStep)

                // Progress bar
                if progress > 0 {
                    VStack(spacing: Spacing.xs) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track with shimmer
                                RoundedRectangle(cornerRadius: Spacing.radiusXS)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 6)
                                    .shimmer()

                                // Progress fill
                                RoundedRectangle(cornerRadius: Spacing.radiusXS)
                                    .fill(Theme.gradientHero)
                                    .frame(width: geometry.size.width * progress, height: 6)
                                    .animation(AnimationSystem.springSmooth, value: progress)
                            }
                        }
                        .frame(height: 6)

                        // Progress percentage
                        Text("\(Int(progress * 100))%")
                            .textStyleCaption()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Product Preview Card

    @ViewBuilder
    private func productPreviewCard(_ preview: LoadingProductPreview) -> some View {
        GlassCard.secondary {
            HStack(spacing: Spacing.md) {
                // Product image
                if let image = preview.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))
                } else {
                    // Loading skeleton for image
                    RoundedRectangle(cornerRadius: Spacing.radiusSM)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .shimmer()
                }

                // Product info
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let name = preview.name {
                        Text(name)
                            .textStyleH4()
                            .lineLimit(2)
                    } else {
                        // Loading skeleton for product name
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 16)
                                .shimmer()

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 100, height: 16)
                                .shimmer()
                        }
                    }

                    if let barcode = preview.barcode {
                        Text("Barcode: \(barcode)")
                            .textStyleCaption()
                    } else if preview.name == nil {
                        // Loading skeleton for barcode
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 120, height: 12)
                            .shimmer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scaleEffect(isAnimating ? 1.0 : 0.9)
        .opacity(isAnimating ? 1.0 : 0)
    }

    // MARK: - Cancel Button

    private var cancelButton: some View {
        Button(action: {
            onCancel?()
        }) {
            Text("Cancel")
                .textStyleButton(color: Theme.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
        }
        .opacity(isAnimating ? 1.0 : 0)
    }
}

// MARK: - Product Preview Model

struct LoadingProductPreview {
    let name: String?
    let barcode: String?
    let image: UIImage?

    init(name: String? = nil, barcode: String? = nil, image: UIImage? = nil) {
        self.name = name
        self.barcode = barcode
        self.image = image
    }
}

// MARK: - Convenience View Modifier

extension View {
    /// Show loading overlay
    func loadingOverlay(
        isPresented: Binding<Bool>,
        title: String = "Analyzing...",
        currentStep: String,
        progress: Double = 0.0,
        productPreview: LoadingProductPreview? = nil,
        canCancel: Bool = false,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        self.overlay {
            if isPresented.wrappedValue {
                LoadingOverlay(
                    title: title,
                    currentStep: currentStep,
                    progress: progress,
                    productPreview: productPreview,
                    canCancel: canCancel,
                    onCancel: onCancel
                )
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Preview

#Preview("Loading States") {
    struct PreviewWrapper: View {
        @State private var step = "Extracting ingredients..."
        @State private var progress = 0.25

        var body: some View {
            VStack {
                Text("Preview Content")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundPrimary)
            .overlay {
                LoadingOverlay(
                    currentStep: step,
                    progress: progress
                )
            }
            .onAppear {
                // Simulate progress
                Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                    withAnimation {
                        progress = min(progress + 0.25, 1.0)
                        if progress >= 1.0 {
                            progress = 0.25
                        }

                        let steps = [
                            "Extracting ingredients...",
                            "Analyzing dietary compatibility...",
                            "Checking allergens...",
                            "Calculating environmental impact..."
                        ]
                        step = steps[Int(progress * 4) % steps.count]
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    return PreviewWrapper()
}

#Preview("With Product Preview") {
    VStack {
        Text("Content")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.backgroundPrimary)
    .overlay {
        LoadingOverlay(
            title: "Analyzing Product",
            currentStep: "Extracting ingredients from label...",
            progress: 0.5,
            productPreview: LoadingProductPreview(
                name: "Organic Almond Milk",
                barcode: "012345678901",
                image: nil
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("With Cancel") {
    VStack {
        Text("Content")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.backgroundPrimary)
    .overlay {
        LoadingOverlay(
            currentStep: "Processing image...",
            progress: 0.3,
            canCancel: true,
            onCancel: {
                AppLogger.debug("Cancelled")
            }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Using View Modifier") {
    struct ModifierPreview: View {
        @State private var isLoading = true
        @State private var step = "Analyzing ingredients..."
        @State private var progress = 0.6

        var body: some View {
            VStack(spacing: Spacing.lg) {
                Text("Main Content")
                    .textStyleH1()

                PrimaryButton.primary("Toggle Loading") {
                    withAnimation {
                        isLoading.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundPrimary)
            .loadingOverlay(
                isPresented: $isLoading,
                title: "Analyzing Product",
                currentStep: step,
                progress: progress,
                canCancel: true,
                onCancel: {
                    isLoading = false
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    return ModifierPreview()
}
