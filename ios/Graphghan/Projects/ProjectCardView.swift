import SwiftUI

/// The project row as a card (spec §6.2). Stateless so it can be snapshotted; `ProjectRow` feeds it.
struct ProjectCardView: View {
    let title: String
    let percent: Double?
    let line: String
    let estimate: String?
    let lastWorked: String?
    let finished: Bool
    let preview: UIImage?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                PreviewFrame(image: preview)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(Font.Heather.heading).foregroundStyle(Color.ink).lineLimit(2)
                    if !finished, let percent {
                        ProgressView(value: percent, total: 100).tint(.heather)
                    }
                    Text(line).font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
                    if let estimate { Text(estimate).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                    if let lastWorked { Text(lastWorked).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Font.Heather.label).foregroundStyle(Color.ink2).padding(.top, 4)
            }
        }
    }
}

/// 96 × 80 preview with the yarn hairline; a Panel placeholder until the image arrives.
struct PreviewFrame: View {
    let image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFill()
            } else {
                Color.panel.overlay(Image(systemName: "photo").foregroundStyle(Color.ink2))
            }
        }
        .frame(width: 96, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(YarnSurface.hairline, lineWidth: 1))
    }
}
