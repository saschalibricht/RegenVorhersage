//
//  TemperatureFetcher.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 27.09.26.
//

import Foundation
import os

// MARK: - Tomorrow.io Temperature API Response Models

private struct TomorrowTemperatureResponse: Codable {
    let data: TomorrowTemperatureData
}

private struct TomorrowTemperatureData: Codable {
    let timelines: [TomorrowTemperatureTimeline]
}

private struct TomorrowTemperatureTimeline: Codable {
    let timestep: String
    let intervals: [TomorrowTemperatureInterval]
}

private struct TomorrowTemperatureInterval: Codable {
    let startTime: String
    let values: TomorrowTemperatureValues
}

private struct TomorrowTemperatureValues: Codable {
    let temperature: Double
}

// MARK: - Temperature Fetcher

/// Fetches hourly temperature forecast data from the Tomorrow.io Timeline API.
/// Like `UVFetcher`, this always uses Tomorrow.io regardless of the active precipitation provider.
struct TemperatureFetcher {

    private static let logger = Logger(
        subsystem: "sascha.RegenVorhersage.RegenWidget",
        category: "TemperatureFetcher"
    )

    /// Number of hours to show after the current hour (current hour + 12 = 13 bars).
    private static let hoursAhead = 12

    func fetchTemperature(lat: Double, lon: Double) async throws -> [TemperaturePoint] {
        let location = "\(lat),\(lon)"

        let calendar = Calendar.current
        let now = Date()
        // Start at the beginning of the current hour so the first bar covers "now"
        let startOfHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let endTime = calendar.date(byAdding: .hour, value: Self.hoursAhead, to: startOfHour)!
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://api.tomorrow.io/v4/timelines")!
        components.queryItems = [
            URLQueryItem(name: "location",  value: location),
            URLQueryItem(name: "fields",    value: "temperature"),
            URLQueryItem(name: "timesteps", value: "1h"),
            URLQueryItem(name: "startTime", value: isoFull.string(from: startOfHour)),
            URLQueryItem(name: "endTime",   value: isoFull.string(from: endTime)),
            URLQueryItem(name: "units",     value: "metric"),
            URLQueryItem(name: "apikey",    value: Secrets.tomorrowIOApiKey),
        ]

        guard let url = components.url else {
            Self.logger.error("❌ [TemperatureFetcher] Failed to build URL")
            throw RadarFetchError.invalidURL
        }

        Self.logger.info("🌡️ [TemperatureFetcher] Fetching temperature for lat=\(lat), lon=\(lon)")

        var request = URLRequest(url: url)
        request.setValue("application/json",   forHTTPHeaderField: "accept")
        request.setValue("gzip, deflate, br",  forHTTPHeaderField: "accept-encoding")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            Self.logger.info("🌡️ [TemperatureFetcher] HTTP \(http.statusCode)")
            guard http.statusCode == 200 else {
                Self.logger.error("❌ [TemperatureFetcher] Non-200 status: \(http.statusCode)")
                throw RadarFetchError.httpError(http.statusCode)
            }
        }

        let tempResponse: TomorrowTemperatureResponse
        do {
            tempResponse = try JSONDecoder().decode(TomorrowTemperatureResponse.self, from: data)
        } catch {
            Self.logger.error("❌ [TemperatureFetcher] Decode error: \(error.localizedDescription)")
            throw RadarFetchError.decodingError(error)
        }

        guard let timeline = tempResponse.data.timelines.first(where: { $0.timestep == "1h" }),
              !timeline.intervals.isEmpty else {
            Self.logger.warning("⚠️ [TemperatureFetcher] No 1h timeline found")
            throw RadarFetchError.noData
        }

        var points: [TemperaturePoint] = []

        for (i, interval) in timeline.intervals.enumerated() {
            guard let ts = isoFull.date(from: interval.startTime) else {
                Self.logger.warning("⚠️ [TemperatureFetcher] Could not parse: \(interval.startTime)")
                continue
            }
            let minutesFromNow = Int(ts.timeIntervalSince(now) / 60.0)
            Self.logger.debug("🌡️ [TemperatureFetcher] [\(i)] T=\(interval.values.temperature) T+\(minutesFromNow)m")
            points.append(TemperaturePoint(timestamp: ts,
                                           temperatureC: interval.values.temperature,
                                           minutesFromNow: minutesFromNow))
        }

        let maxT = points.map(\.temperatureC).max() ?? 0
        let minT = points.map(\.temperatureC).min() ?? 0
        Self.logger.info("🌡️ [TemperatureFetcher] Parsed \(points.count) points, min=\(String(format: "%.1f", minT)) max=\(String(format: "%.1f", maxT))")
        return points
    }
}
