// 
//  PreferencesStorage.swift
//  Ethica
//
//  Created on 11/11/2025
//

import Foundation
import Combine

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @Published var preferences = UserPreferences() {
        didSet {
            savePreferences()
            debouncedSyncToBackend()
        }
    }

    /// Whether we've already attempted a cloud pull this session
    private var hasPulledFromCloud = false

    /// Debounce work item for backend sync (prevents 9 requests while typing "shellfish")
    private var syncDebounceWork: DispatchWorkItem?
    
    let dietOptions = ["Vegan", "Vegetarian", "Jain", "Halal", "Kosher", "Pescatarian"]
    let allergenOptions = ["Gluten", "Dairy", "Nuts", "Soy", "Eggs", "Shellfish", "Peanuts", "Tree Nuts", "Fish", "Sesame"]
    
    private let preferencesKey = "userPreferences"
    
    init() {
        loadPreferences()
    }
    
    func toggleDiet(_ diet: String) {
        let trimmed = diet.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        if preferences.selectedDiets.contains(key) {
            preferences.selectedDiets.remove(key)
            // remove from customDiets if present (case-insensitive)
            if let idx = preferences.customDiets.firstIndex(where: { $0.lowercased() == key }) {
                preferences.customDiets.remove(at: idx)
            }
        } else {
            preferences.selectedDiets.insert(key)
            // if this diet is not one of the standard options, treat it as custom
            let standardLower = dietOptions.map { $0.lowercased() }
            if !standardLower.contains(key) && !preferences.customDiets.contains(where: { $0.lowercased() == key }) {
                preferences.customDiets.append(trimmed)
            }
        }
    }
    
    func toggleAllergen(_ allergen: String) {
        let key = allergen.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if preferences.selectedAllergens.contains(key) {
            preferences.selectedAllergens.remove(key)
            // remove from customAllergens if present
            if let idx = preferences.customAllergens.firstIndex(of: key) {
                preferences.customAllergens.remove(at: idx)
            }
        } else {
            preferences.selectedAllergens.insert(key)
            // if this allergen is not one of the standard options, treat it as custom
            let standardLower = allergenOptions.map { $0.lowercased() }
            if !standardLower.contains(key) && !preferences.customAllergens.contains(key) {
                preferences.customAllergens.append(key)
            }
        }
    }
    
    private func savePreferences() {
        do {
            let encoded = try JSONEncoder().encode(preferences)
            UserDefaults.standard.set(encoded, forKey: preferencesKey)
        } catch {
            AppLogger.error("Failed to save preferences: \(error.localizedDescription)")
        }
    }

    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: preferencesKey) else { return }
        do {
            preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
        } catch {
            AppLogger.error("Failed to load preferences: \(error.localizedDescription)")
        }
    }

    // MARK: - Cloud Sync

    /// Debounced sync — waits 1.5s after last change before sending to backend.
    /// Prevents burst of network requests during rapid edits (typing, slider adjustments).
    private func debouncedSyncToBackend() {
        syncDebounceWork?.cancel()
        let prefsSnapshot = preferences
        let work = DispatchWorkItem {
            Task {
                await NetworkService.shared.syncPreferencesToBackend(prefsSnapshot)
            }
        }
        syncDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Pull preferences from backend (called once per app session for reinstall recovery).
    /// Only overwrites local prefs if local is empty (no diets/allergens selected).
    func pullFromBackendIfNeeded() {
        guard !hasPulledFromCloud else { return }
        hasPulledFromCloud = true

        let localHasData = !preferences.selectedDiets.isEmpty || !preferences.selectedAllergens.isEmpty

        Task {
            guard let cloudPrefs = await NetworkService.shared.pullPreferencesFromBackend() else { return }
            let cloudHasData = !cloudPrefs.selectedDiets.isEmpty || !cloudPrefs.selectedAllergens.isEmpty

            // Only overwrite if local is empty but cloud has data (reinstall recovery)
            if !localHasData && cloudHasData {
                await MainActor.run {
                    self.preferences = cloudPrefs
                }
                AppLogger.debug("☁️ Restored preferences from cloud backup")
            }
        }
    }
}
