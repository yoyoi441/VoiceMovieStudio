import Foundation

/// A lip-sync keyframe: at `time` (seconds, relative to the clip's own start), show `shape`
/// until the next keyframe. Produced either by hand or automatically from VOICEVOX mora timing.
public struct MouthKeyframe: Codable, Hashable, Sendable {
    public var time: TimeInterval
    public var shape: MouthShape

    public init(time: TimeInterval, shape: MouthShape) {
        self.time = time
        self.shape = shape
    }
}

public enum TextWrapMode: String, Codable, CaseIterable, Sendable {
    case none
    case character
    case word

    public var displayName: String {
        switch self {
        case .none: return "折り返さない"
        case .character: return "文字単位"
        case .word: return "単語単位"
        }
    }
}

public enum TextHorizontalAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing

    public var displayName: String {
        switch self {
        case .leading: return "左揃え"
        case .center: return "中央揃え"
        case .trailing: return "右揃え"
        }
    }
}

/// §7-3 "表示方向"/"非表示方向" for the (data-only — see `TextClipData.splitPerCharacter`)
/// per-character reveal/conceal animation.
public enum RevealDirection: String, Codable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop

    public var displayName: String {
        switch self {
        case .leftToRight: return "左から右"
        case .rightToLeft: return "右から左"
        case .topToBottom: return "上から下"
        case .bottomToTop: return "下から上"
        }
    }
}

public struct TextClipData: Codable, Hashable, Sendable {
    public var text: String
    /// "字幕を表示する" — an independent visibility switch from the track's own
    /// show/hide, so a subtitle can be authored and toggled off without deleting it.
    public var isVisible: Bool
    public var fontName: String
    public var fontSize: Double
    public var lineHeight: Double
    public var letterSpacing: Double
    public var wrapMode: TextWrapMode
    /// Wrap width in the same 1920-wide baseline unit as `fontSize` (scaled to the actual
    /// canvas at draw time, like `fontSize` already is).
    public var wrapWidth: Double
    public var alignment: TextHorizontalAlignment
    public var color: CodableColor
    /// "装飾色" — reserved for effects that want a secondary color (kept as plain data;
    /// no built-in effect reads it yet).
    public var decorationColor: CodableColor
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var isStrikethrough: Bool
    public var trimTrailingSpace: Bool
    /// The following four fields describe a per-character reveal/conceal animation
    /// ("文字ごとに分割" + timing/direction). Data-only for now — no per-character
    /// rendering path exists yet, so these don't change what's drawn; see `CompositeFrameView`.
    public var splitPerCharacter: Bool
    public var revealInterval: TimeInterval
    public var revealDirection: RevealDirection
    public var concealInterval: TimeInterval
    public var concealDirection: RevealDirection
    /// Normalized position within the canvas (-1...1, centre origin; right/down positive).
    public var position: CodablePoint

    public init(
        text: String,
        isVisible: Bool = true,
        fontName: String = "HiraginoSans-W6",
        fontSize: Double = 48,
        lineHeight: Double = 1,
        letterSpacing: Double = 0,
        wrapMode: TextWrapMode = .none,
        wrapWidth: Double = 1600,
        alignment: TextHorizontalAlignment = .leading,
        color: CodableColor = .white,
        decorationColor: CodableColor = .black,
        isBold: Bool = true,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isStrikethrough: Bool = false,
        trimTrailingSpace: Bool = false,
        splitPerCharacter: Bool = false,
        revealInterval: TimeInterval = 0,
        revealDirection: RevealDirection = .leftToRight,
        concealInterval: TimeInterval = 0,
        concealDirection: RevealDirection = .leftToRight,
        position: CodablePoint = CodablePoint(x: 0, y: 0.7)
    ) {
        self.text = text
        self.isVisible = isVisible
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.wrapMode = wrapMode
        self.wrapWidth = wrapWidth
        self.alignment = alignment
        self.color = color
        self.decorationColor = decorationColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStrikethrough = isStrikethrough
        self.trimTrailingSpace = trimTrailingSpace
        self.splitPerCharacter = splitPerCharacter
        self.revealInterval = revealInterval
        self.revealDirection = revealDirection
        self.concealInterval = concealInterval
        self.concealDirection = concealDirection
        self.position = position
    }
}

