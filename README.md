# RegenVorhersage

An iOS home screen widget that shows a short-term weather forecast for your current (or a manually chosen) location as a compact bar chart.

## Modes

| Mode | Data | Resolution | Source |
| --- | --- | --- | --- |
| **Regen** (rain) | Precipitation in mm | 5-minute steps, next 90 minutes | BrightSky (DWD radar) inside Germany, Tomorrow.io elsewhere |
| **UV-Index** | UV index | Hourly, today's daylight hours | Tomorrow.io |
| **Temperatur** | Temperature in °C | Hourly, current hour + 12 hours | Tomorrow.io |

The mode can be set in the app (applies to all widgets) or per widget via long-press → *Edit Widget*.

## Features

- Small and medium widget sizes
- Automatic GPS location or manual location search
- Rain mode refreshes every 5, 10 or 15 minutes (configurable); UV and temperature refresh hourly
- Color-coded bars and a highlighted current hour for UV and temperature
- Diagnostics view in the app showing the raw fetched data points

## Requirements

- Xcode with the iOS 18 SDK or later
- iOS 18.0+
- A free [Tomorrow.io](https://www.tomorrow.io) API key

## Setup

1. Clone the repository and open `RegenVorhersage.xcodeproj`.
2. Create `RegenWidget/Secrets.swift` (git-ignored) based on `RegenWidget/Secrets.template.swift`:

   ```swift
   enum Secrets {
       static let tomorrowIOApiKey = "YOUR_API_KEY_HERE"
   }
   ```

3. Set your development team for both the `RegenVorhersage` and `RegenWidgetExtension` targets. App and widget share settings through the App Group `group.sascha.RegenVorhersage`; adjust it if you use a different bundle identifier.
4. Build and run the `RegenVorhersage` scheme, grant location access, then add the widget to your home screen.

## Project Structure

| Path | Purpose |
| --- | --- |
| `RegenVorhersage/ContentView.swift` | App UI: location, update interval, widget mode, diagnostics |
| `RegenWidget/RegenWidget.swift` | Timeline provider and widget chart views |
| `RegenWidget/WidgetConfigIntent.swift` | Per-widget mode configuration (App Intents) |
| `RegenWidget/PrecipitationProvider.swift` | Chooses BrightSky or Tomorrow.io based on location |
| `RegenWidget/BrightSkyProvider.swift`, `TomorrowIOProvider.swift` | Precipitation data sources |
| `RegenWidget/UVFetcher.swift`, `TemperatureFetcher.swift` | Hourly UV and temperature data from Tomorrow.io |
| `RegenWidget/SharedLocationStore.swift` | Settings shared between app and widget via App Group |

## Data Sources

- [Bright Sky](https://brightsky.dev) – free JSON API for data from Deutscher Wetterdienst (DWD)
- [Tomorrow.io](https://www.tomorrow.io) – Timeline API for precipitation, UV index and temperature
