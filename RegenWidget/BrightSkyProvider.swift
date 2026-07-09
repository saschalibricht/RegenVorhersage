//
//  BrightSkyProvider.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 09.07.26.
//

import Foundation
import os

// MARK: - BrightSky API Response Models

/// Top-level response from BrightSky radar API
struct BrightSkyRadarResponse: Codable {
    let radar: [BrightSkyRadarEntry]
}

/// Single 5-minute radar interval from BrightSky
struct BrightSkyRadarEntry: Codable {
    let timestamp: String
    let source: String
    let precipitation_5: [[Double]]
}

// MARK: - BrightSky Provider

/// Fetches precipitation radar data from the BrightSky (DWD) API.
/// Only works reliably within Germany.
struct BrightSkyProvider: PrecipitationProvider {
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage.RegenWidget", category: "BrightSkyProvider")
    
    /// Number of 5-minute intervals to extract (21 × 5 = 105 minutes).
    /// We fetch 105 minutes because data is only refetched every 15 minutes,
    /// so 90 + 15 = 105 ensures the widget always has enough data.
    private static let intervalCount = 21
    
    func fetchPrecipitation(lat: Double, lon: Double) async throws -> [PrecipitationPoint] {
        let dateString = ISO8601DateFormatter().string(from: Date())
        let encodedDate = dateString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dateString
        
        let urlString = "https://api.brightsky.dev/radar?lat=\(lat)&lon=\(lon)&format=plain&distance=1&date=\(encodedDate)"
        
        Self.logger.info("📡 [BrightSky] Starting fetch for lat=\(lat), lon=\(lon), date=\(dateString)")
        Self.logger.debug("📡 [BrightSky] Full URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            Self.logger.error("❌ [BrightSky] Invalid URL: \(urlString)")
            throw RadarFetchError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.info("📡 [BrightSky] HTTP status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                Self.logger.error("❌ [BrightSky] Non-200 status: \(httpResponse.statusCode)")
                throw RadarFetchError.httpError(httpResponse.statusCode)
            }
        }
        
        Self.logger.debug("📡 [BrightSky] Received \(data.count) bytes")
        
        // Log raw response for debugging (first 500 chars)
        if let rawString = String(data: data, encoding: .utf8) {
            let preview = String(rawString.prefix(500))
            Self.logger.debug("📡 [BrightSky] Raw response preview: \(preview)")
        }
        
        // Decode the JSON response
        let radarResponse: BrightSkyRadarResponse
        do {
            let decoder = JSONDecoder()
            radarResponse = try decoder.decode(BrightSkyRadarResponse.self, from: data)
            Self.logger.info("📡 [BrightSky] Decoded \(radarResponse.radar.count) radar entries")
        } catch {
            Self.logger.error("❌ [BrightSky] JSON decode error: \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                Self.logger.error("❌ [BrightSky] Full raw response: \(rawString)")
            }
            throw RadarFetchError.decodingError(error)
        }
        
        // Extract the first N intervals
        let entries = Array(radarResponse.radar.prefix(Self.intervalCount))
        Self.logger.info("📡 [BrightSky] Using \(entries.count) of \(radarResponse.radar.count) entries")
        
        if entries.isEmpty {
            Self.logger.warning("⚠️ [BrightSky] No radar entries found in response")
            throw RadarFetchError.noData
        }
        
        // Parse ISO8601 timestamps and extract precipitation values
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        
        let now = Date()
        var points: [PrecipitationPoint] = []
        
        for (index, entry) in entries.enumerated() {
            guard let timestamp = isoFormatter.date(from: entry.timestamp) else {
                Self.logger.warning("⚠️ [BrightSky] Could not parse timestamp: \(entry.timestamp)")
                continue
            }
            
            // precipitation_5 is [[Double]] — extract the first (and typically only) value
            let precipitation: Double
            if let firstRow = entry.precipitation_5.first, let firstValue = firstRow.first {
                precipitation = firstValue
            } else {
                Self.logger.warning("⚠️ [BrightSky] Empty precipitation_5 at index \(index)")
                precipitation = 0.0
            }
            
            let minutesFromNow = Int(timestamp.timeIntervalSince(now) / 60.0)
            
            Self.logger.debug("📡 [BrightSky] Entry[\(index)]: \(entry.timestamp) → \(precipitation)mm (T+\(minutesFromNow)min)")
            
            let point = PrecipitationPoint(
                timestamp: timestamp,
                precipitationMM: precipitation,
                minutesFromNow: minutesFromNow
            )
            points.append(point)
        }
        
        Self.logger.info("📡 [BrightSky] Successfully parsed \(points.count) precipitation points")
        
        // Log summary
        let maxPrecip = points.map(\.precipitationMM).max() ?? 0
        let totalPrecip = points.map(\.precipitationMM).reduce(0, +)
        Self.logger.info("📡 [BrightSky] Max precipitation: \(maxPrecip)mm, Total: \(totalPrecip)mm")
        
        return points
    }
}
