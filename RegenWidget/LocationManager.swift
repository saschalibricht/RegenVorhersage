//
//  LocationManager.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 07.07.26.
//

import CoreLocation
import os

// MARK: - WidgetLocationManager

/// A lightweight CoreLocation wrapper for widget use.
/// Designed for one-shot location fetches using async/await.
final class WidgetLocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage.RegenWidget", category: "LocationManager")
    
    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // Sufficient for weather radar
        Self.logger.info("📍 [LocationManager] Initialized with kCLLocationAccuracyKilometer")
    }
    
    /// Fetches the current location asynchronously.
    /// Uses the last known location if available, otherwise requests a fresh location.
    /// - Returns: The user's current coordinates
    func getCurrentLocation() async throws -> CLLocationCoordinate2D {
        Self.logger.info("📍 [LocationManager] getCurrentLocation() called")
        
        // Check authorization status
        let status = locationManager.authorizationStatus
        Self.logger.info("📍 [LocationManager] Authorization status: \(status.rawValue)")
        
        switch status {
        case .notDetermined:
            Self.logger.warning("⚠️ [LocationManager] Authorization not determined — requesting when-in-use")
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            Self.logger.error("❌ [LocationManager] Authorization denied or restricted")
            throw RadarFetchError.locationUnavailable
        case .authorizedWhenInUse, .authorizedAlways:
            Self.logger.info("📍 [LocationManager] Authorization granted: \(status.rawValue)")
        @unknown default:
            Self.logger.warning("⚠️ [LocationManager] Unknown authorization status: \(status.rawValue)")
        }
        
        // Try to use cached location first (if less than 15 minutes old)
        if let cachedLocation = locationManager.location {
            let age = Date().timeIntervalSince(cachedLocation.timestamp)
            Self.logger.info("📍 [LocationManager] Cached location age: \(Int(age))s, coords: \(cachedLocation.coordinate.latitude), \(cachedLocation.coordinate.longitude)")
            
            if age < 900 { // 15 minutes
                Self.logger.info("📍 [LocationManager] Using cached location (age < 15min)")
                return cachedLocation.coordinate
            } else {
                Self.logger.info("📍 [LocationManager] Cached location too old, requesting fresh")
            }
        } else {
            Self.logger.info("📍 [LocationManager] No cached location available")
        }
        
        // Request a fresh location
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Self.logger.info("📍 [LocationManager] Requesting fresh location...")
            locationManager.requestLocation()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            Self.logger.error("❌ [LocationManager] didUpdateLocations called with empty array")
            continuation?.resume(throwing: RadarFetchError.locationUnavailable)
            continuation = nil
            return
        }
        
        Self.logger.info("📍 [LocationManager] Got location: \(location.coordinate.latitude), \(location.coordinate.longitude) (accuracy: \(location.horizontalAccuracy)m)")
        
        continuation?.resume(returning: location.coordinate)
        continuation = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.logger.error("❌ [LocationManager] Location error: \(error.localizedDescription)")
        
        // If we have a last known location, use it as fallback
        if let lastLocation = manager.location {
            Self.logger.warning("⚠️ [LocationManager] Using last known location as fallback: \(lastLocation.coordinate.latitude), \(lastLocation.coordinate.longitude)")
            continuation?.resume(returning: lastLocation.coordinate)
        } else {
            continuation?.resume(throwing: RadarFetchError.locationUnavailable)
        }
        continuation = nil
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Self.logger.info("📍 [LocationManager] Authorization changed to: \(manager.authorizationStatus.rawValue)")
    }
}