public struct CharacterClipData: Codable, Hashable, Sendable {
    public var characterID: UUID
    /// The audio clip (by id, same track or another track) this character lip-syncs to.
    public var linkedAudioClipID: UUID?
    public var position: CodablePoint
    public var scale: Double
    public var mouthKeyframes: [MouthKeyframe]
    /// §7-6 "喋る時のみ表示" — hide the character whenever the current mouth shape is
    /// `.closed` (i.e. not actively speaking), instead of showing it for the clip's full
    /// duration.
    public var visibleOnlyWhenSpeaking: Bool
    public var expressionID: UUID?
    /// Optional for compatibility with existing projects. Evaluated by preview and export.
    public var motion: CharacterMotion? = nil

    public init(
        characterID: UUID,
        linkedAudioClipID: UUID? = nil,
        position: CodablePoint = CodablePoint(x: 0, y: 0.2),
        scale: Double = 1.0,
        mouthKeyframes: [MouthKeyframe] = [],
        visibleOnlyWhenSpeaking: Bool = false,
        expressionID: UUID? = nil
    ) {
        self.characterID = characterID
        self.linkedAudioClipID = linkedAudioClipID
        self.position = position
        self.scale = scale
        self.mouthKeyframes = mouthKeyframes
        self.visibleOnlyWhenSpeaking = visibleOnlyWhenSpeaking
        self.expressionID = expressionID
    }

    /// The mouth shape to render at `time` seconds relative to the clip's own start.
    public func mouthShape(at time: TimeInterval) -> MouthShape {
        var current: MouthShape = .closed
        for keyframe in mouthKeyframes where keyframe.time <= time {
            current = keyframe.shape
        }
        return current
    }

    /// Resolves a three-state lip-sync keyframe onto an arbitrary number of ordered
    /// visual frames. Extra frames are used as in-betweens during each state change,
    /// allowing detailed PSD mouth sets to animate without changing the audio analysis
    /// file format.
    public func mouthAnimationFrameIndex(
        at time: TimeInterval,
        frameCount: Int,
        transitionDuration: TimeInterval = 0.08
    ) -> Int {
        guard frameCount > 1, time.isFinite else { return 0 }
        var previous: MouthShape = .closed
        var current: MouthShape = .closed
        var transitionStart: TimeInterval?
        for keyframe in mouthKeyframes where keyframe.time <= time {
            previous = current
            current = keyframe.shape
            transitionStart = keyframe.time
        }
        let from = Character.mouthCompatibilityIndex(previous, frameCount: frameCount)
        let to = Character.mouthCompatibilityIndex(current, frameCount: frameCount)
        guard from != to, let transitionStart else { return to }
        let safeDuration = transitionDuration.isFinite ? min(max(transitionDuration, 0.01), 0.3) : 0.08
        let progress = min(1, max(0, (time - transitionStart) / safeDuration))
        return min(frameCount - 1, max(0, Int((Double(from) + Double(to - from) * progress).rounded())))
    }

    public func presentation(at time: TimeInterval) -> CharacterClipData {
        guard let motion, motion.duration.isFinite, motion.duration > 0,
              motion.offset.isFinite, time.isFinite,
              motion.fromPosition.x.isFinite, motion.fromPosition.y.isFinite,
              motion.fromScale.isFinite, motion.fromScale > 0 else { return self }
        let progress = min(1, max(0, (time + motion.offset) / motion.duration))
        let eased = progress * progress * (3 - 2 * progress)
        var result = self
        result.position = CodablePoint(
            x: motion.fromPosition.x + (position.x - motion.fromPosition.x) * eased,
            y: motion.fromPosition.y + (position.y - motion.fromPosition.y) * eased)
        result.scale = motion.fromScale + (scale - motion.fromScale) * eased
        result.motion = nil
        return result
    }
}

