//
//  EthicaAnimations.swift
//  Ethica
//
//  Custom animation effects for premium UI polish
//

import SwiftUI

// MARK: - Enhanced Confetti (Safe products celebration)

struct ConfettiEffect: View {
    let isActive: Bool
    let style: ConfettiStyle

    enum ConfettiStyle {
        case celebration  // Green leaves + sparkles for safe/high-score
        case standard     // Generic confetti

        var symbols: [String] {
            switch self {
            case .celebration: return ["🌿", "✨", "💚", "🍃", "🌱", "✦"]
            case .standard: return ["✦", "●", "◆", "★", "▲"]
            }
        }
    }

    @State private var particles: [Particle] = []

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var opacity: Double
        var rotation: Double
        var symbol: String
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Text(particle.symbol)
                    .font(.system(size: 14))
                    .scaleEffect(particle.scale)
                    .opacity(particle.opacity)
                    .rotationEffect(.degrees(particle.rotation))
                    .position(x: particle.x, y: particle.y)
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active { spawnWaves() }
        }
        .onAppear {
            if isActive { spawnWaves() }
        }
    }

    private func spawnWaves() {
        // Wave 1
        spawnBatch(count: 12, delay: 0)
        // Wave 2
        spawnBatch(count: 8, delay: 0.3)
    }

    private func spawnBatch(count: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let newParticles = (0..<count).map { _ in
                Particle(
                    x: CGFloat.random(in: 40...320),
                    y: CGFloat.random(in: -30...0),
                    scale: CGFloat.random(in: 0.6...1.4),
                    opacity: 1.0,
                    rotation: Double.random(in: 0...360),
                    symbol: style.symbols.randomElement() ?? "✦"
                )
            }
            particles.append(contentsOf: newParticles)

            withAnimation(.easeOut(duration: 2.2)) {
                particles = particles.map { p in
                    var q = p
                    q.y = p.y + CGFloat.random(in: 250...450)
                    q.x = p.x + CGFloat.random(in: -100...100)
                    q.opacity = 0
                    q.rotation = p.rotation + Double.random(in: -200...200)
                    return q
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                particles.removeAll()
            }
        }
    }
}

// MARK: - Legacy ParticleEffect (backwards compat)

struct ParticleEffect: View {
    let isActive: Bool
    let color: Color

    var body: some View {
        ConfettiEffect(isActive: isActive, style: .standard)
    }
}

// MARK: - Leaf Particle Effect (subtle floating background)

struct LeafParticleEffect: View {
    let particleCount: Int

    @State private var leaves: [LeafParticle] = []

    struct LeafParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var phase: Double
        var speed: Double
        var symbol: String
    }

    init(count: Int = 6) {
        self.particleCount = min(count, 10)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for leaf in leaves {
                    let elapsed = time * leaf.speed
                    let sineX = sin(elapsed + leaf.phase) * 20
                    let posX = leaf.x + sineX
                    let posY = (leaf.y + CGFloat(elapsed * 15)).truncatingRemainder(dividingBy: size.height + 40) - 20

                    var text = context.resolve(Text(leaf.symbol).font(.system(size: 16)))
                    context.opacity = 0.15
                    context.draw(text, at: CGPoint(x: posX, y: posY))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .onAppear { generateLeaves() }
    }

    private func generateLeaves() {
        let symbols = ["🍃", "🌿", "🌱"]
        leaves = (0..<particleCount).map { _ in
            LeafParticle(
                x: CGFloat.random(in: 20...350),
                y: CGFloat.random(in: 0...800),
                phase: Double.random(in: 0...(.pi * 2)),
                speed: Double.random(in: 0.3...0.7),
                symbol: symbols.randomElement() ?? "🍃"
            )
        }
    }
}

// MARK: - Impact Ripple

