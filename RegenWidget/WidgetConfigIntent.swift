//
//  WidgetConfigIntent.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 13.07.26.
//

import AppIntents
import WidgetKit

// MARK: - Widget Intent Mode

enum WidgetIntentMode: String, AppEnum {
    case mirrorApp = "mirrorApp"
    case rain = "rain"
    case uv = "uv"
    case temperature = "temperature"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget-Modus")
    static var caseDisplayRepresentations: [WidgetIntentMode: DisplayRepresentation] = [
        .mirrorApp: DisplayRepresentation(
            title: "App-Einstellung",
            image: .init(systemName: "iphone")
        ),
        .rain: DisplayRepresentation(
            title: "Immer Regen",
            image: .init(systemName: "cloud.rain.fill")
        ),
        .uv: DisplayRepresentation(
            title: "Immer UV-Index",
            image: .init(systemName: "sun.max.fill")
        ),
        .temperature: DisplayRepresentation(
            title: "Immer Temperatur",
            image: .init(systemName: "thermometer.medium")
        ),
    ]
}

// MARK: - Configuration Intent

/// Widget configuration intent that enables the long-press mode picker.
/// Conforms to `WidgetConfigurationIntent` so WidgetKit presents it
/// in the system "Edit Widget" sheet when the user long-presses the widget.
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget-Modus"
    static var description = IntentDescription("Wähle zwischen Regen-, UV-Index- und Temperatur-Anzeige.")

    @Parameter(title: "Modus", default: .mirrorApp)
    var mode: WidgetIntentMode
}
