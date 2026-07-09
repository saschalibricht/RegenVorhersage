//
//  SharedLocationStore.swift
//  RegenVorhersage
//
//  Created by Sascha Libricht on 09.07.26.
//

import CoreLocation
import os

// MARK: - Shared Location Store

/// Persists the user's location preference (automatic vs. manual) in an App Group
/// so both the main app and the widget extension can access the same setting.
///
/// Data is stored in `UserDefaults(suiteName:)` under the shared app group.
enum SharedLocationStore {
    
    /// The App Group identifier shared between the main app and the widget extension.
    /// Must match the value in both targets' entitlements files.
    static let appGroupID = "group.sascha.RegenVorhersage"
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage", category: "SharedLocationStore")
    
    // UserDefaults keys
    private static let isManualKey = "manualLocation_isManual"
    private static let latitudeKey = "manualLocation_latitude"
    private static let longitudeKey = "manualLocation_longitude"
    private static let nameKey = "manualLocation_name"
    
    /// The shared UserDefaults suite for the app group.
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    // MARK: - Read
    
    /// Whether a manual location is currently set.
    static var isManualLocation: Bool {
        sharedDefaults?.bool(forKey: isManualKey) ?? false
    }
    
    /// The manually set coordinate, or `nil` if using automatic (GPS) location.
    static var manualCoordinate: CLLocationCoordinate2D? {
        guard isManualLocation,
              let defaults = sharedDefaults,
              defaults.object(forKey: latitudeKey) != nil,
              defaults.object(forKey: longitudeKey) != nil else {
            return nil
        }
        let lat = defaults.double(forKey: latitudeKey)
        let lon = defaults.double(forKey: longitudeKey)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// The display name for the manually set location, or `nil`.
    static var manualLocationName: String? {
        guard isManualLocation else { return nil }
        return sharedDefaults?.string(forKey: nameKey)
    }
    
    // MARK: - Write
    
    /// Saves a manual location to the shared store.
    static func setManualLocation(coordinate: CLLocationCoordinate2D, name: String) {
        guard let defaults = sharedDefaults else {
            logger.error("❌ [SharedLocationStore] Could not access shared UserDefaults for group: \(appGroupID)")
            return
        }
        defaults.set(true, forKey: isManualKey)
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
        defaults.set(name, forKey: nameKey)
        logger.info("📍 [SharedLocationStore] Saved manual location: \(name) (\(coordinate.latitude), \(coordinate.longitude))")
    }
    
    /// Clears the manual location, reverting to automatic (GPS) mode.
    static func clearManualLocation() {
        guard let defaults = sharedDefaults else {
            logger.error("❌ [SharedLocationStore] Could not access shared UserDefaults for group: \(appGroupID)")
            return
        }
        defaults.set(false, forKey: isManualKey)
        defaults.removeObject(forKey: latitudeKey)
        defaults.removeObject(forKey: longitudeKey)
        defaults.removeObject(forKey: nameKey)
        logger.info("📍 [SharedLocationStore] Cleared manual location, reverting to GPS")
    }
}
