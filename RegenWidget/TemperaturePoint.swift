//
//  TemperaturePoint.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 27.09.26.
//

import Foundation

// MARK: - Temperature Data Point

/// A single hourly temperature forecast point.
/// Mirrors `UVPoint` in structure for consistent handling.
struct TemperaturePoint: Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let temperatureC: Double
    let minutesFromNow: Int
}
