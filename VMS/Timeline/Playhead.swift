import SwiftUI

/// The vertical line marking the current playhead position over the track lanes. Pure
/// presentation — positioning math goes through `TimelineGeometry` like everything else.
struct Playhead: View {
    let time: TimeInterval
    let geometry: TimelineGeometry
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: height)
            .offset(x: geometry.x(for: time))
            .allowsHitTesting(false)
    }
}
