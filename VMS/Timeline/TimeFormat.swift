import Foundation

/// Single place that turns a `TimeInterval` into the `00:00:02.00` (hh:mm:ss.ff) display
/// format the ruler/playhead/inspector all use, and back. `ff` is frame count within the
/// current second (per `Project.frameRate`), not centiseconds — matches common editors and
/// timeline editors show sub-second position.
enum TimeFormat {
    static func string(from time: TimeInterval, frameRate: Double) -> String {
        let fps = max(1, Int(frameRate.rounded()))
        let totalFrames = Int((max(0, time) * frameRate).rounded())
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, frames)
    }
}