public struct CharacterMotion: Codable, Hashable, Sendable {
    public var fromPosition: CodablePoint
    public var fromScale: Double
    public var duration: Double
    /// Keeps the motion phase when a timeline clip is split or trimmed.
    public var offset: Double = 0
    public init(fromPosition: CodablePoint, fromScale: Double, duration: Double) {
        self.fromPosition = fromPosition
        self.fromScale = fromScale
        self.duration = duration
    }
}

public struct AudioClipData: Codable, Hashable, Sendable {
    /// Nil in legacy projects; imported voices must never regenerate through another engine.
    public var voiceProvider: String? = nil
    public var linkedSubtitleClipID: UUID? = nil
    /// File name relative to the project's Assets directory.
    public var fileName: String
    /// Original synthesis source text, if this clip came from TTS (kept for re-generation/subtitles).
    public var sourceText: String?
    /// Per-mora timing returned by the voice engine, used to drive auto lip-sync and subtitles.
    public var moraTimings: [MoraTiming]?
    /// The engine speaker this clip was synthesized with, if any (needed to re-synthesize
    /// after changing `voiceSettings`).
    public var speakerID: Int?
    /// Exact product-side assignment for name-based engines.
    public var voiceLibrary: String? = nil
    public var voiceStyle: String? = nil
    /// The parameters this clip was (or would be, on re-generation) synthesized with.
    public var voiceSettings: VoiceSettings
    /// §7-7 "利用条件などの説明欄" — free-form notes (e.g. a voice library's usage terms).
    public var licenseNotes: String

    public init(
        fileName: String,
        sourceText: String? = nil,
        moraTimings: [MoraTiming]? = nil,
        speakerID: Int? = nil,
        voiceLibrary: String? = nil,
        voiceStyle: String? = nil,
        voiceSettings: VoiceSettings = VoiceSettings(),
        licenseNotes: String = ""
    ) {
        self.fileName = fileName
        self.sourceText = sourceText
        self.moraTimings = moraTimings
        self.speakerID = speakerID
        self.voiceLibrary = voiceLibrary
        self.voiceStyle = voiceStyle
        self.voiceSettings = voiceSettings
        self.licenseNotes = licenseNotes
    }
}

public struct ImageClipData: Codable, Hashable, Sendable {
    /// File name relative to the project's Assets directory.
    public var fileName: String
    public var position: CodablePoint
    public var scale: Double

    public init(fileName: String, position: CodablePoint = CodablePoint(x: 0, y: 0), scale: Double = 1.0) {
        self.fileName = fileName
        self.position = position
        self.scale = scale
    }
}

public struct VideoClipData: Codable, Hashable, Sendable {
    /// Project media-library id and file name relative to Assets.
    public var assetID: UUID
    public var fileName: String
    /// In-point in the source movie. `Clip.duration` is the selected source length.
    public var sourceStartTime: TimeInterval
    public var position: CodablePoint
    public var scale: Double
    public var volume: Double
    public var isMuted: Bool

    public init(
        assetID: UUID,
        fileName: String,
        sourceStartTime: TimeInterval = 0,
        position: CodablePoint = CodablePoint(x: 0, y: 0),
        scale: Double = 1,
        volume: Double = 1,
        isMuted: Bool = false
    ) {
        self.assetID = assetID
        self.fileName = fileName
        self.sourceStartTime = sourceStartTime
        self.position = position
        self.scale = scale
        self.volume = volume
        self.isMuted = isMuted
    }
}

public enum ClipContent: Codable, Hashable, Sendable {
    case text(TextClipData)
    case character(CharacterClipData)
    case audio(AudioClipData)
    case image(ImageClipData)
    case video(VideoClipData)
}

public struct Clip: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startTime: TimeInterval
    public var duration: TimeInterval
    public var content: ClipContent
    public var effects: ClipEffects
    /// Locked items can't be moved, resized, or edited from the timeline/inspector until
    /// unlocked again (independent of `Track.isLocked`, which locks the whole layer).
    public var isLocked: Bool

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        duration: TimeInterval,
        content: ClipContent,
        effects: ClipEffects = ClipEffects(),
        isLocked: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.content = content
        self.effects = effects
        self.isLocked = isLocked
    }

    public var endTime: TimeInterval { startTime + duration }

    public func contains(time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}
