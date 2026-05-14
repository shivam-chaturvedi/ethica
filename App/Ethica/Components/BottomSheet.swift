//
//  BottomSheet.swift
//  Ethica
//
//  Custom glass-morphism bottom sheet with drag-to-dismiss
//

import SwiftUI

// MARK: - Sheet Styling Modifier

struct PremiumSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationCornerRadius(28)
            .presentationBackground(.ultraThinMaterial)
            .presentationDragIndicator(.visible)
    }
}

extension View {
    func premiumSheet() -> some View {
        self.modifier(PremiumSheetModifier())
    }
}

// MARK: - Custom Bottom Sheet (overlay-based)

struct BottomSheetView<Content: View>: View {
    @Binding var isPresented: Bool
    let snapPoints: [CGFloat] // fractions of screen height (e.g. [0.5, 0.92])
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var currentSnapIndex: Int = 0
    @GestureState private var isDragging = false

    private let dismissVelocity: CGFloat = 500

    var body: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height
            let sheetHeight = screenHeight * snapPoints[currentSnapIndex]

            ZStack(alignment: .bottom) {
                // Dimmed background
                if isPresented {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(AnimationSystem.springSmooth) {
                                isPresented = false
                            }
                        }
                        .transition(.opacity)
                }

                // Sheet
                if isPresented {
                    VStack(spacing: 0) {
                        // Drag handle
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 36, height: 5)
                            .padding(.top, 10)
                            .padding(.bottom, 8)

                        content()
                    }
                    .frame(height: sheetHeight, alignment: .top)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .offset(y: max(dragOffset, 0))
                    .gesture(
                        DragGesture()
                            .updating($isDragging) { _, state, _ in state = true }
                            .onChanged { value in
                                dragOffset = value.translation.height
                            }
                            .onEnded { value in
                                let velocity = value.predictedEndTranslation.height - value.translation.height
                                if velocity > dismissVelocity || dragOffset > sheetHeight * 0.4 {
                                    withAnimation(AnimationSystem.springSmooth) {
                                        isPresented = false
                                    }
                                } else {
                                    // Snap back
                                    withAnimation(AnimationSystem.springBouncy) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .animation(AnimationSystem.springSmooth, value: isPresented)
        .onChange(of: isPresented) { _, newValue in
            if newValue {
                dragOffset = 0
                HapticManager.shared.trigger(.impactLight)
            }
        }
    }
}
