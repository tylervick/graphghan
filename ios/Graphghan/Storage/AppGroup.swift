import Foundation

/// Where everything lives: the App Group container, so a widget extension and intents (later plans)
/// see the same store and chart files. Falls back to the app's own Application Support when the
/// group container is unavailable (e.g. a simulator build without the entitlement).
enum AppGroup {
    static let identifier = "group.com.tylervick.graphghan"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) { return url }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("graphghan-group", isDirectory: true)
    }

    static var supportURL: URL { containerURL.appendingPathComponent("Library/Application Support", isDirectory: true) }
    static var cachesURL: URL { containerURL.appendingPathComponent("Library/Caches", isDirectory: true) }
    static var storeURL: URL { supportURL.appendingPathComponent("graphghan.store") }
    static var chartsURL: URL { supportURL.appendingPathComponent("charts", isDirectory: true) }
    static var patternsCacheURL: URL { cachesURL.appendingPathComponent("patterns", isDirectory: true) }
    /// Patterns opened from a file (#16). Application Support, not the purgeable cache: a site
    /// pattern's cache is a copy of something the network can produce again, while this is the
    /// only copy there is, with a project possibly pointing at it.
    static var localPatternsURL: URL { supportURL.appendingPathComponent("local-patterns", isDirectory: true) }
}
