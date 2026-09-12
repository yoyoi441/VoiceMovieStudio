import Foundation

/// Persisted effects rendered through the shared preview/export canvas.
/// Text decoration precedes visual effects.
public enum EffectKind: Codable, Hashable, Sendable {
    case blur(radius: Double)
    case outline(TextOutlineEffect)
    case shadow(TextShadowEffect)
    case gradient(GradientEffect)
    case monochrome
    case mosaic(blockSize: Double)
    case glow(radius: Double)
    case visual(VisualEffect)

    public var displayName: String {
        switch self {
        case .blur: return "ぼかし"
        case .outline: return "縁取り"
        case .shadow: return "影"
        case .gradient: return "グラデーション"
        case .monochrome: return "モノクロ"
        case .mosaic: return "モザイク"
        case .glow: return "発光"
        case .visual(let value): return value.type.displayName
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .blur, .outline, .shadow, .gradient, .monochrome, .mosaic, .glow, .visual: return true
        }
    }

    /// Whether this effect only makes sense on text content (shown for text clips only in
    /// the "add effect" menu; still decodes fine anywhere since it's just data).
    public var isTextOnly: Bool {
        switch self {
        case .outline, .shadow, .gradient: return true
        case .blur, .monochrome, .mosaic, .glow, .visual: return false
        }
    }

    public static func defaultInstance(for kindTemplate: EffectKindTemplate) -> EffectKind {
        switch kindTemplate {
        case .blur: return .blur(radius: 8)
        case .outline: return .outline(TextOutlineEffect())
        case .shadow: return .shadow(TextShadowEffect())
        case .gradient: return .gradient(GradientEffect())
        case .monochrome: return .monochrome
        case .mosaic: return .mosaic(blockSize: 8)
        case .glow: return .glow(radius: 8)
        case .move: return .visual(VisualEffect(.move))
        case .shake: return .visual(VisualEffect(.shake))
        case .spin: return .visual(VisualEffect(.spin))
        case .pulse: return .visual(VisualEffect(.pulse))
        case .blink: return .visual(VisualEffect(.blink))
        case .colorAdjustment: return .visual(VisualEffect(.colorAdjustment))
        case .verticalFlip: return .visual(VisualEffect(.verticalFlip))
        case .crop: return .visual(VisualEffect(.crop))
        }
    }
}

/// Stand-in for "which effect to add" menus/pickers — `EffectKind`'s associated values
/// mean it can't be a plain `CaseIterable` enum, so this lighter enum (no payload) is what
/// `EffectList`'s "add" menu iterates over.
public enum EffectKindTemplate: String, CaseIterable, Sendable {
    case blur, outline, shadow, gradient, monochrome, mosaic, glow
    case move, shake, spin, pulse, blink, colorAdjustment, verticalFlip, crop

    public var displayName: String { EffectKind.defaultInstance(for: self).displayName }
    public var isTextOnly: Bool { EffectKind.defaultInstance(for: self).isTextOnly }
}

public struct Effect: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var kind: EffectKind
    /// Preserves animation phase after splitting or trimming the start of a clip.
    public var timeOffset: Double? = nil

    public init(id: UUID = UUID(), isEnabled: Bool = true, kind: EffectKind) {
        self.id = id
        self.isEnabled = isEnabled
        self.kind = kind
    }
}
