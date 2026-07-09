//
//  TomorrowIOProvider.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 09.07.26.
//

import Foundation
import os

// MARK: - Tomorrow.io API Response Models

/// Top-level response from Tomorrow.io Timeline API
struct TomorrowResponse: Codable {
    let data: TomorrowData
}

struct TomorrowData: Codable {
    let timelines: [TomorrowTimeline]
}

struct TomorrowTimeline: Codable {
    let timestep: String
    let intervals: [TomorrowInterval]
}

struct TomorrowInterval: Codable {
    let startTime: String
    let values: TomorrowValues
}

struct TomorrowValues: Codable {
    /// Precipitation intensity in mm/hr (metric)
    let precipitationIntensity: Double
}

// MARK: - Tomorrow.io Provider

/// Fetches precipitation forecast data from the Tomorrow.io Timeline API.
/// Works globally, used as a fallback for locations outside Germany.
struct TomorrowIOProvider: PrecipitationProvider {
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage.RegenWidget", category: "TomorrowIOProvider")
    
    /// Number of 5-minute intervals to extract (21 × 5 = 105 minutes).
    private static let intervalCount = 21
    
    /// Conversion factor: Tomorrow.io returns mm/hr, we need mm per 5-minute interval.
    private static let intensityToDepthFactor = 5.0 / 60.0
    
    func fetchPrecipitation(lat: Double, lon: Double) async throws -> [PrecipitationPoint] {
        let location = "\(lat),\(lon)"
        
        var components = URLComponents(string: "https://api.tomorrow.io/v4/timelines")!
        components.queryItems = [
            URLQueryItem(name: "location", value: location),
            URLQueryItem(name: "fields", value: "precipitationIntensity"),
            URLQueryItem(name: "timesteps", value: "5m"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "apikey", value: Secrets.tomorrowIOApiKey),
        ]
        
        guard let url = components.url else {
            Self.logger.error("❌ [Tomorrow.io] Failed to build URL")
            throw RadarFetchError.invalidURL
        }
        
        Self.logger.info("📡 [Tomorrow.io] Starting fetch for lat=\(lat), lon=\(lon)")
        Self.logger.debug("📡 [Tomorrow.io] Full URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "accept-encoding")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.info("📡 [Tomorrow.io] HTTP status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                Self.logger.error("❌ [Tomorrow.io] Non-200 status: \(httpResponse.statusCode)")
                if let rawString = String(data: data, encoding: .utf8) {
                    Self.logger.error("❌ [Tomorrow.io] Error response: \(rawString)")
                }
                throw RadarFetchError.httpError(httpResponse.statusCode)
            }
        }
        
        Self.logger.debug("📡 [Tomorrow.io] Received \(data.count) bytes")
        
        // Log raw response for debugging (first 500 chars)
        if let rawString = String(data: data, encoding: .utf8) {
            let preview = String(rawString.prefix(500))
            Self.logger.debug("📡 [Tomorrow.io] Raw response preview: \(preview)")
        }
        
        // Decode the JSON response
        let tomorrowResponse: TomorrowResponse
        do {
            let decoder = JSONDecoder()
            tomorrowResponse = try decoder.decode(TomorrowResponse.self, from: data)
        } catch {
            Self.logger.error("❌ [Tomorrow.io] JSON decode error: \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                Self.logger.error("❌ [Tomorrow.io] Full raw response: \(rawString)")
            }
            throw RadarFetchError.decodingError(error)
        }
        
        // Find the 5m timeline in the response
        guard let timeline = tomorrowResponse.data.timelines.first(where: { $0.timestep == "5m" }) else {
            Self.logger.warning("⚠️ [Tomorrow.io] No 5m timeline found in response")
            throw RadarFetchError.noData
        }
        
        let intervals = Array(timeline.intervals.prefix(Self.intervalCount))
        Self.logger.info("📡 [Tomorrow.io] Using \(intervals.count) of \(timeline.intervals.count) intervals")
        
        if intervals.isEmpty {
            Self.logger.warning("⚠️ [Tomorrow.io] No intervals found in 5m timeline")
            throw RadarFetchError.noData
        }
        
        // Parse ISO8601 timestamps and convert intensity to depth
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Fallback formatter without fractional seconds
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]
        
        let now = Date()
        var points: [PrecipitationPoint] = []
        
        for (index, interval) in intervals.enumerated() {
            guard let timestamp = isoFormatter.date(from: interval.startTime)
                    ?? isoFormatterNoFrac.date(from: interval.startTime) else {
                Self.logger.warning("⚠️ [Tomorrow.io] Could not parse timestamp: \(interval.startTime)")
                continue
            }
            
            // Convert mm/hr intensity to mm depth over a 5-minute interval
            let precipitationMM = interval.values.precipitationIntensity * Self.intensityToDepthFactor
            let minutesFromNow = Int(timestamp.timeIntervalSince(now) / 60.0)
            
            Self.logger.debug("📡 [Tomorrow.io] Entry[\(index)]: \(interval.startTime) → \(String(format: "%.3f", precipitationMM))mm (T+\(minutesFromNow)min)")
            
            let point = PrecipitationPoint(
                timestamp: timestamp,
                precipitationMM: precipitationMM,
                minutesFromNow: minutesFromNow
            )
            points.append(point)
        }
        
        Self.logger.info("📡 [Tomorrow.io] Successfully parsed \(points.count) precipitation points")
        
        // Log summary
        let maxPrecip = points.map(\.precipitationMM).max() ?? 0
        let totalPrecip = points.map(\.precipitationMM).reduce(0, +)
        Self.logger.info("📡 [Tomorrow.io] Max precipitation: \(String(format: "%.3f", maxPrecip))mm, Total: \(String(format: "%.3f", totalPrecip))mm")
        
        return points
    }
}
