//
//  EthicaTabBar.swift
//  Ethica
//
//  Custom animated tab bar with glass morphism and sliding pill indicator
//

import SwiftUI

struct EthicaTabBar: View {
    @Binding var selectedTab: Int
    @Namespace private var tabNamespace

    private let tabs: [(icon: String, label: String, color: Color)] = [
        ("camera.fill", "Scan", Theme.primary),
        ("clock.fill", "History", Theme.accent),
        ("chart.bar.fill", "Impact", Theme.primary),
        ("gearshape.fill", "Settings", Theme.accent)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(index: index)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(tabBarBackground)
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(index: Int) -> some View {
        let tab = tabs[index]
        let isSelected = selectedTab == index

        Button {
            withAnimation(AnimationSystem.springResponsive) {
                selectedTab = index
            }
            HapticManager.shared.trigger(.selectionChanged)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Sliding pill indicator
                    if isSelected {
                        Capsule()
                            .fill(tab.color.opacity(0.18))
                            .frame(width: 56, height: 32)
                            .matchedGeometryEffect(id: "tabPill", in: tabNamespace)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? tab.color : Theme.textMuted)
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                        .symbolEffect(.bounce, value: isSelected)
                }
                .frame(height: 32)

                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tab.color : Theme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Background

    private var tabBarBackground: some View {
        ZStack {
            // Glass morphism
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)

            // Subtle border
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        .padding(.horizontal, Spacing.sm)
    }
}
