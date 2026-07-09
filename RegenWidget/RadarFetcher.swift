//
//  RadarFetcher.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 07.07.26.
//

import Foundation

// MARK: - Processed Data Model

/// Simplified precipitation data point for the widget.
/// Shared across all providers (BrightSky, Tomorrow.io, etc.).
struct PrecipitationPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let precipitationMM: Double
    let minutesFromNow: Int
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
