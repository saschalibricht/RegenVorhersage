//
//  WidgetConfigIntent.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 13.07.26.
//

import AppIntents
import WidgetKit

// MARK: - Widget Mode (AppEnum conformance — widget target only)

extension WidgetMode: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget-Modus")
    static var caseDisplayRepresentations: [WidgetMode: DisplayRepresentation] = [
        .rain: DisplayRepresentation(
            title: "Regen",
            image: .init(systemName: "cloud.rain.fill")
        ),
        .uv: DisplayRepresentation(
            title: "UV-Index",
            image: .init(systemName: "sun.max.fill")
        ),
    ]
}

// MARK: - Configuration Intent

/// Widget configuration intent that enables the long-press mode picker.
/// Conforms to `WidgetConfigurationIntent` so WidgetKit presents it
/// in the system "Edit Widget" sheet when the user long-presses the widget.
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget-Modus"
    static var description = IntentDescription("Wähle zwischen Regen- und UV-Index-Anzeige.")

    @Parameter(title: "Modus", default: .rain)
    var mode: WidgetMode
}