struct ImpactRipple: View {
    var trigger: Bool
    var color: Color = Theme.primary

    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 0

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(rippleScale)
            .opacity(rippleOpacity)
            .drawingGroup()
            .onChange(of: trigger) { _, newValue in
                guard newValue else { return }
                rippleScale = 0.5
                rippleOpacity = 0.4
                withAnimation(.easeOut(duration: 1.2)) {
                    rippleScale = 2.5
                    rippleOpacity = 0
                }
            }
    }
}

// MARK: - Glow Effect (Pulsing glow border for highlighted cards)

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var isGlowing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isGlowing ? 0.6 : 0.2), radius: isGlowing ? radius : radius / 3)
            .shadow(color: color.opacity(isGlowing ? 0.3 : 0.1), radius: isGlowing ? radius * 1.5 : radius / 2)
            .animation(
                .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                value: isGlowing
            )
            .onAppear { isGlowing = true }
    }
}

extension View {
    func glowEffect(color: Color = Theme.primary, radius: CGFloat = 10) -> some View {
        self.modifier(GlowEffect(color: color, radius: radius))
    }
}

// MARK: - Breathing Animation (Gentle scale for loading states)

struct BreathingAnimation: ViewModifier {
    let intensity: CGFloat
    let duration: TimeInterval
    @State private var isBreathing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isBreathing ? 1.0 + intensity : 1.0)
            .opacity(isBreathing ? 1.0 : 0.85)
            .animation(
                .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear { isBreathing = true }
    }
}

extension View {
    func breathingAnimation(intensity: CGFloat = 0.03, duration: TimeInterval = 2.0) -> some View {
        self.modifier(BreathingAnimation(intensity: intensity, duration: duration))
    }
}

// MARK: - Typewriter Text (Character-by-character text reveal)

struct TypewriterText: View {
    let fullText: String
    let speed: TimeInterval

    @State private var displayedText = ""
    @State private var charIndex = 0

    init(_ text: String, speed: TimeInterval = 0.03) {
        self.fullText = text
        self.speed = speed
    }

    var body: some View {
        Text(displayedText)
            .onAppear {
                displayedText = ""
                charIndex = 0
                typeNextCharacter()
            }
    }

    private func typeNextCharacter() {
        guard charIndex < fullText.count else { return }
        let index = fullText.index(fullText.startIndex, offsetBy: charIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + speed) {
            displayedText += String(fullText[index])
            charIndex += 1
            typeNextCharacter()
        }
    }
}

// MARK: - Count Up Text (Animated counter from 0 to target)

struct CountUpText: View {
    let target: Double
    let duration: TimeInterval
    let prefix: String
    let suffix: String
    let decimals: Int

    @State private var currentValue: Double = 0
    @State private var timer: Timer?

    init(
        target: Double,
        duration: TimeInterval = 1.5,
        prefix: String = "",
        suffix: String = "",
        decimals: Int = 0
    ) {
        self.target = target
        self.duration = duration
        self.prefix = prefix
        self.suffix = suffix
        self.decimals = decimals
    }

    var body: some View {
        Text("\(prefix)\(formattedValue)\(suffix)")
            .onAppear {
                startCounting()
            }
    }

    private var formattedValue: String {
        if decimals == 0 {
            return "\(Int(currentValue))"
        }
        return String(format: "%.\(decimals)f", currentValue)
    }

    private func startCounting() {
        let steps = 60.0
        let stepDuration = duration / steps
        var step = 0.0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { t in
            step += 1
            let progress = step / steps
            let easedProgress = 1 - pow(1 - progress, 3)
            currentValue = target * easedProgress

            if step >= steps {
                currentValue = target
                t.invalidate()
            }
        }
    }
}

// MARK: - Animated Tab Indicator

struct AnimatedTabIndicator: View {
    let selectedTab: Int
    let tabCount: Int

    var body: some View {
        GeometryReader { geometry in
            let tabWidth = geometry.size.width / CGFloat(tabCount)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.primary)
                .frame(width: tabWidth * 0.5, height: 3)
                .offset(x: tabWidth * CGFloat(selectedTab) + tabWidth * 0.25)
                .animation(AnimationSystem.springResponsive, value: selectedTab)
        }
        .frame(height: 3)
    }
}
