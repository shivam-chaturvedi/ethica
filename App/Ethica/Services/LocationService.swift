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

    // MARK: - Nearby Stores (Real — via OpenStreetMap Overpass API)

    /// Find real nearby stores via OpenStreetMap Overpass API (no backend server).
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

        // Call Overpass directly
        do {
            guard let url = URL(string: "https://overpass-api.de/api/interpreter") else { return [] }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 20

            let radiusMeters = max(500.0, maxDistance * 1609.34)
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude

            let query = """
            [out:json][timeout:15];
            (
              node["shop"~"supermarket|convenience|health_food|greengrocer"](around:\(Int(radiusMeters)),\(lat),\(lon));
              way["shop"~"supermarket|convenience|health_food|greengrocer"](around:\(Int(radiusMeters)),\(lat),\(lon));
              relation["shop"~"supermarket|convenience|health_food|greengrocer"](around:\(Int(radiusMeters)),\(lat),\(lon));
            );
            out center tags;
            """

            let body = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            request.httpBody = body.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ Overpass returned non-200")
                return []
            }

            let stores = parseOverpassStores(data: data)

            // Cache results
            storeCache[cacheKey] = (stores: stores, timestamp: Date())
            AppLogger.debug("📍 Fetched \(stores.count) stores from OpenStreetMap Overpass")

            return stores.filter { $0.distance(from: location) <= maxDistance }
                .sorted { $0.distance(from: location) < $1.distance(from: location) }

        } catch {
            AppLogger.error("❌ Store fetch error: \(error.localizedDescription)")
            return []
        }
    }

    private func parseOverpassStores(data: Data) -> [Store] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else {
            return []
        }

        return elements.compactMap { el in
            let type = el["type"] as? String ?? "node"
            guard let idNum = el["id"] as? NSNumber else { return nil }
            let tags = el["tags"] as? [String: Any] ?? [:]
            let name = (tags["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let storeName = name, !storeName.isEmpty else { return nil }

            let lat: Double?
            let lon: Double?
            if let elLat = el["lat"] as? Double, let elLon = el["lon"] as? Double {
                lat = elLat
                lon = elLon
            } else if let center = el["center"] as? [String: Any],
                      let cLat = center["lat"] as? Double,
                      let cLon = center["lon"] as? Double {
                lat = cLat
                lon = cLon
            } else {
                return nil
            }

            let chain = guessChain(from: storeName)
            let addressParts = [
                tags["addr:housenumber"] as? String,
                tags["addr:street"] as? String
            ].compactMap { $0 }.joined(separator: " ")

            let address = addressParts.isEmpty ? (tags["addr:full"] as? String ?? storeName) : addressParts

            return Store(
                id: "\(type)_\(idNum.stringValue)",
                name: storeName,
                chain: chain,
                address: address,
                city: tags["addr:city"] as? String ?? "",
                state: tags["addr:state"] as? String ?? "",
                zipCode: tags["addr:postcode"] as? String ?? "",
                latitude: lat ?? 0,
                longitude: lon ?? 0,
                phone: tags["phone"] as? String
            )
        }
    }

    private func guessChain(from name: String) -> StoreChain {
        let lower = name.lowercased()
        if lower.contains("whole foods") { return .wholeFoods }
        if lower.contains("trader joe") { return .traderJoes }
        if lower.contains("sprouts") { return .sprouts }
        if lower.contains("walmart") { return .walmart }
        if lower.contains("target") { return .target }
        if lower.contains("costco") { return .costco }
        if lower.contains("aldi") { return .aldi }
        return .other
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
