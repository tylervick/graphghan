import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() { light.prepare(); medium.prepare(); rigid.prepare() }

    static func play(_ feedback: WorkFeedback) {
        switch feedback {
        case .run: light.impactOccurred()
        case .row: medium.impactOccurred()
        case .newColor:
            rigid.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { rigid.impactOccurred() }
        case .finished: notify.notificationOccurred(.success)
        }
    }
}
