//
//  AnimationExtensions.swift
//  Ethica
//
//  Global animation modifiers and extensions
//

import SwiftUI

// MARK: - View Extensions for Animations

extension View {
    /// Adds a subtle bounce animation when view appears
    func bounceOnAppear(delay: Double = 0) -> some View {
        self.modifier(BounceOnAppearModifier(delay: delay))
    }
    
    /// Adds a fade and slide animation when view appears
    func fadeSlideIn(edge: Edge = .bottom, distance: CGFloat = 20, delay: Double = 0) -> some View {
        self.modifier(FadeSlideInModifier(edge: edge, distance: distance, delay: delay))
    }
    
    /// Adds a spring press animation for buttons
    func springPress() -> some View {
        self.modifier(SpringPressModifier())
    }
    
    /// Adds a shimmer effect for loading states
    func shimmer(active: Bool = true) -> some View {
        self.modifier(ShimmerModifier(active: active))
    }
}

// MARK: - Bounce On Appear Modifier

struct BounceOnAppearModifier: ViewModifier {
    let delay: Double
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .spring(response: 0.6, dampingFraction: 0.7)
                    .delay(delay)
                ) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
    }
}

// MARK: - Fade Slide In Modifier

struct FadeSlideInModifier: ViewModifier {
    let edge: Edge
    let distance: CGFloat
    let delay: Double
    @State private var offset: CGFloat
    @State private var opacity: Double = 0
    
    init(edge: Edge, distance: CGFloat, delay: Double) {
        self.edge = edge
        self.distance = distance
        self.delay = delay
        
        switch edge {
        case .top:
            _offset = State(initialValue: -distance)
        case .bottom:
            _offset = State(initialValue: distance)
        case .leading:
            _offset = State(initialValue: -distance)
        case .trailing:
            _offset = State(initialValue: distance)
        }
    }
    
    func body(content: Content) -> some View {
        content
            .offset(
                x: edge == .leading || edge == .trailing ? offset : 0,
                y: edge == .top || edge == .bottom ? offset : 0
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .spring(response: 0.6, dampingFraction: 0.8)
                    .delay(delay)
                ) {
                    offset = 0
                    opacity = 1.0
                }
            }
    }
}

// MARK: - Spring Press Modifier

struct SpringPressModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isPressed = true
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
            )
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if active {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.3)
                        .offset(x: phase * geometry.size.width)
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = 1.0
                            }
                        }
                    }
                }
            )
            .mask(content)
    }
}

// MARK: - Page Transition Styles

struct PageTransition: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
    }
}

extension AnyTransition {
    static var pageSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
    
    static var pageSlideBack: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}
