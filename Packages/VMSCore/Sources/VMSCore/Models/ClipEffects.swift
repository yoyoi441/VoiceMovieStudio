import Foundation

public struct TextOutlineEffect: Codable, Hashable, Sendable {
    public var color: CodableColor
    public var width: Double

    public init(color: CodableColor = .black, width: Double = 4) {
        self.color = color
        self.width = width
    }
}

public struct TextShadowEffect: Codable, Hashable, Sendable {
    public var color: CodableColor
    public var radius: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(color: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 0.6), radius: Double = 4, offsetX: Double = 2, offsetY: Double = 2) {
        self.color = color
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

/// §7-2. Only `normal`/`add`/`multiply`/`screen` render for real (all four map directly
/// onto SwiftUI's `GraphicsContext.BlendMode`); every case is still selectable so the
/// control isn't artificially limited to what's wired up today.
public enum BlendModeOption: String, Codable, CaseIterable, Sendable {
    case normal
    case add
    case multiply
    case screen

    public var displayName: String {
        switch self {
        case .normal: return "通常"
        case .add: return "加算"
        case .multiply: return "乗算"
        case .screen: return "スクリーン"
        }
    }
}

/// Common per-clip editing properties ("共通設定" + "オブジェクト効果"). Fade/
/// opacity/scale/rotation/blend-mode/flip/z-order/clipping/notes are always-present
/// per-clip settings (§7-2); `effectsList` is the separate, user-managed stack of
/// additional effects (§7-4: blur/outline/shadow/gradient/…) with its own add/remove/
/// reorder/enable-toggle UI. For audio clips, `fadeInDuration`/`fadeOutDuration` mean a
/// volume ramp instead of an opacity ramp — same controls, meaning follows content type.
public struct ClipEffects: Codable, Hashable, Sendable {
    public var opacity: Double
    public var fadeInDuration: TimeInterval
    public var fadeOutDuration: TimeInterval
    public var scale: Double
    public var rotationDegrees: Double
    public var blendMode: BlendModeOption
    public var flipHorizontal: Bool
    /// "手前に表示" — draws this clip after (on top of) other same-track-time clips
    /// regardless of track order.
    public var showInFront: Bool
    /// "Z値順に表示" — when on, `zPosition` (rather than track order) decides draw order
    /// among visible clips at the same time.
    public var useZOrder: Bool
    public var zPosition: Double
    /// "クリッピング" — per-item opt-in to the toolbar's "上のアイテムを基準にした
    /// クリッピング" behavior (`ProjectStore.isClipAboveOnlyEnabled`).
    public var clipToAbove: Bool
    public var notes: String
    public var effectsList: [Effect]

    public init(
        opacity: Double = 1,
        fadeInDuration: TimeInterval = 0,
        fadeOutDuration: TimeInterval = 0,
        scale: Double = 1,
        rotationDegrees: Double = 0,
        blendMode: BlendModeOption = .normal,
        flipHorizontal: Bool = false,
        showInFront: Bool = false,
        useZOrder: Bool = false,
        zPosition: Double = 0,
        clipToAbove: Bool = false,
        notes: String = "",
        effectsList: [Effect] = []
    ) {
        self.opacity = opacity
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.blendMode = blendMode
        self.flipHorizontal = flipHorizontal
        self.showInFront = showInFront
        self.useZOrder = useZOrder
        self.zPosition = zPosition
        self.clipToAbove = clipToAbove
        self.notes = notes
        self.effectsList = effectsList
    }

    /// Multiplier (0-1) from fade in/out at `localTime` seconds into a clip of `duration`
    /// seconds. Used as an opacity multiplier for visuals and a volume multiplier for audio.
    public func fadeMultiplier(localTime: TimeInterval, duration: TimeInterval) -> Double {
        var multiplier = 1.0
        if fadeInDuration > 0 {
            multiplier = min(multiplier, max(0, localTime / fadeInDuration))
        }
        if fadeOutDuration > 0 {
            let remaining = duration - localTime
            multiplier = min(multiplier, max(0, remaining / fadeOutDuration))
        }
        return multiplier
    }
}
