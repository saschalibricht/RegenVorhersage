//
//  PrecipitationProvider.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 09.07.26.
//

import CoreLocation

// MARK: - Precipitation Provider Protocol

/// Abstraction over different precipitation data sources (BrightSky, Tomorrow.io, etc.).
/// Each provider fetches precipitation data for a given coordinate and returns
/// a uniform `[PrecipitationPoint]` array.
protocol PrecipitationProvider {
    /// Fetches precipitation forecast data for the given coordinates.
    /// - Parameters:
    ///   - lat: Latitude
    ///   - lon: Longitude
    /// - Returns: Array of `PrecipitationPoint` for the next ~105 minutes (21 × 5-min intervals)
    func fetchPrecipitation(lat: Double, lon: Double) async throws -> [PrecipitationPoint]
}

// MARK: - Provider Factory

/// Selects the appropriate `PrecipitationProvider` based on the user's location.
/// Uses BrightSky (DWD radar) inside Germany and Tomorrow.io everywhere else.
enum PrecipitationProviderFactory {
    
    // Germany bounding box (generous margins)
    private static let germanyLatRange: ClosedRange<Double> = 47.0...55.1
    private static let germanyLonRange: ClosedRange<Double> = 5.8...15.1
    
    /// Returns `true` if the coordinate falls within Germany's bounding box.
    static func isInGermany(_ coordinate: CLLocationCoordinate2D) -> Bool {
        germanyLatRange.contains(coordinate.latitude) && germanyLonRange.contains(coordinate.longitude)
    }
    
    /// Returns the appropriate precipitation provider for the given coordinate.
    static func provider(for coordinate: CLLocationCoordinate2D) -> PrecipitationProvider {
        if isInGermany(coordinate) {
            return BrightSkyProvider()
        } else {
            return TomorrowIOProvider()
        }
    }
}
