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
