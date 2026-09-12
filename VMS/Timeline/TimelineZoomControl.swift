import SwiftUI
import VMSCore

/// §3-1: zoom percentage readout, slider, in/out buttons, fit-to-window. Everything here
/// mutates `store.pixelsPerSecond` directly and continuously (not gated behind
/// `onEditingChanged`) so the ruler and every clip's width update live while dragging, per
/// spec — zoom is view state, not project content, so it deliberately isn't undoable.
struct TimelineZoomControl: View {
    @Environment(ProjectStore.self) private var store

    private let baselinePixelsPerSecond: Double = 120
    private let minPercent: Double = 20
    private let maxPercent: Double = 400

    var body: some View {
        HStack(spacing: 4) {
            Button { zoom(by: 0.8) } label: {
                IconCatalog.resolve(.zoomOut).font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("縮小")

            Slider(value: percentBinding, in: minPercent...maxPercent)
                .frame(width: 110)

            Button { zoom(by: 1.25) } label: {
                IconCatalog.resolve(.zoomIn).font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("拡大")

            Text("\(Int(percent))%")
                .font(Theme.valueFont)
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .trailing)

            Button { fitToWindow() } label: {
                IconCatalog.resolve(.zoomFit).font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("表示範囲に合わせる")
        }
    }

    private var percent: Double {
        store.pixelsPerSecond / baselinePixelsPerSecond * 100
    }

    private var percentBinding: Binding<Double> {
        Binding(
            get: { percent },
            set: { store.pixelsPerSecond = max(1, $0 / 100 * baselinePixelsPerSecond) }
        )
    }

    private func zoom(by factor: Double) {
        let clamped = min(maxPercent, max(minPercent, percent * factor))
        store.pixelsPerSecond = clamped / 100 * baselinePixelsPerSecond
    }

    private func fitToWindow() {
        let duration = max(store.currentTimeline.duration, 1)
        let fitted = store.timelineViewportWidth / duration
        let minPixelsPerSecond = minPercent / 100 * baselinePixelsPerSecond
        let maxPixelsPerSecond = maxPercent / 100 * baselinePixelsPerSecond
        store.pixelsPerSecond = min(maxPixelsPerSecond, max(minPixelsPerSecond, fitted))
    }
}
