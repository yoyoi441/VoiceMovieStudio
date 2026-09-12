import Foundation
import CoreGraphics

/// Single source of truth for time↔pixel conversion on the timeline. Every place that
/// used to write `time * pixelsPerSecond` (or the inverse) by hand — the ruler, the
/// playhead, clip rects, drag/resize gestures, the preview's seek bar — goes through this
/// instead, so zooming can never leave one of them out of sync with the others.
struct TimelineGeometry: Equatable {
    var pixelsPerSecond: Double

    func x(for time: TimeInterval) -> CGFloat {
        CGFloat(time * pixelsPerSecond)
    }

    func time(for x: CGFloat) -> TimeInterval {
        guard pixelsPerSecond > 0 else { return 0 }
        return max(0, Double(x) / pixelsPerSecond)
    }

    /// Unclamped conversion for a *delta* (e.g. a drag's `translation.width`), where a
    /// negative result is meaningful and shouldn't be floored to zero like `time(for:)`
    /// does for absolute positions.
    func deltaTime(forDeltaX deltaX: CGFloat) -> TimeInterval {
        guard pixelsPerSecond > 0 else { return 0 }
        return Double(deltaX) / pixelsPerSecond
    }

    func width(for duration: TimeInterval) -> CGFloat {
        max(4, CGFloat(duration * pixelsPerSecond))
    }
}
