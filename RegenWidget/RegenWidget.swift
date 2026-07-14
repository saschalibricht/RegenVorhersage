//
//  RegenWidget.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 07.07.26.
//

import WidgetKit
import SwiftUI
import AppIntents
import CoreLocation
import os

// MARK: - Timeline Entry

struct RegenEntry: TimelineEntry {
    let date: Date
    let precipitationPoints: [PrecipitationPoint]
    let uvPoints: [UVPoint]
    let widgetMode: WidgetMode
    let errorMessage: String?
    let debugInfo: String
    let locality: String?

    /// Placeholder entry for widget gallery
    static var placeholder: RegenEntry {
        let now = Date()
        let precip = (0..<18).map { i in
            PrecipitationPoint(
                timestamp: now.addingTimeInterval(Double(i * 300)),
                precipitationMM: [0, 0, 0.2, 0.5, 1.0, 2.5, 1.5, 0.8, 0.3, 0, 0, 0, 0, 0.1, 0.4, 0, 0, 0][i],
                minutesFromNow: i * 5
            )
        }
        let uv = (0..<18).map { i in
            UVPoint(
                timestamp: now.addingTimeInterval(Double(i * 300)),
                uvIndex: [3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0, 3.5][i],
                minutesFromNow: i * 5
            )
        }
        return RegenEntry(
            date: now,
            precipitationPoints: precip,
            uvPoints: uv,
            widgetMode: .rain,
            errorMessage: nil,
            debugInfo: "Placeholder",
            locality: ""
        )
    }
}

// MARK: - Timeline Provider (AppIntentTimelineProvider)

struct RegenTimelineProvider: AppIntentTimelineProvider {
    typealias Entry  = RegenEntry
    typealias Intent = ConfigurationAppIntent

    private static let logger = Logger(
        subsystem: "sascha.RegenVorhersage.RegenWidget",
        category: "TimelineProvider"
    )

