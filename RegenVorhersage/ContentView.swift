//
//  ContentView.swift
//  RegenVorhersage
//
//  Created by Sascha Libricht on 07.07.26.
//

import SwiftUI
import CoreLocation
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

// MARK: - Content View

struct ContentView: View {
    @StateObject private var locationManager = AppLocationManager()
    
    @State private var precipitationPoints: [PrecipitationPoint] = []
    @State private var fetchError: String? = nil
    @State private var isFetching: Bool = false
    @State private var lastFetchTime: Date? = nil
    
    var body: some View {
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
            
            // Location permission status
            VStack(spacing: 12) {
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
                } else if locationManager.authorizationStatus == .denied {
                    Text("Bitte aktiviere die Standortberechtigung in den Einstellungen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                if locationManager.currentLocation != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        Text(locationManager.locality ?? "")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            .padding(.horizontal, 20)
            
            // Diagnostics & Data Section
            VStack {
                HStack {
                    Text("Diagnosedaten")
                        .font(.headline)
                    Spacer()
                    Button {
                        fetchData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(locationManager.currentLocation == nil || isFetching)
                }
                .padding(.bottom, 4)
                
                if let error = fetchError {
                    Text("Fehler: \(error)")
                        .foregroundColor(.red)
                        .font(.caption)
                } else if isFetching {
                    ProgressView("Lade Radardaten...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if !precipitationPoints.isEmpty {
                    Text("Letztes Update: \(lastFetchTime?.formatted(date: .omitted, time: .standard) ?? "-")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ScrollView {
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
                    }
                    .frame(maxHeight: 180)
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
            
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .onChange(of: locationManager.currentLocation) { oldValue, newValue in
            if precipitationPoints.isEmpty {
                fetchData()
            }
        }
    }
    
    private func fetchData() {
        guard let location = locationManager.currentLocation else { return }
        isFetching = true
        fetchError = nil
        
        Task {
            do {
                let points = try await RadarFetcher.fetchPrecipitation(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
                await MainActor.run {
                    self.precipitationPoints = points
                    self.lastFetchTime = Date()
                    self.isFetching = false
                }
            } catch {
                await MainActor.run {
                    self.fetchError = error.localizedDescription
                    self.isFetching = false
                }
            }
        }
    }
    
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
