import Foundation

public struct GradientColorStop: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Position along the gradient, 0...1.
    public var position: Double
    public var color: CodableColor

    public init(id: UUID = UUID(), position: Double, color: CodableColor) {
        self.id = id
        self.position = position
        self.color = color
    }
}

public enum GradientKind: String, Codable, CaseIterable, Sendable {
    case linear
    case radial

    public var displayName: String {
        switch self {
        case .linear: return "線形"
        case .radial: return "円形"
        }
    }
}

/// §7-5. Text-decoration gradient — rendered for real via SwiftUI's `Text.foregroundStyle`
/// (a `LinearGradient`/`RadialGradient` foreground style on the resolved text), so editing
/// stops here changes what the preview/export actually draw, not just a data model.
public struct GradientEffect: Codable, Hashable, Sendable {
    public var kind: GradientKind
    public var angleDegrees: Double
    public var stops: [GradientColorStop]

    public init(
        kind: GradientKind = .linear,
        angleDegrees: Double = 0,
        stops: [GradientColorStop] = [
            GradientColorStop(position: 0, color: CodableColor(red: 1, green: 0.85, blue: 0.2)),
            GradientColorStop(position: 1, color: CodableColor(red: 1, green: 0.3, blue: 0.5))
        ]
    ) {
        self.kind = kind
        self.angleDegrees = angleDegrees
        self.stops = stops.sorted { $0.position < $1.position }
    }
}
