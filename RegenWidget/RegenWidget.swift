//
//  RegenWidget.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 07.07.26.
//

import WidgetKit
import SwiftUI
import CoreLocation
import os

// MARK: - Timeline Entry

struct RegenEntry: TimelineEntry {
    let date: Date
    let precipitationPoints: [PrecipitationPoint]
    let errorMessage: String?
    let debugInfo: String
    let locality: String?
    
    /// Placeholder entry for widget gallery
    static var placeholder: RegenEntry {
        let now = Date()
        let points = (0..<18).map { i in
            PrecipitationPoint(
                timestamp: now.addingTimeInterval(Double(i * 300)),
                precipitationMM: [0, 0, 0.2, 0.5, 1.0, 2.5, 1.5, 0.8, 0.3, 0, 0, 0, 0, 0.1, 0.4, 0, 0, 0][i],
                minutesFromNow: i * 5
            )
        }
        return RegenEntry(date: now, precipitationPoints: points, errorMessage: nil, debugInfo: "Placeholder", locality: "")
    }
}

// MARK: - Timeline Provider

struct RegenTimelineProvider: TimelineProvider {
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage.RegenWidget", category: "TimelineProvider")
    
    func placeholder(in context: Context) -> RegenEntry {
        Self.logger.info("🔄 [TimelineProvider] placeholder() called")
        return RegenEntry.placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (RegenEntry) -> Void) {
        Self.logger.info("🔄 [TimelineProvider] getSnapshot() called, isPreview=\(context.isPreview)")
        
        if context.isPreview {
            completion(RegenEntry.placeholder)
            return
        }
        
        Task {
            let entry = await fetchRadarEntry()
            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<RegenEntry>) -> Void) {
        Self.logger.info("🔄 [TimelineProvider] getTimeline() called, family=\(context.family.description)")
        
        Task {
            let entry = await fetchRadarEntry()
            
            // Reload based on user configuration
            let interval = SharedLocationStore.updateIntervalMinutes
            let reloadDate = Calendar.current.date(byAdding: .minute, value: interval, to: Date())!
            Self.logger.info("🔄 [TimelineProvider] Next reload scheduled at: \(reloadDate) (in \(interval) min)")
            
            let timeline = Timeline(entries: [entry], policy: .after(reloadDate))
            completion(timeline)
        }
    }
    
    /// Fetches location + radar data, returning a single timeline entry.
    /// Checks for a manually set location in SharedLocationStore first,
    /// then falls back to GPS if no manual location is configured.
    private func fetchRadarEntry() async -> RegenEntry {
        Self.logger.info("🔄 [TimelineProvider] fetchRadarEntry() starting...")
        let startTime = Date()
        
        do {
            // Step 1: Determine location (manual override or GPS)
            let coordinate: CLLocationCoordinate2D
            var locality: String? = nil
            
            if let manualCoord = SharedLocationStore.manualCoordinate {
                // Use the manually set location from the app
                coordinate = manualCoord
                locality = SharedLocationStore.manualLocationName
                Self.logger.info("🔄 [TimelineProvider] Step 1: Using manual location: \(coordinate.latitude), \(coordinate.longitude) (\(locality ?? "unknown"))")
            } else {
                // Fall back to GPS
                Self.logger.info("🔄 [TimelineProvider] Step 1: Fetching GPS location...")
                let locationManager = WidgetLocationManager()
                coordinate = try await locationManager.getCurrentLocation()
                Self.logger.info("🔄 [TimelineProvider] GPS location obtained: \(coordinate.latitude), \(coordinate.longitude)")
                
                // Reverse geocode for GPS-based locality
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let geocoder = CLGeocoder()
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    locality = placemarks.first?.locality ?? placemarks.first?.name
                } catch {
                    Self.logger.error("🔄 [TimelineProvider] Reverse geocoding failed: \(error.localizedDescription)")
                }
            }
            
            // Step 2: Select provider and fetch precipitation data
            let provider = PrecipitationProviderFactory.provider(for: coordinate)
            let providerName = PrecipitationProviderFactory.isInGermany(coordinate) ? "BrightSky" : "Tomorrow.io"
            Self.logger.info("🔄 [TimelineProvider] Step 2: Fetching precipitation via \(providerName)...")
            let points = try await provider.fetchPrecipitation(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
            
            let elapsed = Date().timeIntervalSince(startTime)
            Self.logger.info("🔄 [TimelineProvider] ✅ Success: \(points.count) points in \(String(format: "%.2f", elapsed))s")
            
            let debugInfo = "OK: \(points.count)pts @ \(String(format: "%.2f", coordinate.latitude)),\(String(format: "%.2f", coordinate.longitude)) (\(String(format: "%.1f", elapsed))s)"
            
            return RegenEntry(
                date: Date(),
                precipitationPoints: points,
                errorMessage: nil,
                debugInfo: debugInfo,
                locality: locality
            )
            
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            Self.logger.error("🔄 [TimelineProvider] ❌ Error after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            
            return RegenEntry(
                date: Date(),
                precipitationPoints: [],
                errorMessage: error.localizedDescription,
                debugInfo: "ERR: \(error.localizedDescription)",
                locality: nil
            )
        }
    }
}

// MARK: - Widget Entry View

struct RegenWidgetEntryView: View {
    var entry: RegenEntry
    
