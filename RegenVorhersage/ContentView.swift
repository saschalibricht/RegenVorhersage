//
//  ContentView.swift
//  RegenVorhersage
//
//  Created by Sascha Libricht on 07.07.26.
//

import SwiftUI
import CoreLocation
import MapKit
import WidgetKit
import os

// MARK: - App Location Manager

/// Location manager for the main app to trigger the permission dialog.
/// The widget inherits location access from the host app's permission.
class AppLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage", category: "AppLocationManager")
    
    private let locationManager = CLLocationManager()
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var locationError: String?
    @Published var locality: String?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
        Self.logger.info("📍 [AppLocationManager] Initialized, status: \(self.authorizationStatus.rawValue)")
    }
    
    func requestPermission() {
        Self.logger.info("📍 [AppLocationManager] Requesting when-in-use authorization")
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        Self.logger.info("📍 [AppLocationManager] Requesting one-shot location")
        locationManager.requestLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        Self.logger.info("📍 [AppLocationManager] Authorization changed to: \(manager.authorizationStatus.rawValue)")
        
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            locationManager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.first
        if let loc = locations.first {
            Self.logger.info("📍 [AppLocationManager] Location: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
            // Perform reverse geocoding to update locality
            Task {
                let geocoder = CLGeocoder()
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(loc)
                    let name = placemarks.first?.locality ?? placemarks.first?.name
                    await MainActor.run {
                        self.locality = name
                    }
                } catch {
                    Self.logger.error("❌ [AppLocationManager] Reverse geocoding failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error.localizedDescription
        Self.logger.error("❌ [AppLocationManager] Error: \(error.localizedDescription)")
    }
}

// MARK: - Location Search View Model

/// Wraps MKLocalSearchCompleter to provide location autocomplete suggestions.
class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isResolving = false
    
    private let completer: MKLocalSearchCompleter
    
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    
    /// Updates the search completer with new query text.
    func search(_ text: String) {
        if text.isEmpty {
            completions = []
        } else {
            completer.queryFragment = text
        }
    }
    
    /// Resolves a search completion to a coordinate and locality name.
    @MainActor
    func resolveCompletion(_ completion: MKLocalSearchCompletion) async -> (CLLocationCoordinate2D, String)? {
        isResolving = true
        defer { isResolving = false }
        
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            let name = item.placemark.locality ?? item.placemark.name ?? completion.title
            return (item.placemark.coordinate, name)
        } catch {
            return nil
        }
    }
    
    // MARK: - MKLocalSearchCompleterDelegate
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Silently ignore completer errors
    }
}

// MARK: - Location Search View

/// Sheet view for searching and selecting a location by name.
struct LocationSearchView: View {
    @StateObject private var viewModel = LocationSearchViewModel()
    @Environment(\.dismiss) private var dismiss
    
    /// Callback when the user selects a location.
    let onLocationSelected: (CLLocationCoordinate2D, String) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                if viewModel.isResolving {
                    HStack {
                        Spacer()
                        ProgressView("Lade Koordinaten…")
                        Spacer()
                    }
                }
                
