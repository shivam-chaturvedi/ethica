//
//  Animation.swift
//  Ethica
//
//  Animation System - Timing, Easing, Physics
//  Balanced & Engaging animation style (300-500ms, spring physics)
//

import SwiftUI

/// Animation system with consistent timing and easing
struct AnimationSystem {

    // MARK: - Accessibility

    /// Whether the user has enabled Reduce Motion in system settings
    static var prefersReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Returns the given animation if motion is allowed, otherwise `.default`
    static func motionSafe(_ animation: Animation) -> Animation {
        prefersReducedMotion ? .default : animation
    }

    /// Returns the given animation if motion is allowed, otherwise `nil` (no animation)
    static func motionSafeOrNone(_ animation: Animation) -> Animation? {
        prefersReducedMotion ? nil : animation
    }

    // MARK: - Spring Animations (Physics-Based)

    /// Bouncy spring - playful, energetic (response: 0.5, damping: 0.7)
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.7)

    /// Smooth spring - balanced, polished (response: 0.6, damping: 0.8) - DEFAULT
    static let springSmooth = Animation.spring(response: 0.6, dampingFraction: 0.8)

    /// Responsive spring - quick feedback (response: 0.3, damping: 0.8)
    static let springResponsive = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Gentle spring - subtle, refined (response: 0.7, damping: 0.9)
    static let springGentle = Animation.spring(response: 0.7, dampingFraction: 0.9)

    // MARK: - Duration-Based Animations

    /// Fast animation - 200ms (quick feedback, micro-interactions)
    static let fast = Animation.easeOut(duration: 0.2)

    /// Normal animation - 300ms (standard transitions)
    static let normal = Animation.easeInOut(duration: 0.3)

    /// Slow animation - 500ms (complex animations, page transitions)
    static let slow = Animation.easeInOut(duration: 0.5)

    // MARK: - Specialized Animations

    /// Snappy animation - quick with overshoot
    static let snappy = Animation.interpolatingSpring(stiffness: 300, damping: 20)

    /// Smooth fade - opacity transitions
    static let fade = Animation.easeInOut(duration: 0.25)

    /// Scale pop - button press effects
    static let scalePop = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// Slide - drawer/modal presentations
    static let slide = Animation.spring(response: 0.5, dampingFraction: 0.8)

    // MARK: - Stagger Delays (for sequential animations)

    /// Fast stagger - 50ms between items
    static let staggerFast: TimeInterval = 0.05

    /// Normal stagger - 100ms between items (DEFAULT)
    static let staggerNormal: TimeInterval = 0.1

    /// Slow stagger - 150ms between items
    static let staggerSlow: TimeInterval = 0.15
}

// MARK: - Animation View Modifiers

extension View {
    /// Animate with smooth spring (DEFAULT)
    func animateSmooth<V: Equatable>(_ value: V) -> some View {
        self.animation(AnimationSystem.springSmooth, value: value)
    }

    /// Animate with bouncy spring
    func animateBouncy<V: Equatable>(_ value: V) -> some View {
        self.animation(AnimationSystem.springBouncy, value: value)
    }

    /// Animate with gentle spring
    func animateGentle<V: Equatable>(_ value: V) -> some View {
        self.animation(AnimationSystem.springGentle, value: value)
    }

    /// Animate with fast timing
    func animateFast<V: Equatable>(_ value: V) -> some View {
        self.animation(AnimationSystem.fast, value: value)
    }

    /// Animate with normal timing
    func animateNormal<V: Equatable>(_ value: V) -> some View {
        self.animation(AnimationSystem.normal, value: value)
    }

    /// Fade in/out animation
    func animateFade<V: Equatable>(_ value: V) -> some View {
        self.animation(AnimationSystem.fade, value: value)
    }
}

// MARK: - Entrance Animations

extension View {
    /// Fade in from transparent
    func fadeIn(delay: TimeInterval = 0) -> some View {
        self.modifier(FadeInModifier(delay: delay))
    }

    /// Slide in from bottom with fade
    func slideInFromBottom(delay: TimeInterval = 0, offset: CGFloat = 20) -> some View {
        self.modifier(SlideInFromBottomModifier(delay: delay, offset: offset))
    }

    /// Slide in from top with fade
    func slideInFromTop(delay: TimeInterval = 0, offset: CGFloat = -20) -> some View {
        self.modifier(SlideInFromTopModifier(delay: delay, offset: offset))
    }

    /// Scale and fade in (pop effect)
    func scaleIn(delay: TimeInterval = 0) -> some View {
        self.modifier(ScaleInModifier(delay: delay))
    }

    /// Stagger animation for lists
    func staggerAnimation(index: Int, delay: TimeInterval = AnimationSystem.staggerNormal) -> some View {
        self.modifier(StaggerModifier(index: index, baseDelay: delay))
    }

    /// Slide in from leading edge with fade
    func slideInFromLeading(delay: TimeInterval = 0, offset: CGFloat = 30) -> some View {
        self.modifier(SlideInFromLeadingModifier(delay: delay, offset: offset))
    }

    /// Glow pulse effect behind content
    func glowPulse(color: Color, intensity: Double = 0.6, speed: Double = 1.5) -> some View {
        self.modifier(GlowPulseModifier(color: color, intensity: intensity, speed: speed))
    }
}

// MARK: - Transition Effects

extension AnyTransition {
    /// Slide and fade from bottom
    static var slideFromBottom: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// Slide and fade from top
    static var slideFromTop: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    /// Scale and fade
    static var scaleAndFade: AnyTransition {
        .scale(scale: 0.9).combined(with: .opacity)
    }

