import Foundation

/// Turns per-mora voice timing into mouth-shape keyframes. This is a coarse viseme
/// approximation (three shapes, chosen from the vowel sound) rather than true phoneme
/// animation — suitable for simple character speech, cheap enough to compute instantly.
public enum LipSyncGenerator {
    public static func keyframes(from moraTimings: [MoraTiming], speed: Double = 1.0) -> [MouthKeyframe] {
        guard !moraTimings.isEmpty else { return [] }
        let safeSpeed = min(max(speed, 0.5), 3.0)

        var keyframes: [MouthKeyframe] = []
        for mora in moraTimings {
            let shape = mouthShape(for: mora)
            keyframes.append(MouthKeyframe(time: mora.startTime, shape: shape))
            let activeDuration = mora.duration / safeSpeed
            keyframes.append(MouthKeyframe(time: mora.startTime + activeDuration, shape: .closed))
        }
        return keyframes
    }

    private static func mouthShape(for mora: MoraTiming) -> MouthShape {
        guard !mora.isPause, let vowel = mora.vowel else { return .closed }
        switch vowel {
        case "a", "o":
            return .open
        case "i", "u", "e":
            return .small
        default:
            return .closed
        }
    }
}
