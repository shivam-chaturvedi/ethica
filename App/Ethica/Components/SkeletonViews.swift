//
//  SkeletonViews.swift
//  Ethica
//
//  Skeleton loading placeholders with shimmer effect
//

import SwiftUI

// MARK: - Skeleton Primitives

struct SkeletonRect: View {
    let width: CGFloat?
    let height: CGFloat

    init(width: CGFloat? = nil, height: CGFloat = 16) {
        self.width = width
        self.height = height
    }

    var body: some View {
        RoundedRectangle(cornerRadius: height / 3)
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .shimmer()
            .accessibilityHidden(true)
    }
}

struct SkeletonCircle: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .frame(width: size, height: size)
            .shimmer()
            .accessibilityHidden(true)
    }
}

// MARK: - Skeleton Card (generic product card placeholder)

struct SkeletonCard: View {
    var body: some View {
        GlassCard.primary {
            HStack(spacing: Spacing.md) {
                SkeletonCircle(size: 48)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SkeletonRect(width: 140, height: 14)
                    SkeletonRect(width: 100, height: 12)
                }

                Spacer()

                SkeletonCircle(size: 40)
            }
        }
    }
}

// MARK: - Skeleton History Card

struct SkeletonHistoryCard: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Timeline dot
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 12, height: 12)
                .shimmer()

            GlassCard.secondary {
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        SkeletonRect(width: 150, height: 14)
                        SkeletonRect(width: 100, height: 11)
                        SkeletonRect(width: 80, height: 11)
                    }

                    Spacer()

                    SkeletonCircle(size: 44)
                }
            }
        }
    }
}

// MARK: - Skeleton Dashboard Hero

struct SkeletonDashboardHero: View {
    var body: some View {
        GlassCard.primary {
            VStack(spacing: Spacing.lg) {
                SkeletonCircle(size: 120)
                SkeletonRect(width: 160, height: 18)
                SkeletonRect(width: 200, height: 13)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
        }
    }
}

// MARK: - Skeleton Stat Grid

struct SkeletonStatGrid: View {
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.md) {
            ForEach(0..<4, id: \.self) { _ in
                GlassCard.secondary {
                    VStack(spacing: Spacing.sm) {
                        SkeletonCircle(size: 28)
                        SkeletonRect(width: 60, height: 22)
                        SkeletonRect(width: 80, height: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
    }
}

// MARK: - Skeleton Results View

struct SkeletonResultsView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SkeletonRect(width: 180, height: 18)
                    SkeletonRect(width: 120, height: 13)
                }
                Spacer()
            }

            // Hero verdict
            GlassCard.primary {
                VStack(spacing: Spacing.lg) {
                    SkeletonCircle(size: 100)
                    SkeletonRect(width: 160, height: 16)
                    SkeletonRect(width: 200, height: 13)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
            }

            // Stats row
            HStack(spacing: Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    GlassCard.secondary {
                        VStack(spacing: Spacing.xs) {
                            SkeletonRect(width: 50, height: 20)
                            SkeletonRect(width: 60, height: 11)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            // Details cards
            ForEach(0..<2, id: \.self) { _ in
                GlassCard.secondary {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SkeletonRect(width: 120, height: 14)
                        SkeletonRect(height: 12)
                        SkeletonRect(width: 180, height: 12)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }
}