                ForEach(Array(viewModel.completions.enumerated()), id: \.offset) { _, completion in
                    Button {
                        Task {
                            if let (coordinate, name) = await viewModel.resolveCompletion(completion) {
                                onLocationSelected(coordinate, name)
                                dismiss()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(viewModel.isResolving)
                }
            }
            .searchable(text: $viewModel.query, prompt: "Stadt oder Ort eingeben")
            .onChange(of: viewModel.query) { _, newValue in
                viewModel.search(newValue)
            }
            .navigationTitle("Standort suchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var locationManager = AppLocationManager()
    
    @State private var precipitationPoints: [PrecipitationPoint] = []
    @State private var uvPoints: [UVPoint] = []
    @State private var lastPrecipFetchTime: Date? = nil
    @State private var lastUVFetchTime: Date? = nil
    @State private var fetchError: String? = nil
    @State private var isFetching: Bool = false
    @State private var lastFetchTime: Date? = nil
    
    private static let logger = Logger(subsystem: "sascha.RegenVorhersage", category: "ContentView")
    
    // Manual location state
    @State private var isManualLocation = false
    @State private var manualLatitude: Double? = nil
    @State private var manualLongitude: Double? = nil
    @State private var manualLocationName: String? = nil
    @State private var showingLocationSearch = false
    
    @AppStorage(SharedLocationStore.updateIntervalKey, store: UserDefaults(suiteName: SharedLocationStore.appGroupID))
    private var updateIntervalMinutes: Int = 15

    @AppStorage(SharedLocationStore.widgetModeKey, store: UserDefaults(suiteName: SharedLocationStore.appGroupID))
    private var widgetModeStr: String = WidgetMode.rain.rawValue

    private var widgetMode: WidgetMode { WidgetMode(rawValue: widgetModeStr) ?? .rain }
    
    /// The coordinate currently used for data fetching (manual or GPS).
    private var activeCoordinate: CLLocationCoordinate2D? {
        if isManualLocation, let lat = manualLatitude, let lon = manualLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return locationManager.currentLocation?.coordinate
    }
    
    /// Display name for the active location.
    private var activeLocationName: String? {
        if isManualLocation {
            return manualLocationName
        }
        return locationManager.locality
    }
    
    /// Name of the API provider for the current coordinate.
    private var activeProviderName: String {
        guard let coord = activeCoordinate else { return "–" }
        return PrecipitationProviderFactory.isInGermany(coord) ? "BrightSky (DWD)" : "Tomorrow.io"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App icon
                Image(systemName: "cloud.rain.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("RegenVorhersage")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Niederschlagsradar-Widget")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Divider()
                    .padding(.horizontal, 40)
                
                // MARK: Location & API Section
                VStack(spacing: 12) {
                    // GPS permission status
                    HStack {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                        Text(statusText)
                            .font(.callout)
                    }
                    
                    if locationManager.authorizationStatus == .notDetermined {
                        Button("Standort freigeben") {
                            locationManager.requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if locationManager.authorizationStatus == .denied && !isManualLocation {
                        Text("Bitte aktiviere die Standortberechtigung in den Einstellungen oder wähle einen Standort manuell.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    
                    // Active location & API info
                    if activeCoordinate != nil {
                        Divider()
                        
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: isManualLocation ? "mappin.circle.fill" : "location.fill")
                                Text(activeLocationName ?? "Standort wird ermittelt…")
                                    .fontWeight(.medium)
                                if isManualLocation {
                                    Text("(manuell)")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                            }
                            .font(.callout)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.caption)
                                Text("API: \(activeProviderName)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Location mode buttons
                    Divider()
                    
                    if isManualLocation {
                        HStack(spacing: 12) {
                            Button {
                                showingLocationSearch = true
                            } label: {
                                Label("Ort ändern", systemImage: "magnifyingglass")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                switchToAutomatic()
                            } label: {
                                Label("Zurück zu GPS", systemImage: "location.fill")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        }
                    } else {
                        Button {
                            showingLocationSearch = true
                        } label: {
                            Label("Standort manuell wählen", systemImage: "magnifyingglass")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider()

                    HStack {
                        Text("Aktualisierungsintervall")
                            .font(.callout)
                        Spacer()
                        Picker("Intervall", selection: $updateIntervalMinutes) {
                            Text("5 Min").tag(5)
                            Text("10 Min").tag(10)
                            Text("15 Min").tag(15)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: updateIntervalMinutes) { _, _ in
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }

                    Divider()

                    HStack {
                        Text("Widget-Modus")
                            .font(.callout)
                        Spacer()
                        Picker("Modus", selection: $widgetModeStr) {
                            Label("Regen", systemImage: "cloud.rain.fill").tag(WidgetMode.rain.rawValue)
                            Label("UV-Index", systemImage: "sun.max.fill").tag(WidgetMode.uv.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .onChange(of: widgetModeStr) { _, newValue in
                            SharedLocationStore.widgetMode = newValue
                            WidgetCenter.shared.reloadAllTimelines()
                            fetchData()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                .padding(.horizontal, 20)
                
                // MARK: Diagnostics & Data Section
                VStack {
                    HStack {
                        Text("Diagnosedaten")
                            .font(.headline)
                        Spacer()
                        Button {
                            fetchData(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(activeCoordinate == nil || isFetching)
                    }
                    .padding(.bottom, 4)
                    
                    if let error = fetchError {
                        Text("Fehler: \(error)")
                            .foregroundColor(.red)
                            .font(.caption)
                    } else if isFetching {
                        ProgressView("Lade Daten...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else if widgetMode == .uv && !uvPoints.isEmpty {
                        Text("Letztes Update: \(lastFetchTime?.formatted(date: .omitted, time: .standard) ?? "-")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 4) {
                            ForEach(uvPoints.prefix(18)) { point in
                                HStack {
                                    Text(point.timestamp.formatted(date: .omitted, time: .shortened))
                                        .frame(width: 50, alignment: .leading)
                                    Text("+\(point.minutesFromNow)m")
                                        .frame(width: 50, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("UV \(String(format: "%.1f", point.uvIndex))")
                                        .frame(width: 70, alignment: .trailing)
                                        .foregroundStyle(uvDiagColor(for: point.uvIndex))
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                        .padding(.top, 4)
                    } else if widgetMode == .rain && !precipitationPoints.isEmpty {
                        Text("Letztes Update: \(lastFetchTime?.formatted(date: .omitted, time: .standard) ?? "-")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 4) {
                            ForEach(precipitationPoints.prefix(18)) { point in
                                HStack {
                                    Text(point.timestamp.formatted(date: .omitted, time: .shortened))
                                        .frame(width: 50, alignment: .leading)
                                    Text("+\(point.minutesFromNow)m")
                                        .frame(width: 50, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(String(format: "%.2f", point.precipitationMM)) mm")
                                        .frame(width: 70, alignment: .trailing)
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        Text("Keine Daten geladen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                .padding(.horizontal, 20)
            }
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .onChange(of: locationManager.currentLocation) { oldValue, newValue in
            if !isManualLocation {
                if widgetMode == .rain && precipitationPoints.isEmpty {
                    fetchData()
                } else if widgetMode == .uv && uvPoints.isEmpty {
                    fetchData()
                }
            }
        }
        .sheet(isPresented: $showingLocationSearch) {
            LocationSearchView { coordinate, name in
                setManualLocation(coordinate: coordinate, name: name)
            }
        }
    }
    
    // MARK: - Actions
    
    /// Sets a manually selected location, persists it to the shared store,
    /// triggers a data fetch, and reloads the widget timeline.
    private func setManualLocation(coordinate: CLLocationCoordinate2D, name: String) {
        isManualLocation = true
        manualLatitude = coordinate.latitude
        manualLongitude = coordinate.longitude
        manualLocationName = name
        precipitationPoints = []
        uvPoints = []
        lastPrecipFetchTime = nil
        lastUVFetchTime = nil
        fetchError = nil
        
        // Persist to shared store so the widget picks up the manual location
        SharedLocationStore.setManualLocation(coordinate: coordinate, name: name)
        WidgetCenter.shared.reloadAllTimelines()
        
        fetchData()
    }
    
    /// Switches back to automatic (GPS) location, clears the shared store,
    /// triggers a data fetch, and reloads the widget timeline.
    private func switchToAutomatic() {
        isManualLocation = false
        manualLatitude = nil
        manualLongitude = nil
        manualLocationName = nil
        precipitationPoints = []
        uvPoints = []
        lastPrecipFetchTime = nil
        lastUVFetchTime = nil
        fetchError = nil
        
        // Clear the shared store so the widget reverts to GPS
        SharedLocationStore.clearManualLocation()
        WidgetCenter.shared.reloadAllTimelines()
        
        fetchData()
    }
    
    private func shouldFetch(for mode: WidgetMode) -> Bool {
        let now = Date()
        let intervalSeconds = Double(updateIntervalMinutes * 60)
        switch mode {
        case .rain:
            guard let lastTime = lastPrecipFetchTime else { return true }
            return now.timeIntervalSince(lastTime) > intervalSeconds || precipitationPoints.isEmpty
        case .uv:
            guard let lastTime = lastUVFetchTime else { return true }
            return now.timeIntervalSince(lastTime) > intervalSeconds || uvPoints.isEmpty
        }
    }

    private func fetchData(force: Bool = false) {
        guard let coordinate = activeCoordinate else { return }
        
        let mode = widgetMode
        if !force && !shouldFetch(for: mode) {
            Self.logger.info("ℹ️ [ContentView] Using cached data for \(mode.rawValue), fetched recently.")
            return
        }
        
        isFetching = true
        fetchError = nil
        
        Task {
            do {
                if mode == .rain {
                    let provider = PrecipitationProviderFactory.provider(for: coordinate)
                    let points = try await provider.fetchPrecipitation(
                        lat: coordinate.latitude,
                        lon: coordinate.longitude
                    )
                    await MainActor.run {
                        self.precipitationPoints = points
                        self.lastPrecipFetchTime = Date()
                        self.lastFetchTime = Date()
                        self.isFetching = false
                    }
                } else {
                    let points = try await UVFetcher().fetchUVIndex(
                        lat: coordinate.latitude,
                        lon: coordinate.longitude
                    )
                    await MainActor.run {
                        self.uvPoints = points
                        self.lastUVFetchTime = Date()
                        self.lastFetchTime = Date()
                        self.isFetching = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.fetchError = error.localizedDescription
                    self.isFetching = false
                }
            }
        }
    }
    
    // MARK: - UV Diagnostics Color Helper

    private func uvDiagColor(for uvIndex: Double) -> Color {
        switch uvIndex {
        case ..<3:  return .green
        case ..<6:  return .yellow
        case ..<8:  return .orange
        default:    return .red
        }
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        default:
            return "questionmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        default:
            return .orange
        }
    }
    
    private var statusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse:
            return "Standort: Erlaubt (bei Nutzung)"
        case .authorizedAlways:
            return "Standort: Immer erlaubt"
        case .denied:
            return "Standort: Verweigert"
        case .restricted:
            return "Standort: Eingeschränkt"
        default:
            return "Standort: Nicht festgelegt"
        }
    }
}

#Preview {
    ContentView()
}
