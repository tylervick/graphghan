import UIKit

/// What the iPhone's power situation is, for the diagnostics and for one sentence on the import
/// sheet (#176).
///
/// Why the app cares: Apple's own framework documentation is quiet on it, but the consistent
/// report from developers is that the on-device model is rate limited on battery and not when
/// the device is charging, and Low Power Mode throttles background work generally. Every run of
/// the row check that has been refused so far was, as far as we know, on battery. That is not
/// established, so nothing here claims it is -- the state is recorded in the probe's report so a
/// run settles it, and the sheet says only that plugging in may help.
@MainActor
enum PowerState {
    /// Battery reporting is off by default and `batteryState` reads `.unknown` until it is on.
    private static func enableMonitoring() {
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }

    /// True only when we positively know the iPhone is running on its battery. An unknown state
    /// is never reported as battery: a wrong "plug it in" is worse than no advice.
    static var isOnBattery: Bool {
        enableMonitoring()
        return UIDevice.current.batteryState == .unplugged
    }

    static var isLowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// The line the probe's report carries, so a device run records what nobody thought to note.
    static var summary: String {
        enableMonitoring()
        let power: String
        switch UIDevice.current.batteryState {
        case .charging: power = "charging"
        case .full: power = "on mains, full"
        case .unplugged: power = "on battery"
        default: power = "power state unknown"
        }
        let level = UIDevice.current.batteryLevel
        let percent = level < 0 ? "" : ", \(Int(level * 100))%"
        return "the iPhone was \(power)\(percent)\(isLowPower ? ", in Low Power Mode" : "")"
    }
}
