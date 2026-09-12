import SwiftUI
import VMSCore

/// §5: time ruler. Tick spacing adapts to zoom (picks a "nice" interval so major ticks
/// land roughly every 80-150pt regardless of `pixelsPerSecond`), major ticks are labeled
/// `00:00:02.00` via `TimeFormat`, and click/drag scrubs the playhead — all through the
/// same `TimelineGeometry` the timeline body and clips use, so nothing can fall out of
/// sync when zooming.
struct TimeRuler: View {
    let duration: TimeInterval
    let frameRate: Double
    let geometry: TimelineGeometry
    @Binding var playhead: TimeInterval

    /// "Nice" seconds-per-major-tick steps to choose from as zoom changes.
    private static let niceIntervals: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]

    var body: some View {
        let majorInterval = niceMajorInterval()
        let minorInterval = majorInterval / 5

        Canvas { context, size in
            var t = 0.0
            while t <= duration {
                let x = geometry.x(for: t)
                let isMajor = isApproximately(t, (t / majorInterval).rounded() * majorInterval)
                let tick = tickPath(x: x, height: size.height, isMajor: isMajor)
                context.stroke(tick, with: .color(.secondary), lineWidth: 1)
                if isMajor {
                    let label = context.resolve(
                        Text(TimeFormat.string(from: t, frameRate: frameRate))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    )
                    context.draw(label, at: CGPoint(x: x + 3, y: 3), anchor: .topLeading)
                }
                t += minorInterval
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in playhead = geometry.time(for: value.location.x) }
        )
    }

    private func tickPath(x: CGFloat, height: CGFloat, isMajor: Bool) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: isMajor ? 8 : 14))
        path.addLine(to: CGPoint(x: x, y: height))
        return path
    }

    private func niceMajorInterval() -> Double {
        let targetPixels = 100.0
        for interval in Self.niceIntervals {
            if geometry.pixelsPerSecond * interval >= targetPixels {
                return interval
            }
        }
        return Self.niceIntervals.last ?? 600
    }
}

/// Loose float equality for picking whether a minor tick lands on a major boundary.
private func isApproximately(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 0.0001
}
