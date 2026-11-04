import AiboCore
import SwiftUI

enum KeystrokeRowAnchor {
    case leading
    case center
    case trailing
}

/// Keycaps on the bubble's side of the aibo. No pointer; each cap scales and
/// fades in, later caps delayed by their place in the chord.
struct KeystrokeStrip: View {
    var rowAnchor: KeystrokeRowAnchor = .center

    private var monitor = KeystrokeMonitor.shared

    var body: some View {
        let presses = monitor.displayed
        let layout = KeystrokeStripLayout.layout(count: presses.count)
        KeystrokeGrid(
            side: CGFloat(layout.side),
            spacing: CGFloat(KeystrokeStripLayout.spacing),
            keysPerRow: layout.keysPerRow,
            anchor: rowAnchor
        ) {
            ForEach(presses) { press in
                KeystrokeKeycap(press: press, side: CGFloat(layout.side))
            }
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rows of equal caps. A short last row sits on `anchor` so it stays next to the aibo.
private struct KeystrokeGrid: Layout {
    var side: CGFloat
    var spacing: CGFloat
    var keysPerRow: Int
    var anchor: KeystrokeRowAnchor

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = subviews.count
        guard count > 0, keysPerRow > 0, side > 0 else { return .zero }
        let rows = (count + keysPerRow - 1) / keysPerRow
        let columns = min(count, keysPerRow)
        return CGSize(
            width: extent(columns),
            height: extent(rows)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0, keysPerRow > 0 else { return }
        let child = ProposedViewSize(width: side, height: side)
        for index in subviews.indices {
            let row = index / keysPerRow
            let column = index % keysPerRow
            let rowCount = min(keysPerRow, count - row * keysPerRow)
            let rowWidth = extent(rowCount)
            let x0: CGFloat
            switch anchor {
            case .leading:
                x0 = bounds.minX
            case .trailing:
                x0 = bounds.maxX - rowWidth
            case .center:
                x0 = bounds.minX + (bounds.width - rowWidth) / 2
            }
            subviews[index].place(
                at: CGPoint(
                    x: x0 + CGFloat(column) * (side + spacing),
                    y: bounds.minY + CGFloat(row) * (side + spacing)
                ),
                anchor: .topLeading,
                proposal: child
            )
        }
    }

    private func extent(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * side + CGFloat(count - 1) * spacing
    }
}

private struct KeystrokeKeycap: View {
    let press: KeystrokePress
    var side: CGFloat

    @State private var settled = false

    private var scale: CGFloat {
        guard KeystrokeStripLayout.regularSide > 0 else { return 1 }
        return side / CGFloat(KeystrokeStripLayout.regularSide)
    }

    var body: some View {
        face
            .scaleEffect(settled ? 1 : 0.72)
            .opacity(settled ? 1 : 0)
            .onAppear {
                let delay = Double(min(press.staggerIndex, 5)) * 0.05
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.spring(duration: 0.34, bounce: 0.2).delay(delay)) {
                        settled = true
                    }
                }
            }
    }

    private var face: some View {
        let shape = RoundedRectangle(
            cornerRadius: KeystrokeMetrics.cornerRadius * scale,
            style: .continuous
        )
        return ZStack {
            StatusBubble.chromeMaterial(
                shape,
                style: AppSettings.shared.bubbleGlassStyle,
                tint: AppSettings.shared.bubbleGlassTint,
                suppressGlass: false
            )
            legend
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private var legend: some View {
        if let symbolName = press.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: 28 * scale, weight: .medium))
                .foregroundStyle(.primary)
        } else {
            Text(press.label.localizedUppercase)
                .font(.system(size: (press.label.count > 3 ? 16 : 22) * scale, weight: .medium))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6 * scale)
        }
    }
}
