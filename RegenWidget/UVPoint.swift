//
//  UVPoint.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 13.07.26.
//

import Foundation

// MARK: - UV Index Data Point

/// A single UV Index forecast point at a specific 5-minute interval.
/// Mirrors `PrecipitationPoint` in structure for consistent handling.
struct UVPoint: Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let uvIndex: Double
    let minutesFromNow: Int
}