    @Environment(\.widgetFamily) var family
    
    /// We display the first 18 intervals (18 × 5 = 90 minutes) from the fetched data.
    private var displayPoints: [PrecipitationPoint] {
        Array(entry.precipitationPoints.prefix(18))
    }
    
    /// Maximum precipitation across displayed points, used for sensible scaling.
    private var yAxisMax: Double {
        let maxVal = displayPoints.map(\.precipitationMM).max() ?? 0
        if maxVal <= 10.0 { return 10.0 }
        if maxVal <= 20.0 { return 20.0 }
        return ceil(maxVal / 10.0) * 10.0
    }
    
    /// Whether there is any rain forecast in the next 90 minutes.
    private var hasRainInNext90Mins: Bool {
        displayPoints.contains(where: { $0.precipitationMM > 0 })
    }
    
    private func timeString(for index: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if index < displayPoints.count {
            return formatter.string(from: displayPoints[index].timestamp)
        }
        // Fallback for projected time
        let fallbackDate = entry.date.addingTimeInterval(TimeInterval(index * 5 * 60))
        return formatter.string(from: fallbackDate)
    }
    
    private var refreshTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.date)
    }
    
    var body: some View {
        if let errorMessage = entry.errorMessage {
            errorView(errorMessage)
        } else if displayPoints.isEmpty {
            errorView("Keine Daten")
        } else {
            radarChartView
        }
    }
    
    // MARK: - Chart View
    
    private var radarChartView: some View {
        VStack(spacing: 2) {
            // Minimal title row
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(entry.locality ?? "")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text(refreshTimeString)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            
            // Bar chart area
            GeometryReader { geometry in
                let chartHeight = max(0, geometry.size.height - 28)
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        // Background Grid & Y-Axis Label
                        VStack(spacing: 0) {
                            if hasRainInNext90Mins {
                                HStack(spacing: 4) {
                                    Text("\(String(format: "%g", yAxisMax)) mm")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "cloud.rain")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.3))
                                        .frame(height: 0.5)
                                }
                                .padding(.top, 6)
                            }
                            
                            Spacer()
                            
                            Divider().background(Color.secondary.opacity(0.3))
                        }
                        .frame(height: chartHeight)
                        
                        // Bars
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(Array(displayPoints.enumerated()), id: \.element.id) { index, point in
                                barColumn(for: point, maxHeight: chartHeight - 24)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // X-axis tick labels every 30 minutes (indices 0, 6, 12, 18)
                    GeometryReader { labelGeo in
                        let w = labelGeo.size.width
                        let wb = (w - 17.0) / 18.0
                        
                        ZStack(alignment: .topLeading) {
                            // Tick marks
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 4)
                                .offset(x: 0.5 * wb, y: 0)
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 4)
                                .offset(x: 6.0 * (wb + 1.0) + 0.5 * wb, y: 0)
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 4)
                                .offset(x: 12.0 * (wb + 1.0) + 0.5 * wb, y: 0)
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: 4)
                                .offset(x: 17.0 * (wb + 1.0) + 0.5 * wb, y: 0)
                            
                            // 0 min
                            Text(timeString(for: 0))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .rotationEffect(.degrees(-45), anchor: .topTrailing)
                                .offset(x: 0.5 * wb - 40.0, y: 4)
                            
                            // 30 min
                            Text(timeString(for: 6))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .rotationEffect(.degrees(-45), anchor: .topTrailing)
                                .offset(x: 6.0 * (wb + 1.0) + 0.5 * wb - 40.0, y: 4)
                            
                            // 60 min
                            Text(timeString(for: 12))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .rotationEffect(.degrees(-45), anchor: .topTrailing)
                                .offset(x: 12.0 * (wb + 1.0) + 0.5 * wb - 40.0, y: 4)
                            
                            // 90 min
                            Text(timeString(for: 18))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .rotationEffect(.degrees(-45), anchor: .topTrailing)
                                .offset(x: 17.0 * (wb + 1.0) + 0.5 * wb - 40.0, y: 4)
                        }
                    }
                    .frame(height: 28)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
    
    // MARK: - Bar Column
    
    private func barColumn(for point: PrecipitationPoint, maxHeight: CGFloat) -> some View {
        let hasRain = point.precipitationMM > 0
        let baseline = maxHeight * 0.1
        
        let height: CGFloat = hasRain
            ? baseline + CGFloat(point.precipitationMM / yAxisMax) * (maxHeight - baseline)
            : baseline
        
        return RoundedRectangle(cornerRadius: 2)
            .fill(hasRain ? Color.blue : Color.gray.opacity(0.3))
            .frame(height: height)
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.icloud")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Widget Configuration

struct RegenWidget: Widget {
    let kind: String = "RegenWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RegenTimelineProvider()) { entry in
            if #available(iOS 17.0, *) {
                RegenWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                RegenWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Regenradar")
        .description("Niederschlagsvorhersage für die nächsten 90 Minuten")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    RegenWidget()
} timeline: {
    RegenEntry.placeholder
}

#Preview(as: .systemMedium) {
    RegenWidget()
} timeline: {
    RegenEntry.placeholder
}
