//
//  LocationService.swift
//  Ethica
//
//  Location services for finding nearby stores
//

import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    private let locationManager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var locationError: String?

    /// Cached stores from backend, keyed by rounded lat/lng
    private var storeCache: [String: (stores: [Store], timestamp: Date)] = [:]
    private let storeCacheTTL: TimeInterval = 1800 // 30 minutes

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters // Don't need high accuracy for stores
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            locationError = "Location permission not granted"
            return
        }

        locationManager.requestLocation()
    }

    // MARK: - Nearby Stores (Real — via OpenStreetMap)

    /// Find real nearby stores via backend (OpenStreetMap Overpass API).
    /// Results are cached for 30 minutes per location.
    func findNearbyStores(maxDistance: Double = 15.0) async -> [Store] {
        guard let location = currentLocation else {
            AppLogger.warning("⚠️ No current location available")
            return []
        }

        let cacheKey = "\(round(location.coordinate.latitude * 100) / 100),\(round(location.coordinate.longitude * 100) / 100)"

        // Check cache
        if let cached = storeCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < storeCacheTTL {
            AppLogger.debug("📍 Store cache hit (\(cached.stores.count) stores)")
            return cached.stores.filter { $0.distance(from: location) <= maxDistance }
        }

        // Call backend
        do {
            guard let url = URL(string: "\(AppConfig.backendURL)/nearby-stores") else {
                AppLogger.error("Invalid nearby-stores URL")
                return []
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let payload: [String: Any] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "radius_miles": maxDistance
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ Store API returned non-200")
                return []
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let storeArray = json?["stores"] as? [[String: Any]] else {
                AppLogger.warning("⚠️ Invalid store response format")
                return []
            }

            let stores = storeArray.compactMap { Store.fromJSON($0) }

            // Cache results
            storeCache[cacheKey] = (stores: stores, timestamp: Date())
            AppLogger.debug("📍 Fetched \(stores.count) real stores from OpenStreetMap")

            return stores.filter { $0.distance(from: location) <= maxDistance }
                .sorted { $0.distance(from: location) < $1.distance(from: location) }

        } catch {
            AppLogger.error("❌ Store fetch error: \(error.localizedDescription)")
            return []
        }
    }

    /// Synchronous version that returns cached stores only (for sort comparators etc.)
    func findNearbyStoresCached(maxDistance: Double = 15.0) -> [Store] {
        guard let location = currentLocation else { return [] }

        let cacheKey = "\(round(location.coordinate.latitude * 100) / 100),\(round(location.coordinate.longitude * 100) / 100)"

        if let cached = storeCache[cacheKey] {
            return cached.stores.filter { $0.distance(from: location) <= maxDistance }
        }
        return []
    }

    func storeDistance(_ store: Store) -> Double? {
        guard let location = currentLocation else { return nil }
        return store.distance(from: location)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            AppLogger.debug("✅ Location permission granted")
            requestLocation()
        case .denied, .restricted:
            AppLogger.error("❌ Location permission denied")
            locationError = "Location permission denied. Enable in Settings to see nearby stores."
        case .notDetermined:
            AppLogger.debug("⏳ Location permission not determined")
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        locationError = nil
        AppLogger.debug("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = "Failed to get location: \(error.localizedDescription)"
        AppLogger.error("❌ Location error: \(error)")
    }
}