    func placeholder(in context: Context) -> RegenEntry {
        Self.logger.info("🔄 [TimelineProvider] placeholder() called")
        return RegenEntry.placeholder
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> RegenEntry {
        Self.logger.info("🔄 [TimelineProvider] snapshot() isPreview=\(context.isPreview)")
        guard !context.isPreview else { return RegenEntry.placeholder }
        return await fetchEntry(configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<RegenEntry> {
        Self.logger.info("🔄 [TimelineProvider] timeline() called")
        let entry = await fetchEntry(configuration: configuration)
        let interval = entry.widgetMode == .uv ? 60 : SharedLocationStore.updateIntervalMinutes
        let reloadDate = Calendar.current.date(byAdding: .minute, value: interval, to: Date())!
        Self.logger.info("🔄 [TimelineProvider] Next reload in \(interval) min at \(reloadDate)")
        return Timeline(entries: [entry], policy: .after(reloadDate))
    }

    // MARK: - Mode Resolution

    private func resolveMode(configuration: ConfigurationAppIntent) -> WidgetMode {
        switch configuration.mode {
        case .mirrorApp:
            return WidgetMode(rawValue: SharedLocationStore.widgetMode) ?? .rain
        case .rain:
            return .rain
        case .uv:
            return .uv
        }
    }

    // MARK: - Data Fetch

    private func fetchEntry(configuration: ConfigurationAppIntent) async -> RegenEntry {
        Self.logger.info("🔄 [TimelineProvider] fetchEntry() starting")
        let start = Date()
        let mode  = resolveMode(configuration: configuration)

        do {
            // Step 1: Resolve location
            let coordinate: CLLocationCoordinate2D
            var locality: String? = nil

            if let manual = SharedLocationStore.manualCoordinate {
                coordinate = manual
                locality   = SharedLocationStore.manualLocationName
                Self.logger.info("🔄 [TimelineProvider] Using manual location: \(coordinate.latitude), \(coordinate.longitude)")
            } else {
                Self.logger.info("🔄 [TimelineProvider] Fetching GPS location")
                let lm = WidgetLocationManager()
                coordinate = try await lm.getCurrentLocation()

                let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc) {
                    locality = placemarks.first?.locality ?? placemarks.first?.name
                }
            }

            // Step 2: Fetch only the required data for the active mode
            var points: [PrecipitationPoint] = []
            var uvPoints: [UVPoint] = []

            if mode == .rain {
                points = try await PrecipitationProviderFactory
                    .provider(for: coordinate)
                    .fetchPrecipitation(lat: coordinate.latitude, lon: coordinate.longitude)
            } else {
                uvPoints = try await UVFetcher()
                    .fetchUVIndex(lat: coordinate.latitude, lon: coordinate.longitude)
            }

            let elapsed = Date().timeIntervalSince(start)
            Self.logger.info("🔄 [TimelineProvider] ✅ Mode: \(mode.rawValue). \(points.count) rain / \(uvPoints.count) UV in \(String(format: "%.2f", elapsed))s")

            return RegenEntry(
                date: Date(),
                precipitationPoints: points,
                uvPoints: uvPoints,
                widgetMode: mode,
                errorMessage: nil,
                debugInfo: "OK \(points.count)R \(uvPoints.count)UV (Mode: \(mode.rawValue))",
                locality: locality
            )

        } catch {
            let elapsed = Date().timeIntervalSince(start)
            Self.logger.error("🔄 [TimelineProvider] ❌ \(error.localizedDescription) after \(String(format: "%.2f", elapsed))s")
            return RegenEntry(
                date: Date(),
                precipitationPoints: [],
                uvPoints: [],
                widgetMode: mode,
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

    // MARK: Rain helpers

    private var displayPoints: [PrecipitationPoint] {
        Array(entry.precipitationPoints.prefix(18))
    }

    private var yAxisMax: Double {
        let maxVal = displayPoints.map(\.precipitationMM).max() ?? 0
        if maxVal <= 10.0 { return 10.0 }
        if maxVal <= 20.0 { return 20.0 }
        return ceil(maxVal / 10.0) * 10.0
    }

    private var hasRainInNext90Mins: Bool {
        displayPoints.contains(where: { $0.precipitationMM > 0 })
    }

    // MARK: UV helpers

    private var uvDisplayPoints: [UVPoint] {
        entry.uvPoints
    }

    /// Y-axis ceiling for UV: default 8, scales up if any value exceeds it.
    private var uvYAxisMax: Double {
        let maxVal = uvDisplayPoints.map(\.uvIndex).max() ?? 0
        return maxVal > 8.0 ? ceil(maxVal) : 8.0
    }

    private func uvBarColor(for uvIndex: Double) -> Color {
        switch uvIndex {
        case ..<0.1: return Color.gray.opacity(0.3)
        case ..<3:   return Color(red: 0.35, green: 0.75, blue: 0.25)  // Low – green
        case ..<6:   return Color(red: 0.97, green: 0.80, blue: 0.05)  // Moderate – yellow
        case ..<8:   return Color(red: 0.97, green: 0.49, blue: 0.09)  // High – orange
        default:     return Color(red: 0.85, green: 0.14, blue: 0.14)  // Very High – red
        }
    }

    // MARK: Shared helpers

    private func timeString(for index: Int, in points: [any _TimestampedPoint]) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        if index < points.count {
            return fmt.string(from: points[index].pointTimestamp)
        }
        return fmt.string(from: entry.date.addingTimeInterval(TimeInterval(index * 5 * 60)))
    }

    private var refreshTimeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: entry.date)
    }

    // MARK: - Body

    var body: some View {
        if let error = entry.errorMessage {
            errorView(error)
        } else {
            switch entry.widgetMode {
            case .rain:
                if displayPoints.isEmpty { errorView("Keine Daten") }
                else { radarChartView }
            case .uv:
                if uvDisplayPoints.isEmpty { errorView("Keine UV-Daten") }
                else { uvChartView }
            }
        }
    }

    // MARK: - Rain Chart

    private var radarChartView: some View {
        VStack(spacing: 2) {
            headerRow
            GeometryReader { geo in
                let chartH = max(0, geo.size.height - 24)
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        // Background grid + Y-axis label
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
                        .frame(height: chartH)

                        // Bars
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(Array(displayPoints.enumerated()), id: \.element.id) { _, point in
                                rainBarColumn(for: point, maxHeight: chartH - 24)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    xAxisLabels(using: displayPoints.map { $0 as any _TimestampedPoint })
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func rainBarColumn(for point: PrecipitationPoint, maxHeight: CGFloat) -> some View {
        let hasRain  = point.precipitationMM > 0
        let baseline = maxHeight * 0.1
        let height: CGFloat = hasRain
            ? baseline + CGFloat(point.precipitationMM / yAxisMax) * (maxHeight - baseline)
            : baseline

        return RoundedRectangle(cornerRadius: 2)
            .fill(hasRain ? Color.blue : Color.gray.opacity(0.3))
            .frame(height: height)
    }

    // MARK: - UV Chart

    private var uvChartView: some View {
        VStack(spacing: 2) {
            headerRow
            GeometryReader { geo in
                let chartH = max(0, geo.size.height - 24)
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        // Background grid + Y-axis label
                        VStack(spacing: 0) {
                            HStack(spacing: 4) {
                                Text("UV \(Int(uvYAxisMax))")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "sun.max.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(height: 0.5)
                            }
                            .padding(.top, 6)
                            Spacer()
                            Divider().background(Color.secondary.opacity(0.3))
                        }
                        .frame(height: chartH)

                        // Bars
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(Array(uvDisplayPoints.enumerated()), id: \.element.id) { _, point in
                                uvBarColumn(for: point, maxHeight: chartH - 24)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    xAxisLabels(using: uvDisplayPoints.map { $0 as any _TimestampedPoint })
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func uvBarColumn(for point: UVPoint, maxHeight: CGFloat) -> some View {
        let clamped  = min(point.uvIndex, uvYAxisMax)
        let baseline = maxHeight * 0.1
        let textHeight: CGFloat = 8
        let usableHeight = max(0, maxHeight - textHeight)
        
        let height: CGFloat = clamped < 0.1
            ? baseline
            : baseline + CGFloat(clamped / uvYAxisMax) * (usableHeight - baseline)

        return VStack(spacing: 1) {
            if point.uvIndex >= 0.5 {
                Text(String(format: "%.0f", point.uvIndex))
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                Text(" ")
                    .font(.system(size: 6.5))
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(uvBarColor(for: point.uvIndex))
                .frame(height: height)
        }
    }

    // MARK: - Shared Sub-views

    /// Top row with location name and last-refresh time.
    private var headerRow: some View {
        HStack {
            HStack(spacing: 3) {
                Image(systemName: "location.fill").font(.caption2)
                Text(entry.locality ?? "")
                    .font(.caption2).fontWeight(.semibold).lineLimit(1)
            }
            .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise").font(.caption2)
                Text(refreshTimeString).font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func xAxisLabels(using points: [any _TimestampedPoint]) -> some View {
        GeometryReader { geo in
            let count = max(1, points.count)
            let w  = geo.size.width
            let wb = (w - CGFloat(count - 1)) / CGFloat(count)

            ZStack(alignment: .topLeading) {
                // Tick marks
                let tickIndices = count > 1 ? [0, count / 3, 2 * count / 3, count - 1] : [0]
                ForEach(tickIndices, id: \.self) { col in
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 1.5, height: 5)
                        .offset(x: Double(col) * (wb + (col == 0 ? 0 : 1.0)) + 0.5 * wb - 0.75, y: 0)
                }

                // Labels
                ForEach(tickIndices, id: \.self) { col in
                    Text(timeStringFor(index: col, points: points))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .center)
                        .offset(
                            x: Double(col) * (wb + (col == 0 ? 0 : 1.0)) + 0.5 * wb - 20.0,
                            y: 7
                        )
                }
            }
        }
        .frame(height: 24)
    }

    private func timeStringFor(index: Int, points: [any _TimestampedPoint]) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        if index < points.count { return fmt.string(from: points[index].pointTimestamp) }
        return fmt.string(from: entry.date.addingTimeInterval(TimeInterval(index * 5 * 60)))
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.icloud")
                .font(.title2).foregroundStyle(.secondary)
            Text(message)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Internal Timestamp Protocol

/// Allows `xAxisLabels` to work with both `PrecipitationPoint` and `UVPoint`
/// without a full generic type parameter on the view.
protocol _TimestampedPoint {
    var pointTimestamp: Date { get }
}

extension PrecipitationPoint: _TimestampedPoint {
    var pointTimestamp: Date { timestamp }
}

extension UVPoint: _TimestampedPoint {
    var pointTimestamp: Date { timestamp }
}

// MARK: - Widget Configuration

struct RegenWidget: Widget {
    let kind: String = "RegenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: RegenTimelineProvider()
        ) { entry in
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
        .description("Niederschlag & UV-Index für die nächsten 90 Minuten.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

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
