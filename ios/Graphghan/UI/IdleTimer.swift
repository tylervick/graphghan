import UIKit

/// The screen kept awake while something long runs. Counted rather than set, so two holds that
/// overlap -- the Work screen and a PDF import reading its rows (#176) -- cannot turn each
/// other's off; the screen sleeps again when the last one is let go.
@MainActor
enum IdleTimer {
    private static var holds = 0

    static func hold() {
        holds += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        holds = max(0, holds - 1)
        if holds == 0 { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// For the tests: how many holds are outstanding.
    static var count: Int { holds }
}
