# Graphghan for iOS

SwiftUI app for working graphghan patterns published at https://graphghan.milo.cat/. The
`Packages/GraphghanCore` package reads the chart format (`../docs/chart-format.md`) and is tested
against `../fixtures/chart-format`.

    cd ios
    mise install            # xcodegen
    mise run generate       # Graphghan.xcodeproj (gitignored)
    mise run core-test      # swift test, macOS host
    mise run test           # app unit tests on the iPhone 17 simulator
    open Graphghan.xcodeproj

Bundle id `com.tylervick.graphghan`, App Group `group.com.tylervick.graphghan`, iOS 17.0+.

## Layout

- `Graphghan/` — the app
  - `Storage/` — model queries and operations (projects, patterns, sessions)
  - `Network/` — HTTP client and response handling
  - `Services/` — higher-level logic (projects, patterns, work)
  - `Patterns/` — Patterns tab with pattern browser and chart detail
  - `Projects/` — Projects tab with project list and detail
  - `Work/` — full-screen Work screen
  - `UI/` — shared components and colors
- `Packages/GraphghanCore/` — Swift reader for the chart format (JSON decoder, engine)
- `Tests/` — app unit tests (Swift Testing, in-memory SwiftData, stub HTTP client)

## Data

- SwiftData store and chart files under the App Group container (`group.com.tylervick.graphghan`)
- Pattern cache under `Library/Caches/patterns/<id>/` (ETags and downloaded charts)