    /// Scale from center
    static var scaleCenter: AnyTransition {
        .scale(scale: 0.8, anchor: .center).combined(with: .opacity)
    }
}

// MARK: - View Modifiers for Entrance Animations

private struct FadeInModifier: ViewModifier {
    let delay: TimeInterval
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .onAppear {
                if AnimationSystem.prefersReducedMotion {
                    appeared = true
                } else {
                    withAnimation(AnimationSystem.fade.delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

private struct SlideInFromBottomModifier: ViewModifier {
    let delay: TimeInterval
    let offset: CGFloat
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (AnimationSystem.prefersReducedMotion ? 0 : offset))
            .onAppear {
                if AnimationSystem.prefersReducedMotion {
                    appeared = true
                } else {
                    withAnimation(AnimationSystem.springSmooth.delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

private struct SlideInFromTopModifier: ViewModifier {
    let delay: TimeInterval
    let offset: CGFloat
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (AnimationSystem.prefersReducedMotion ? 0 : offset))
            .onAppear {
                if AnimationSystem.prefersReducedMotion {
                    appeared = true
                } else {
                    withAnimation(AnimationSystem.springSmooth.delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

private struct ScaleInModifier: ViewModifier {
    let delay: TimeInterval
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : (AnimationSystem.prefersReducedMotion ? 1 : 0.9))
            .onAppear {
                if AnimationSystem.prefersReducedMotion {
                    appeared = true
                } else {
                    withAnimation(AnimationSystem.springBouncy.delay(delay)) {
                        appeared = true
                    }
                }
            }
    }
}

private struct StaggerModifier: ViewModifier {
    let index: Int
    let baseDelay: TimeInterval
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (AnimationSystem.prefersReducedMotion ? 0 : 20))
            .onAppear {
                if AnimationSystem.prefersReducedMotion {
                    appeared = true
                } else {
                    let staggerDelay = baseDelay * Double(index)
                    withAnimation(AnimationSystem.springSmooth.delay(staggerDelay)) {
                        appeared = true
                    }
                }
            }
    }
}

// MARK: - Button Press Animation

extension View {
    /// Add button press scale effect
    func buttonPressAnimation() -> some View {
        self.modifier(ButtonPressModifier())
    }
}

private struct ButtonPressModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(AnimationSystem.springBouncy, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - Animated Number Counter

struct AnimatedNumber: View {
    let value: Double
    let duration: Double
    let formatter: NumberFormatter

    @State private var displayValue: Double = 0

    init(
        value: Double,
        duration: Double = 1.0,
        formatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return f
        }()
    ) {
        self.value = value
        self.duration = duration
        self.formatter = formatter
    }

    var body: some View {
        Text(formatter.string(from: NSNumber(value: displayValue)) ?? "0")
            .onAppear {
                withAnimation(.easeOut(duration: duration)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: duration * 0.5)) {
                    displayValue = newValue
                }
            }
    }
}

// MARK: - Pulsing Animation

extension View {
    /// Add pulsing animation (for loading indicators)
    func pulsing(duration: TimeInterval = 1.5) -> some View {
        self.modifier(PulsingModifier(duration: duration))
    }
}

private struct PulsingModifier: ViewModifier {
    let duration: TimeInterval
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(
                AnimationSystem.prefersReducedMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                if !AnimationSystem.prefersReducedMotion {
                    isPulsing = true
                }
            }
    }
}

private struct SlideInFromLeadingModifier: ViewModifier {
    let delay: TimeInterval
    let offset: CGFloat
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : -offset)
            .onAppear {
                withAnimation(AnimationSystem.springSmooth.delay(delay)) {
                    appeared = true
                }
            }
    }
}

private struct GlowPulseModifier: ViewModifier {
    let color: Color
    let intensity: Double
    let speed: Double
    @State private var isGlowing = false

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color)
                    .blur(radius: 20)
                    .opacity(isGlowing ? intensity : 0.15)
                    .animation(.easeInOut(duration: speed).repeatForever(autoreverses: true), value: isGlowing)
            )
            .onAppear { isGlowing = true }
    }
}

// MARK: - Scroll Transition (iOS 17)

extension View {
    /// Fade + scale + slide items as they scroll into viewport (GPU-accelerated)
    func scrollFadeIn() -> some View {
        self.scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .offset(y: phase.isIdentity ? 0 : 16)
        }
    }
}

// MARK: - Shake Effect (Phase Animator)

struct ShakeEffect: ViewModifier {
    var trigger: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .phaseAnimator([0, -10, 10, -8, 8, -5, 5, 0], trigger: trigger) { view, offset in
                    view.offset(x: offset)
                } animation: { _ in
                    .spring(response: 0.08, dampingFraction: 0.4)
                }
        } else {
            content
        }
    }
}

extension View {
    func shakeEffect(trigger: Bool) -> some View {
        modifier(ShakeEffect(trigger: trigger))
    }
}

// MARK: - Glow Burst Effect

struct GlowBurstModifier: ViewModifier {
    let color: Color
    var trigger: Bool
    @State private var burstScale: CGFloat = 0.5
    @State private var burstOpacity: Double = 0

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color)
                    .scaleEffect(burstScale)
                    .opacity(burstOpacity)
                    .blur(radius: 30)
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue else { return }
                burstScale = 0.5
                burstOpacity = 0.6
                withAnimation(.easeOut(duration: 0.6)) {
                    burstScale = 2.0
                    burstOpacity = 0
                }
            }
    }
}

extension View {
    func glowBurst(color: Color, trigger: Bool) -> some View {
        modifier(GlowBurstModifier(color: color, trigger: trigger))
    }
}
