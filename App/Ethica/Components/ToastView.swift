//
//  ToastView.swift
//  Ethica
//
//  Toast/snackbar notification system with glass morphism
//

import SwiftUI

// MARK: - Toast Model

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let variant: ToastVariant
    let duration: TimeInterval

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }

    enum ToastVariant {
        case success, error, info, warning

        var color: Color {
            switch self {
            case .success: return Theme.success
            case .error: return Theme.error
            case .info: return Theme.info
            case .warning: return Theme.warning
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }

        var haptic: HapticManager.HapticType {
            switch self {
            case .success: return .success
            case .error: return .error
            case .info: return .impactLight
            case .warning: return .warning
            }
        }
    }
}

// MARK: - Toast Manager

@Observable
class ToastManager {
    static let shared = ToastManager()
    private init() {}

    var currentToast: ToastItem?
    private var queue: [ToastItem] = []
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, variant: ToastItem.ToastVariant = .info, duration: TimeInterval = 3.0) {
        let toast = ToastItem(message: message, variant: variant, duration: duration)
        if currentToast == nil {
            present(toast)
        } else {
            queue.append(toast)
        }
    }

    func success(_ message: String) { show(message, variant: .success) }
    func error(_ message: String) { show(message, variant: .error) }
    func warning(_ message: String) { show(message, variant: .warning) }
    func info(_ message: String) { show(message, variant: .info) }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(AnimationSystem.springResponsive) {
            currentToast = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showNext()
        }
    }

    private func present(_ toast: ToastItem) {
        HapticManager.shared.trigger(toast.variant.haptic)
        withAnimation(AnimationSystem.springBouncy) {
            currentToast = toast
        }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func showNext() {
        guard !queue.isEmpty else { return }
        present(queue.removeFirst())
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastItem
    @State private var progress: CGFloat = 1.0

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Accent stripe
            RoundedRectangle(cornerRadius: 2)
                .fill(toast.variant.color)
                .frame(width: 4, height: 36)

            Image(systemName: toast.variant.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(toast.variant.color)

            Text(toast.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 4)

            Button {
                ToastManager.shared.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            }
        )
        .overlay(alignment: .bottom) {
            // Progress bar
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1)
                    .fill(toast.variant.color.opacity(0.5))
                    .frame(width: geo.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .padding(.horizontal, Spacing.screenHorizontal)
        .onAppear {
            withAnimation(.linear(duration: toast.duration)) {
                progress = 0
            }
            // Announce to VoiceOver
            AccessibilityNotification.Announcement(toast.message).post()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Toast Container Modifier

struct ToastContainerModifier: ViewModifier {
    @State private var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                        .zIndex(999)
                }
            }
    }
}

extension View {
    func withToasts() -> some View {
        modifier(ToastContainerModifier())
    }
}
