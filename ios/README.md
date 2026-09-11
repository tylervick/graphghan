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
  - `Storage/` — App Group paths, the two SwiftData models (`Project`, `ProgressEvent`) and
    `ChartLibrary`, the downloaded chart files
  - `Network/` — HTTP client and response handling
  - `Services/` — `ProjectService`, through which every project mutation goes
  - `Patterns/` — Patterns tab with pattern browser and chart detail
  - `Projects/` — Projects tab with project list and detail
  - `Work/` — full-screen Work screen
  - `UI/` — shared components and colors
- `Packages/GraphghanCore/` — Swift reader for the chart format (JSON decoder, engine)
- `Tests/` — app unit tests (Swift Testing, in-memory SwiftData, stub HTTP client)

## Data

Everything lives in the App Group container (`group.com.tylervick.graphghan`):

- SwiftData store at `Library/Application Support/graphghan.store`, chart files at
  `Library/Application Support/charts/<chart id>.json` (never evicted while a project uses one)
- Pattern cache under `Library/Caches/patterns/<id>/`: the library index, manifests, previews and
  their ETags

## Live Activity

The Work screen runs a Live Activity on the lock screen and in the Dynamic Island, backed by the
`GraphghanWidgets` extension target. `Shared/` compiles into both the app and the extension, but
the Done and Back intents run in the app: the extension has nothing registered, so
`WorkIntentHandler` (set up in `AppModel.live`) is what actually calls `ProjectService.apply`. A
lock-screen tap that launches the app from the background still applies through
`ProjectService.apply`. The controller keeps one activity live at a time, restarts it after the
system's 8-hour limit on the next advance, and reconciles every active activity on launch, with
the stored cursor winning. `project.yml` sets `NSSupportsLiveActivities` in the app's Info.plist.
Snapshots of the lock screen and Dynamic Island layouts live under `Tests/__Snapshots__`; delete a
PNG to re-record it. Those references are tied to the iPhone 17 simulator, so re-record on that
device if they drift after an OS update.
