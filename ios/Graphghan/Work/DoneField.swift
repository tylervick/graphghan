import SwiftUI
import GraphghanCore

/// One stop on the color track: a run near the cursor and where it sits. Offset 0 is the current
/// run (the wide column), -1 the one Back returns to (the leading column), +1 the next run (a
/// sliver peeking in from the trailing edge); the rest wait off screen so that advancing slides
/// colors along the track instead of swapping them.
struct TrackStop: Identifiable, Equatable {
    let cursor: Cursor
    let offset: Int
    /// The run's yarn color; nil past the last run (the finished stop), drawn as Cream.
    let hex: String?
    var id: Cursor { cursor }
}

/// What the current column shows: the run under the cursor and the on-deck line beneath it.
struct WorkFieldContent: Equatable {
    let count: Int
    let code: String
    let name: String
    let onDeck: String?
    /// The stitch abbreviation, when the chart states one; drawn as a small capsule by the count.
    var stitch: String? = nil
}

/// The lower half of the Work screen (spec §6.1): full-height color columns for the previous and
/// current runs under clear glass, the next run's color peeking in at the trailing edge. The
/// current column carries the count, code, name, the on-deck line, and Done; tapping it, or any
/// bare part of the field, advances. Back is the leading column. On Done the columns slide left
/// so the color just finished becomes the Back column and the sliver widens into the current one.
struct WorkField: View {
    let finished: Bool
    let canGoBack: Bool
    let content: WorkFieldContent?
    let doneLabel: String
    let doneForeground: Color
    let backForeground: Color
    let stops: [TrackStop]
    let onDone: () -> Void
    let onBack: () -> Void

    static let inset: CGFloat = 12
    static let backWidth: CGFloat = 72
    static let gap: CGFloat = 12
    /// How much of the next run's color shows at the trailing edge.
    static let sliver: CGFloat = 28
    static let radius: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let zones = Zones(width: geo.size.width, height: geo.size.height, showsBack: !finished)
            ZStack(alignment: .topLeading) {
                Button(action: onDone) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                ColorTrack(stops: stops, zones: zones)
                glass(zones: zones)
            }
        }
    }

    @ViewBuilder private func glass(zones: Zones) -> some View {
        let panels = ZStack(alignment: .topLeading) {
            if !finished {
                Button(action: onBack) {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 28, weight: .semibold))
                        Text("Back").font(Font.Heather.label).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .frame(width: zones.back.width, height: zones.back.height)
                    .foregroundStyle(backForeground.opacity(canGoBack ? 1 : 0.4))
                    .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                    .clearGlass()
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .offset(x: zones.back.minX)
                .accessibilityLabel("Back one run")
            }
            Button(action: onDone) {
                VStack(spacing: 6) {
                    if let content {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(content.count)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            if let stitch = content.stitch {
                                Text(stitch)
                                    .font(Font.Heather.label)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .overlay(Capsule().strokeBorder(doneForeground.opacity(0.6), lineWidth: 1.5))
                            }
                        }
                        Text(content.code).font(Font.Heather.code).lineLimit(1)
                        Text(content.name).font(Font.Heather.heading).lineLimit(1).minimumScaleFactor(0.7)
                        if let onDeck = content.onDeck {
                            Text(onDeck).font(Font.Heather.label).opacity(0.75).lineLimit(2).multilineTextAlignment(.center)
                        }
                    } else {
                        Text("Finished").font(Font.Heather.title)
                        Text("Every row is done. Block it, weave in the ends, and take a picture.")
                            .font(Font.Heather.body).multilineTextAlignment(.center)
                    }
                    Text(finished ? "Close" : "Done")
                        .font(Font.Heather.done).lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.top, 14)
                }
                .padding(16)
                .frame(width: zones.current.width, height: zones.current.height)
                .foregroundStyle(doneForeground)
                .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                .clearGlass()
            }
            .buttonStyle(.plain)
            .offset(x: zones.current.minX)
            .accessibilityLabel(doneLabel)
            .accessibilityValue(content?.onDeck ?? "")
        }
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: Self.gap) { panels }
        } else {
            panels
        }
    }
}

/// Where each track offset sits, for a field of a given width.
private struct Zones {
    let back: CGRect
    let current: CGRect
    let next: CGRect
    let offLeading: CGRect
    let offTrailing: CGRect

    init(width: CGFloat, height h: CGFloat, showsBack: Bool) {
        let inset = WorkField.inset, gap = WorkField.gap, backW = WorkField.backWidth, sliver = WorkField.sliver
        let currentX = showsBack ? inset + backW + gap : inset
        let currentW = width - currentX - gap - sliver
        back = CGRect(x: inset, y: 0, width: backW, height: h)
        current = CGRect(x: currentX, y: 0, width: currentW, height: h)
        next = CGRect(x: width - sliver, y: 0, width: backW, height: h)
        offLeading = CGRect(x: -backW - 40, y: 0, width: backW, height: h)
        offTrailing = CGRect(x: width + 60, y: 0, width: backW, height: h)
    }

    func rect(for offset: Int, showsBack: Bool) -> (CGRect, Double) {
        switch offset {
        case 0: return (current, 1)
        case -1: return showsBack ? (back, 1) : (offLeading, 0)
        case 1: return (next, 1)
        case ..<(-1): return (offLeading, 0)
        default: return (offTrailing, 0)
        }
    }
}

/// The yarn colors under the glass, one block per nearby run, blurred a touch so they read as
/// color pooled under the material rather than a second set of buttons.
private struct ColorTrack: View {
    let stops: [TrackStop]
    let zones: Zones

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(stops) { stop in
                let (rect, opacity) = zones.rect(for: stop.offset, showsBack: stops.contains { $0.offset == -1 })
                RoundedRectangle(cornerRadius: WorkField.radius, style: .continuous)
                    .fill(stop.hex.map(YarnSurface.fill) ?? Color.cream)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX)
                    .opacity(opacity)
                    .blur(radius: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Clear Liquid Glass on iOS 26 so the track shows through; a thin material panel before that.
    @ViewBuilder func clearGlass() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: WorkField.radius, style: .continuous))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: WorkField.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: WorkField.radius, style: .continuous).strokeBorder(YarnSurface.hairline, lineWidth: 1))
        }
    }
}
