import SwiftUI
import GraphghanCore

/// One stop on the color track under the controls: a run near the cursor and where it sits.
/// Offset 0 is the current run (under Done), -1 the one Back returns to (under Back); the rest wait
/// off screen so that advancing slides colors along the track instead of swapping them.
struct TrackStop: Identifiable, Equatable {
    let cursor: Cursor
    let offset: Int
    /// The run's yarn color; nil past the last run (the finished stop), drawn as Cream.
    let hex: String?
    var id: Cursor { cursor }
}

/// The controls at the bottom of the Work screen (spec §6.1): two clear glass capsules, Back at the
/// leading edge and Done filling the rest, over a track of yarn colors. The previous run's color
/// pools under Back and the current one under Done; on advance the track slides left so the color
/// you just finished moves under Back and the next one arrives under Done. The field above is the
/// big Done target; these are its visible handles.
struct DoneField: View {
    let finished: Bool
    let canGoBack: Bool
    let doneLabel: String
    let doneForeground: Color
    let backForeground: Color
    let stops: [TrackStop]
    let onDone: () -> Void
    let onBack: () -> Void

    static let height: CGFloat = 88
    static let backWidth: CGFloat = 92
    static let gap: CGFloat = 12

    var body: some View {
        ZStack(alignment: .leading) {
            ColorTrack(stops: stops, showsBack: !finished)
            controls
        }
        .frame(height: Self.height)
    }

    @ViewBuilder private var controls: some View {
        let row = HStack(spacing: Self.gap) {
            if !finished {
                Button(action: onBack) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 26, weight: .semibold))
                        Text("Back").font(Font.Heather.label).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .frame(width: Self.backWidth, height: Self.height)
                    .foregroundStyle(backForeground.opacity(canGoBack ? 1 : 0.4))
                    .contentShape(Capsule())
                    .clearGlass()
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .accessibilityLabel("Back one run")
            }
            Button(action: onDone) {
                Text(finished ? "Close" : "Done")
                    .font(Font.Heather.done)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: Self.height)
                    .padding(.horizontal, 24)
                    .foregroundStyle(doneForeground)
                    .contentShape(Capsule())
                    .clearGlass()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneLabel)
        }
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: Self.gap) { row }
        } else {
            row
        }
    }
}

/// The yarn colors under the glass: capsules the size of the zone they occupy, blurred a touch so
/// they read as color pooled under the material rather than a second set of buttons.
private struct ColorTrack: View {
    let stops: [TrackStop]
    let showsBack: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                ForEach(stops) { stop in
                    let place = placement(for: stop.offset, width: width)
                    Capsule()
                        .fill(stop.hex.map(YarnSurface.fill) ?? Color.cream)
                        .frame(width: place.width, height: DoneField.height)
                        .offset(x: place.x)
                        .opacity(place.opacity)
                        .blur(radius: 2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func placement(for offset: Int, width: CGFloat) -> (x: CGFloat, width: CGFloat, opacity: Double) {
        let doneX = showsBack ? DoneField.backWidth + DoneField.gap : 0
        let doneWidth = width - doneX
        switch offset {
        case 0: return (doneX, doneWidth, 1)
        case -1: return showsBack ? (0, DoneField.backWidth, 1) : (-DoneField.backWidth - 40, DoneField.backWidth, 0)
        case ..<(-1): return (-DoneField.backWidth - 40, DoneField.backWidth, 0)
        default: return (width + 20, doneWidth, 1)
        }
    }
}

private extension View {
    /// Clear Liquid Glass on iOS 26 so the track shows through; a thin material capsule before that.
    @ViewBuilder func clearGlass() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.clear.interactive(), in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(YarnSurface.hairline, lineWidth: 1))
        }
    }
}
