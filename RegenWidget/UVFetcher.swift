//
//  UVFetcher.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 13.07.26.
//

import Foundation
import os

// MARK: - Tomorrow.io UV API Response Models

private struct TomorrowUVResponse: Codable {
    let data: TomorrowUVData
}

private struct TomorrowUVData: Codable {
    let timelines: [TomorrowUVTimeline]
}

private struct TomorrowUVTimeline: Codable {
    let timestep: String
    let intervals: [TomorrowUVInterval]
}

private struct TomorrowUVInterval: Codable {
    let startTime: String
    let values: TomorrowUVValues
}

private struct TomorrowUVValues: Codable {
    let uvIndex: Double
}

// MARK: - UV Fetcher

/// Fetches UV Index forecast data from the Tomorrow.io Timeline API at 5-minute resolution.
/// Always uses Tomorrow.io regardless of the active precipitation provider,
/// since BrightSky (DWD) does not provide UV data.
struct UVFetcher {

    private static let logger = Logger(
        subsystem: "sascha.RegenVorhersage.RegenWidget",
        category: "UVFetcher"
    )

    /// Number of 5-minute intervals to fetch (21 × 5 = 105 min, displayed as first 18 = 90 min).
    private static let intervalCount = 21

    func fetchUVIndex(lat: Double, lon: Double) async throws -> [UVPoint] {
        let location = "\(lat),\(lon)"

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://api.tomorrow.io/v4/timelines")!
        components.queryItems = [
            URLQueryItem(name: "location",  value: location),
            URLQueryItem(name: "fields",    value: "uvIndex"),
            URLQueryItem(name: "timesteps", value: "1h"),
            URLQueryItem(name: "startTime", value: isoFull.string(from: startOfDay)),
            URLQueryItem(name: "endTime",   value: isoFull.string(from: endOfDay)),
            URLQueryItem(name: "units",     value: "metric"),
            URLQueryItem(name: "apikey",    value: Secrets.tomorrowIOApiKey),
        ]

        guard let url = components.url else {
            Self.logger.error("❌ [UVFetcher] Failed to build URL")
            throw RadarFetchError.invalidURL
        }

        Self.logger.info("🌞 [UVFetcher] Fetching UV for lat=\(lat), lon=\(lon)")

        var request = URLRequest(url: url)
        request.setValue("application/json",   forHTTPHeaderField: "accept")
        request.setValue("gzip, deflate, br",  forHTTPHeaderField: "accept-encoding")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            Self.logger.info("🌞 [UVFetcher] HTTP \(http.statusCode)")
            guard http.statusCode == 200 else {
                Self.logger.error("❌ [UVFetcher] Non-200 status: \(http.statusCode)")
                throw RadarFetchError.httpError(http.statusCode)
            }
        }

        let uvResponse: TomorrowUVResponse
        do {
            uvResponse = try JSONDecoder().decode(TomorrowUVResponse.self, from: data)
        } catch {
            Self.logger.error("❌ [UVFetcher] Decode error: \(error.localizedDescription)")
            throw RadarFetchError.decodingError(error)
        }

        guard let timeline = uvResponse.data.timelines.first(where: { $0.timestep == "1h" }) else {
            Self.logger.warning("⚠️ [UVFetcher] No 1h timeline found")
            throw RadarFetchError.noData
        }

        let intervals = timeline.intervals
        guard !intervals.isEmpty else {
            throw RadarFetchError.noData
        }

        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        let now = Date()
        var points: [UVPoint] = []

        for (i, interval) in intervals.enumerated() {
            guard let ts = isoFull.date(from: interval.startTime)
                       ?? isoBasic.date(from: interval.startTime) else {
                Self.logger.warning("⚠️ [UVFetcher] Could not parse: \(interval.startTime)")
                continue
            }
            let minutesFromNow = Int(ts.timeIntervalSince(now) / 60.0)
            Self.logger.debug("🌞 [UVFetcher] [\(i)] UV=\(interval.values.uvIndex) T+\(minutesFromNow)m")
            points.append(UVPoint(timestamp: ts,
                                  uvIndex: interval.values.uvIndex,
                                  minutesFromNow: minutesFromNow))
        }

        // Find the active daylight hours
        let firstNonZero = points.firstIndex(where: { $0.uvIndex > 0 }) ?? 6
        let lastNonZero = points.lastIndex(where: { $0.uvIndex > 0 }) ?? min(18, points.count - 1)

        let startIndex = max(0, firstNonZero - 1)
        let endIndex = min(points.count - 1, lastNonZero + 1)
        
        let resultPoints = Array(points[startIndex...endIndex])

        let maxUV = resultPoints.map(\.uvIndex).max() ?? 0
        Self.logger.info("🌞 [UVFetcher] Parsed \(resultPoints.count) UV points, max=\(String(format: "%.1f", maxUV))")
        return resultPoints
    }
}
