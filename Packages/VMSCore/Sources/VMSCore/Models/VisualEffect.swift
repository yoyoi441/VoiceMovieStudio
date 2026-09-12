import Foundation

/// Parameters are percentages of the canvas, except shake (pixels at 1920px width).
/// The same deterministic sampler drives preview and export; no random/frame counters.
public enum VisualEffectType: String, Codable, CaseIterable, Sendable {
    case move, shake, spin, pulse, blink, colorAdjustment, verticalFlip, crop
    public var displayName: String {
        switch self {
        case .move: "移動・拡大縮小"
        case .shake: "振動"
        case .spin: "連続回転"
        case .pulse: "拡大縮小の繰り返し"
        case .blink: "点滅（なめらか）"
        case .colorAdjustment: "色調整"
        case .verticalFlip: "上下反転"
        case .crop: "画面範囲の切り抜き"
        }
    }
    public var parameters: [VisualEffectParameter] {
        switch self {
        case .move: [
            .init("fromX", "開始X", -200...200, 0, "%"), .init("fromY", "開始Y", -200...200, 0, "%"),
            .init("toX", "終了X", -200...200, 20, "%"), .init("toY", "終了Y", -200...200, 0, "%"),
            .init("fromScale", "開始倍率", 1...500, 100, "%"), .init("toScale", "終了倍率", 1...500, 100, "%"),
            .init("seconds", "移動時間", 0.01...600, 1, "秒", step: 0.01)]
        case .shake: [
            .init("x", "横の振幅", 0...200, 8, "px"), .init("y", "縦の振幅", 0...200, 8, "px"),
            .init("rotation", "角度振幅", 0...45, 0, "°"), .init("frequency", "速さ", 0.1...15, 8, "Hz", step: 0.1)]
        case .spin: [.init("speed", "回転速度", -720...720, 90, "°/秒")]
        case .pulse: [.init("amount", "振幅", 0...90, 10, "%"), .init("frequency", "速さ", 0.1...10, 1, "Hz", step: 0.1)]
        case .blink: [.init("minimum", "最低濃度", 0...100, 20, "%"), .init("frequency", "速さ", 0.1...3, 1, "Hz", step: 0.1)]
        case .colorAdjustment: [
            .init("brightness", "明るさ", -100...100, 0, "%"), .init("contrast", "コントラスト", 0...300, 100, "%"),
            .init("saturation", "彩度", 0...300, 100, "%"), .init("hue", "色相", -180...180, 0, "°")]
        case .verticalFlip: []
        case .crop: ["left", "right", "top", "bottom"].enumerated().map {
            .init($0.element, ["左", "右", "上", "下"][$0.offset], 0...95, 0, "%")
        }
        }
    }
}

public struct VisualEffectParameter: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let range: ClosedRange<Double>
    public let defaultValue: Double
    public let unit: String
    public let step: Double
    public init(_ id: String, _ label: String, _ range: ClosedRange<Double>, _ defaultValue: Double, _ unit: String, step: Double = 1) {
        self.id = id; self.label = label; self.range = range; self.defaultValue = defaultValue; self.unit = unit; self.step = step
    }
    public func clamp(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : defaultValue
    }
}

public enum VisualEasing: String, Codable, CaseIterable, Sendable {
    case linear, smooth
    public var displayName: String { self == .linear ? "等速" : "なめらか" }
}

public struct VisualEffect: Codable, Hashable, Sendable {
    public var type: VisualEffectType
    public var parameters: [String: Double] = [:]
    public var easing: VisualEasing = .smooth
    public init(_ type: VisualEffectType) { self.type = type }
    public func value(_ key: String) -> Double {
        guard let definition = type.parameters.first(where: { $0.id == key }) else { return 0 }
        return definition.clamp(parameters[key] ?? definition.defaultValue)
    }
    public mutating func setValue(_ key: String, _ value: Double) {
        guard let definition = type.parameters.first(where: { $0.id == key }) else { return }
        parameters[key] = definition.clamp(value)
    }
    public func sample(at localTime: Double) -> VisualEffectSample {
        let time = localTime.isFinite ? min(86400 * 365, max(0, localTime)) : 0
        var result = VisualEffectSample()
        switch type {
        case .move:
            let p = min(1, time / value("seconds"))
            let t = easing == .smooth ? p * p * (3 - 2 * p) : p
            result.x = (value("fromX") + (value("toX") - value("fromX")) * t) / 100
            result.y = (value("fromY") + (value("toY") - value("fromY")) * t) / 100
            result.scale = (value("fromScale") + (value("toScale") - value("fromScale")) * t) / 100
        case .shake:
            let phase = time * value("frequency") * 2 * Double.pi
            result.pixelX = value("x") * sin(phase)
            result.pixelY = value("y") * sin(phase * 1.31)
            result.rotation = value("rotation") * sin(phase * 0.73)
        case .spin: result.rotation = (time * value("speed")).truncatingRemainder(dividingBy: 360)
        case .pulse: result.scale = 1 + value("amount") / 100 * sin(time * value("frequency") * 2 * .pi)
        case .blink:
            let low = value("minimum") / 100
            result.opacity = low + (1 - low) * (1 + cos(time * value("frequency") * 2 * .pi)) / 2
        case .verticalFlip: result.flipVertical = true
        case .crop, .colorAdjustment: break
        }
        return result
    }
}

public struct VisualEffectSample: Hashable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var pixelX: Double = 0
    public var pixelY: Double = 0
    public var scale: Double = 1
    public var rotation: Double = 0
    public var opacity: Double = 1
    public var flipVertical = false
    public init() {}
}
