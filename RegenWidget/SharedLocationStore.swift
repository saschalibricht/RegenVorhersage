//
//  SharedLocationStore.swift
//  RegenVorhersage
//
//  Created by Sascha Libricht on 09.07.26.
//

import CoreLocation
import os

// MARK: - Widget Display Mode

/// Determines what data the widget chart displays.
/// `AppEnum` conformance is added in `WidgetConfigIntent.swift` (widget target only),
/// so the main app can use this type without importing AppIntents.
enum WidgetMode: String, CaseIterable, Sendable {
    case rain = "rain"
    case uv   = "uv"
}

// MARK: - Shared Location Store

/// Persists the user's location preference (automatic vs. manual) in an App Group
/// so both the main app and the widget extension can access the same setting.
///
/// Data is stored in `UserDefaults(suiteName:)` under the shared app group.
enum SharedLocationStore {
    
    /// The App Group identifier shared between the main app and the widget extension.
    /// Resolved dynamically at runtime to match the resigned entitlements in sideloaded IPAs.
    static var appGroupID: String {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return "group.sascha.RegenVorhersage"
        }
        
        var mainBundleID = bundleID
        if mainBundleID.hasSuffix(".RegenWidget") {
            mainBundleID = String(mainBundleID.dropLast(".RegenWidget".count))
        } else if mainBundleID.hasSuffix(".RegenWidgetExtension") {
            mainBundleID = String(mainBundleID.dropLast(".RegenWidgetExtension".count))
        }
        
        return "group.\(mainBundleID)"
    }
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage", category: "SharedLocationStore")
    
    // UserDefaults keys
    private static let isManualKey = "manualLocation_isManual"
    private static let latitudeKey = "manualLocation_latitude"
    private static let longitudeKey = "manualLocation_longitude"
    private static let nameKey = "manualLocation_name"
    static let updateIntervalKey      = "settings_updateInterval"
    /// Stores the currently active widget mode ("rain" or "uv").
    static let widgetModeKey            = "settings_widgetMode"
    /// Stores the last intent mode seen by the widget — used to detect genuine long-press changes.
    static let lastWidgetIntentModeKey  = "settings_lastWidgetIntentMode"
    
    /// The shared UserDefaults suite for the app group.
    /// Falls back to standard UserDefaults if the app group container is not available.
    private static var sharedDefaults: UserDefaults {
        let identifier = appGroupID
        if let shared = UserDefaults(suiteName: identifier) {
            return shared
        }
        logger.error("⚠️ [SharedLocationStore] Could not access shared UserDefaults for group: \(identifier). Falling back to UserDefaults.standard.")
        return UserDefaults.standard
    }
    
    // MARK: - Read
    
    /// Whether a manual location is currently set.
    static var isManualLocation: Bool {
        sharedDefaults.bool(forKey: isManualKey)
    }
    
    /// The manually set coordinate, or `nil` if using automatic (GPS) location.
    static var manualCoordinate: CLLocationCoordinate2D? {
        let defaults = sharedDefaults
        guard isManualLocation,
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
        return sharedDefaults.string(forKey: nameKey)
    }
    
    /// The user-configured update interval in minutes (default 15)
    static var updateIntervalMinutes: Int {
        let val = sharedDefaults.integer(forKey: updateIntervalKey)
        return val > 0 ? val : 15
    }

    /// The active widget display mode (rain or UV). Defaults to rain.
    static var widgetMode: String {
        get { sharedDefaults.string(forKey: widgetModeKey) ?? WidgetMode.rain.rawValue }
        set { sharedDefaults.set(newValue, forKey: widgetModeKey) }
    }

    /// The last intent mode the widget observed — used to detect long-press configuration changes.
    static var lastWidgetIntentMode: String {
        get { sharedDefaults.string(forKey: lastWidgetIntentModeKey) ?? WidgetMode.rain.rawValue }
        set { sharedDefaults.set(newValue, forKey: lastWidgetIntentModeKey) }
    }
    
    // MARK: - Write
    
    /// Saves a manual location to the shared store.
    static func setManualLocation(coordinate: CLLocationCoordinate2D, name: String) {
        let defaults = sharedDefaults
        defaults.set(true, forKey: isManualKey)
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
        defaults.set(name, forKey: nameKey)
        logger.info("📍 [SharedLocationStore] Saved manual location: \(name) (\(coordinate.latitude), \(coordinate.longitude))")
    }
    
    /// Clears the manual location, reverting to automatic (GPS) mode.
    static func clearManualLocation() {
        let defaults = sharedDefaults
        defaults.set(false, forKey: isManualKey)
        defaults.removeObject(forKey: latitudeKey)
        defaults.removeObject(forKey: longitudeKey)
        defaults.removeObject(forKey: nameKey)
        logger.info("📍 [SharedLocationStore] Cleared manual location, reverting to GPS")
    }
}
