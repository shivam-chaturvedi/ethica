//
//  StoreAvailabilityBadge.swift
//  Ethica
//
//  Displays store availability for alternative products
//

import SwiftUI
import Combine
import CoreLocation

struct StoreAvailabilityBadge: View {
    let productName: String
    @State private var availabilities: [NearbyAvailability] = []
    @State private var isLoading = true
    @State private var showAllStores = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Theme.primary)
                        .scaleEffect(0.7)
                    Text("Checking nearby stores...")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 8)
            } else if !availabilities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.warning)
                        Text("Estimated Availability")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        if availabilities.count > 2 {
                            Button(action: {
                                showAllStores.toggle()
                            }) {
                                Text(showAllStores ? "Show Less" : "Show More")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.primary)
                            }
                        }
                    }

                    // Disclaimer
                    Text("Based on estimates - always verify with store")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.warning)
                        .padding(.bottom, 4)

                    // Store badges
                    let displayedStores = showAllStores ? availabilities : Array(availabilities.prefix(2))

                    ForEach(displayedStores) { nearby in
                        storeBadge(nearby: nearby)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.warning.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            // If not loading and empty — show nothing (graceful)
        }
        .onAppear {
            guard loadTask == nil else { return } // Deduplicate
            loadTask = Task { await loadAvailability() }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @ViewBuilder
    private func storeBadge(nearby: NearbyAvailability) -> some View {
        HStack(spacing: 10) {
            // Store icon
            Image(systemName: nearby.store.chain.icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: nearby.store.chain.color))
                .frame(width: 24)

            // Store info
            VStack(alignment: .leading, spacing: 2) {
                Text(nearby.store.chain == .other ? nearby.store.name : nearby.store.chain.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    // Distance
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                        Text(nearby.formattedDistance)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Theme.textSecondary)

                    // Aisle
                    if let aisle = nearby.availability.aisle {
                        Text("•")
                            .foregroundColor(Theme.textMuted)
                        Text(aisle)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }

            Spacer()

            // Price (if available)
            if let formattedPrice = nearby.formattedPrice {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedPrice)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.success)

                    Text("est.")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textMuted)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.success)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: nearby.store.chain.color).opacity(0.1))
        )
    }

    private func loadAvailability() async {
        await MainActor.run { isLoading = true }

        // Wait for location if needed — observe the published property instead of sleeping
        let locationService = LocationService.shared
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestLocationPermission()
        }

        // Poll for location (up to 3 seconds, 100ms intervals) instead of blind sleep
        if locationService.currentLocation == nil {
            locationService.requestLocation()
            for _ in 0..<30 {
                if Task.isCancelled { return }
                if locationService.currentLocation != nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        if Task.isCancelled { return }

        // Fetch availability (cached by service — fast on repeat calls)
        let results = await StoreAvailabilityService.shared.checkAvailability(
            productName: productName,
            maxStores: 5,
            userPreferences: PreferencesManager.shared.preferences
        )

        if Task.isCancelled { return }

        await MainActor.run {
            self.availabilities = results.filter { $0.availability.inStock }
            self.isLoading = false
        }
    }
}

// MARK: - Compact version for inline use

struct StoreAvailabilityCompact: View {
    let productName: String
    @State private var nearestStore: NearbyAvailability?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(Theme.textSecondary)
                        .scaleEffect(0.6)
                    Text("Checking stores...")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
            } else if let nearest = nearestStore {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.warning)

                    Image(systemName: nearest.store.chain.icon)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: nearest.store.chain.color))

                    Text(nearest.store.chain == .other ? nearest.store.name : nearest.store.chain.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)

                    Text("(\(nearest.formattedDistance))")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)

                    Text("Est.")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.warning)

                    if let price = nearest.formattedPrice {
                        Text("•")
                            .foregroundColor(Theme.textMuted)
                        Text(price)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.success)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(hex: nearest.store.chain.color).opacity(0.15))
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: nearest.store.chain.color).opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .onAppear {
            guard loadTask == nil else { return }
            loadTask = Task { await loadNearest() }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadNearest() async {
        await MainActor.run { isLoading = true }

        // Uses the same cached results as StoreAvailabilityBadge (5-min TTL)
        let results = await StoreAvailabilityService.shared.checkAvailability(
            productName: productName,
            maxStores: 1
        )

        if Task.isCancelled { return }

        await MainActor.run {
            self.nearestStore = results.first(where: { $0.availability.inStock })
            self.isLoading = false
        }
    }
}

// MARK: - Preview

struct StoreAvailabilityBadge_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                StoreAvailabilityBadge(productName: "Beyond Burger")
                    .padding()

                StoreAvailabilityCompact(productName: "Oat Milk")
                    .padding()
            }
        }
    }
}
