import SwiftUI

/// A Panel card with a 4pt leading rule: Heather for information, Brick for a failure (spec §6.6).
struct Banner: View {
    enum Kind { case info, failure }
    struct Action {
        let label: String
        let run: () -> Void
        init(label: String, run: @escaping () -> Void) { self.label = label; self.run = run }
    }
    let text: String
    var kind: Kind = .info
    var action: Action?

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(kind == .info ? Color.heather : Color.brick).frame(width: 4)
            HStack(spacing: 10) {
                Text(text).font(Font.Heather.caption).foregroundStyle(Color.ink)
                Spacer(minLength: 0)
                if let action {
                    Button(action.label, action: action.run).font(Font.Heather.label).tint(.moss)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
