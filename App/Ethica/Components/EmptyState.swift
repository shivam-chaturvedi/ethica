//
//  EmptyState.swift
//  Ethica
//
//  Empty state view for no results, no history, etc.
//

import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 60, weight: .light))
                .foregroundColor(Theme.textMuted)

            Text(title)
                .textStyleH2()

            Text(message)
                .textStyleBody()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let actionTitle = actionTitle, let action = action {
                PrimaryButton.primary(actionTitle, action: action)
                    .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.screenHorizontal)
    }
}
