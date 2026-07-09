//
//  RadarFetcher.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 07.07.26.
//

import Foundation
import os

// MARK: - API Response Models

/// Top-level response from BrightSky radar API
struct RadarResponse: Codable {
    let radar: [RadarEntry]
}

/// Single 5-minute radar interval
struct RadarEntry: Codable {
    let timestamp: String
    let source: String
    let precipitation_5: [[Double]]
}

// MARK: - Processed Data Model

/// Simplified precipitation data point for the widget
struct PrecipitationPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let precipitationMM: Double
    let minutesFromNow: Int
}

// MARK: - RadarFetcher

/// Fetches and parses precipitation radar data from the BrightSky API.
/// Uses Swift Concurrency (async/await).
final class RadarFetcher: Sendable {
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage.RegenWidget", category: "RadarFetcher")
    
    /// Number of 5-minute intervals to extract (21 × 5 = 105 minutes).
    /// We fetch 105 minutes because data is only refetched every 15 minutes,
    /// so 90 + 15 = 105 ensures the widget always has enough data.
    private static let intervalCount = 21
    
    /// Fetches precipitation data for the given coordinates.
    /// - Parameters:
    ///   - lat: Latitude
    ///   - lon: Longitude
    /// - Returns: Array of PrecipitationPoint for the next 21 intervals
    static func fetchPrecipitation(lat: Double, lon: Double) async throws -> [PrecipitationPoint] {
        let dateString = ISO8601DateFormatter().string(from: Date())
        let encodedDate = dateString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dateString
        
        let urlString = "https://api.brightsky.dev/radar?lat=\(lat)&lon=\(lon)&format=plain&distance=1&date=\(encodedDate)"
        
        logger.info("📡 [RadarFetcher] Starting fetch for lat=\(lat), lon=\(lon), date=\(dateString)")
        logger.debug("📡 [RadarFetcher] Full URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            logger.error("❌ [RadarFetcher] Invalid URL: \(urlString)")
            throw RadarFetchError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Log HTTP response details
        if let httpResponse = response as? HTTPURLResponse {
            logger.info("📡 [RadarFetcher] HTTP status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                logger.error("❌ [RadarFetcher] Non-200 status: \(httpResponse.statusCode)")
                throw RadarFetchError.httpError(httpResponse.statusCode)
            }
        }
        
        logger.debug("📡 [RadarFetcher] Received \(data.count) bytes")
        
        // Log raw response for debugging (first 500 chars)
        if let rawString = String(data: data, encoding: .utf8) {
            let preview = String(rawString.prefix(500))
            logger.debug("📡 [RadarFetcher] Raw response preview: \(preview)")
        }
        
        // Decode the JSON response
        let radarResponse: RadarResponse
        do {
            let decoder = JSONDecoder()
            radarResponse = try decoder.decode(RadarResponse.self, from: data)
            logger.info("📡 [RadarFetcher] Decoded \(radarResponse.radar.count) radar entries")
        } catch {
            logger.error("❌ [RadarFetcher] JSON decode error: \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                logger.error("❌ [RadarFetcher] Full raw response: \(rawString)")
            }
            throw RadarFetchError.decodingError(error)
        }
        
        // Extract the first N intervals
        let entries = Array(radarResponse.radar.prefix(intervalCount))
        logger.info("📡 [RadarFetcher] Using \(entries.count) of \(radarResponse.radar.count) entries")
        
        if entries.isEmpty {
            logger.warning("⚠️ [RadarFetcher] No radar entries found in response")
            throw RadarFetchError.noData
        }
        
        // Parse ISO8601 timestamps and extract precipitation values
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        
        let now = Date()
        var points: [PrecipitationPoint] = []
        
        for (index, entry) in entries.enumerated() {
            guard let timestamp = isoFormatter.date(from: entry.timestamp) else {
                logger.warning("⚠️ [RadarFetcher] Could not parse timestamp: \(entry.timestamp)")
                continue
            }
            
            // precipitation_5 is [[Double]] — extract the first (and typically only) value
            let precipitation: Double
            if let firstRow = entry.precipitation_5.first, let firstValue = firstRow.first {
                precipitation = firstValue
            } else {
                logger.warning("⚠️ [RadarFetcher] Empty precipitation_5 at index \(index)")
                precipitation = 0.0
            }
            
            let minutesFromNow = Int(timestamp.timeIntervalSince(now) / 60.0)
            
            logger.debug("📡 [RadarFetcher] Entry[\(index)]: \(entry.timestamp) → \(precipitation)mm (T+\(minutesFromNow)min)")
            
            let point = PrecipitationPoint(
                timestamp: timestamp,
                precipitationMM: precipitation,
                minutesFromNow: minutesFromNow
            )
            points.append(point)
        }
        
        logger.info("📡 [RadarFetcher] Successfully parsed \(points.count) precipitation points")
        
        // Log summary
        let maxPrecip = points.map(\.precipitationMM).max() ?? 0
        let totalPrecip = points.map(\.precipitationMM).reduce(0, +)
        logger.info("📡 [RadarFetcher] Max precipitation: \(maxPrecip)mm, Total: \(totalPrecip)mm")
        
        return points
    }
}

// MARK: - Error Types

enum RadarFetchError: Error, LocalizedError {
    case invalidURL
    case httpError(Int)
    case decodingError(Error)
    case noData
    case locationUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .noData:
            return "No radar data available"
        case .locationUnavailable:
            return "Location unavailable"
        }
    }
}
