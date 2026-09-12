import SwiftUI
import CoreImage
import VMSCore

/// Draws one composited frame of the project at `time`. Pure value inputs (no
/// `ProjectStore`/environment dependency) so the exact same view can be used for the live
/// preview canvas and, via `ImageRenderer`, for rendering each output frame during export.
struct CompositeFrameView: View {
    let project: Project
    /// The specific scene being drawn — `Project` no longer has a single `timeline`, since
    /// a project can have multiple scenes, so the caller says which one.
    let timeline: Timeline
    let time: TimeInterval
    let imageProvider: CharacterImageProvider
    let videoFrameProvider: VideoFrameProvider
    var drawsBackground = true
    private static let effectContext = CIContext(options: [.cacheIntermediates: false])

    var body: some View {
        Canvas { context, size in
            let canvasRect = CGRect(origin: .zero, size: size)
            if drawsBackground { context.fill(Path(canvasRect), with: .color(.black)) }

            for clip in timeline.visibleClipsInDrawOrder(at: time) {
                drawWithEffects(clip: clip, in: &context, canvasSize: size)
            }
        }
        .frame(width: project.resolution.width, height: project.resolution.height)
    }

    /// Applies `clip.effects` — fade → opacity, blend mode, the effect list's blur, then
    /// scale/rotation/flip — as an isolated layer around the clip's own content drawing,
    /// so per-content drawing code stays unaware of most of this. Audio clips draw nothing.
    private func drawWithEffects(clip: Clip, in context: inout GraphicsContext, canvasSize: CGSize) {
        let localTime = time - clip.startTime
        var clip = clip
        if case .character(let data) = clip.content {
            clip.content = .character(data.presentation(at: localTime))
        }
        let opacity = clip.effects.opacity * clip.effects.fadeMultiplier(localTime: localTime, duration: clip.duration)
        guard opacity > 0.001 else { return }

        context.drawLayer { layer in
            layer.opacity = opacity
            layer.blendMode = Self.graphicsBlendMode(for: clip.effects.blendMode)

            if clip.effects.scale != 1 || clip.effects.rotationDegrees != 0 || clip.effects.flipHorizontal {
                let anchor = anchorPoint(for: clip, canvasSize: canvasSize)
                layer.translateBy(x: anchor.x, y: anchor.y)
                layer.rotate(by: .degrees(clip.effects.rotationDegrees))
                layer.scaleBy(x: (clip.effects.flipHorizontal ? -1 : 1) * clip.effects.scale, y: clip.effects.scale)
                layer.translateBy(x: -anchor.x, y: -anchor.y)
            }

            let effects = Array(clip.effects.effectsList.filter { $0.isEnabled && !$0.kind.isTextOnly }.prefix(64))
            drawEffectStack(effects, index: effects.count - 1, clip: clip, in: &layer, canvasSize: canvasSize)
        }
    }

    /// Outer layers apply the last list entry last, preserving the user's effect order.
    private func drawEffectStack(_ effects: [Effect], index: Int, clip: Clip,
                                 in context: inout GraphicsContext, canvasSize: CGSize) {
        if index >= 0, isRasterEffect(effects[index].kind) {
            drawRasterEffects(effects, index: index, clip: clip, in: &context, canvasSize: canvasSize)
            return
        }
        guard index >= 0 else {
            switch clip.content {
            case .text(let data) where data.isVisible:
                drawText(data, effectsList: clip.effects.effectsList, in: &context, canvasSize: canvasSize)
            case .text:
                break
            case .character(let data):
                drawCharacter(data, clip: clip, in: &context, canvasSize: canvasSize)
            case .image(let data):
                drawImage(data, in: &context, canvasSize: canvasSize)
            case .video(let data):
                drawVideo(data, clip: clip, in: &context, canvasSize: canvasSize)
            case .audio:
                break
            }
            return
        }
        context.drawLayer { layer in
            let effect = effects[index]
            switch effect.kind {
            case .blur(let radius): layer.addFilter(.blur(radius: safe(radius, in: 0...50)))
            case .glow(let radius):
                layer.addFilter(.shadow(color: .white.opacity(0.8), radius: safe(radius, in: 0...50), x: 0, y: 0))
            case .visual(let visual):
                let offset = (effect.timeOffset ?? 0).isFinite ? effect.timeOffset ?? 0 : 0
                let sample = visual.sample(at: time - clip.startTime + offset)
                layer.opacity *= sample.opacity
                let anchor = anchorPoint(for: clip, canvasSize: canvasSize)
                layer.translateBy(x: sample.x * canvasSize.width + sample.pixelX * canvasSize.width / 1920,
                                  y: sample.y * canvasSize.height + sample.pixelY * canvasSize.width / 1920)
                layer.translateBy(x: anchor.x, y: anchor.y)
                layer.rotate(by: .degrees(sample.rotation))
                layer.scaleBy(x: sample.scale, y: sample.scale * (sample.flipVertical ? -1 : 1))
                layer.translateBy(x: -anchor.x, y: -anchor.y)
                if visual.type == .crop {
                    let left = visual.value("left") / 100, right = visual.value("right") / 100
                    let top = visual.value("top") / 100, bottom = visual.value("bottom") / 100
                    layer.clip(to: Path(CGRect(x: left * canvasSize.width, y: top * canvasSize.height,
                        width: max(0, 1 - left - right) * canvasSize.width,
                        height: max(0, 1 - top - bottom) * canvasSize.height)))
                }
            default: break
            }
            drawEffectStack(effects, index: index - 1, clip: clip, in: &layer, canvasSize: canvasSize)
        }
    }

    private func safe(_ value: Double, in range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }

    private func isRasterEffect(_ kind: EffectKind) -> Bool {
        switch kind {
        case .monochrome, .mosaic: true
        case .visual(let value): value.type == .colorAdjustment
        default: false
        }
    }

    /// ImageRenderer's CoreGraphics backend can ignore Canvas color filters. Render
    /// the transparent source once, then apply consecutive color filters with Core Image.
    /// Preview and export use this same path; the CIContext is reused across frames.
    private func drawRasterEffects(_ effects: [Effect], index: Int, clip: Clip,
                                   in context: inout GraphicsContext, canvasSize: CGSize) {
        var first = index
        while first > 0 && isRasterEffect(effects[first - 1].kind) { first -= 1 }
        var source = clip
        source.effects = ClipEffects(effectsList: clip.effects.effectsList.filter { $0.kind.isTextOnly } + effects.prefix(first))
        let renderer = ImageRenderer(content: CompositeFrameView(project: project,
            timeline: Timeline(tracks: [Track(name: "描画", clips: [source])]), time: time,
            imageProvider: imageProvider, videoFrameProvider: videoFrameProvider, drawsBackground: false))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return }
        var output = CIImage(cgImage: cgImage)
        let bounds = output.extent
        for effect in effects[first...index] {
            switch effect.kind {
            case .monochrome:
                output = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            case .visual(let value):
                output = output.applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: value.value("brightness") / 100,
                    kCIInputContrastKey: value.value("contrast") / 100,
                    kCIInputSaturationKey: value.value("saturation") / 100])
                output = output.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: value.value("hue") * .pi / 180])
            case .mosaic(let size):
                output = output.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(1, safe(size, in: 1...200) * canvasSize.width / 1920)])
            default: break
            }
        }
        guard let result = Self.effectContext.createCGImage(output.cropped(to: bounds), from: bounds) else { return }
        context.draw(Image(decorative: result, scale: 1), in: CGRect(origin: .zero, size: canvasSize))
    }

    private static func graphicsBlendMode(for option: BlendModeOption) -> GraphicsContext.BlendMode {
        switch option {
        case .normal: return .normal
        case .add: return .plusLighter
        case .multiply: return .multiply
        case .screen: return .screen
        }
    }

    private func anchorPoint(for clip: Clip, canvasSize: CGSize) -> CGPoint {
        let position: CodablePoint
        switch clip.content {
        case .text(let data): position = data.position
        case .character(let data): position = data.position
        case .image(let data): position = data.position
        case .video(let data): position = data.position
        case .audio: return .zero
        }
        return Self.canvasPoint(position, in: canvasSize)
    }

    private func drawVideo(_ data: VideoClipData, clip: Clip, in context: inout GraphicsContext, canvasSize: CGSize) {
        let sourceTime = data.sourceStartTime + max(0, time - clip.startTime)
        guard let image = videoFrameProvider.image(
            fileName: data.fileName,
            sourceTime: sourceTime,
            frameRate: project.frameRate
        ) else { return }
        let naturalSize = image.size
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        let canvasAspect = canvasSize.width / canvasSize.height
        let imageAspect = naturalSize.width / naturalSize.height
        let fitted: CGSize
        if imageAspect > canvasAspect {
            fitted = CGSize(width: canvasSize.width, height: canvasSize.width / imageAspect)
        } else {
            fitted = CGSize(width: canvasSize.height * imageAspect, height: canvasSize.height)
        }
        let size = CGSize(width: fitted.width * data.scale, height: fitted.height * data.scale)
        let center = Self.canvasPoint(data.position, in: canvasSize)
        context.draw(
            Image(nsImage: image),
            in: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        )
    }

    private func drawImage(_ data: ImageClipData, in context: inout GraphicsContext, canvasSize: CGSize) {
        guard let image = imageProvider.image(named: data.fileName) else { return }
        let naturalSize = image.size
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        let targetHeight = canvasSize.height * 0.5 * data.scale
        let targetWidth = targetHeight * (naturalSize.width / naturalSize.height)
        let center = Self.canvasPoint(data.position, in: canvasSize)
        let rect = CGRect(
            x: center.x - targetWidth / 2,
            y: center.y - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        context.draw(Image(nsImage: image), in: rect)
    }

    /// §7-3. Wrapping honors `wrapWidth` for real (the resolved text is drawn `in:` a
    /// constrained rect instead of `at:`, which lets `GraphicsContext.ResolvedText` break
    /// lines itself). `alignment` only moves the anchor point of the whole block, and
    /// `lineHeight` isn't applied at all: `GraphicsContext.resolve(_:)` requires an exact
    /// `Text`, and both `.multilineTextAlignment` and `.lineSpacing` are `View`-level
    /// modifiers (return `some View`, not `Text`), so neither can be chained onto a value
    /// this API accepts. `splitPerCharacter`/reveal/conceal timing are data-only too — no
    /// per-character rendering path exists, so they don't change what's drawn yet.
    private func drawText(_ data: TextClipData, effectsList: [Effect], in context: inout GraphicsContext, canvasSize: CGSize) {
        let point = Self.canvasPoint(data.position, in: canvasSize)
        let color = Color(
            red: data.color.red, green: data.color.green, blue: data.color.blue, opacity: data.color.alpha
        )
        let scale = canvasSize.width / 1920
        let fontSize = data.fontSize * scale
        let wrapWidth = data.wrapWidth * scale
        let displayString = data.trimTrailingSpace
            ? String(data.text.reversed().drop { $0 == " " || $0 == "\t" || $0 == "\u{3000}" }.reversed())
            : data.text

        let shadow = Self.firstEnabled(in: effectsList) { kind -> TextShadowEffect? in
            if case .shadow(let value) = kind { return value }
            return nil
        }
        let outline = Self.firstEnabled(in: effectsList) { kind -> TextOutlineEffect? in
            if case .outline(let value) = kind { return value }
            return nil
        }
        let gradient = Self.firstEnabled(in: effectsList) { kind -> GradientEffect? in
            if case .gradient(let value) = kind { return value }
            return nil
        }

        if let shadow {
            context.addFilter(.shadow(
                color: Color(
                    red: shadow.color.red, green: shadow.color.green, blue: shadow.color.blue, opacity: shadow.color.alpha
                ),
                radius: shadow.radius,
                x: shadow.offsetX,
                y: shadow.offsetY
            ))
        }

        func styled(_ base: Text) -> Text {
            var styledText = base
                .font(Self.font(size: fontSize, name: data.fontName, bold: data.isBold, italic: data.isItalic))
                .tracking(data.letterSpacing * scale)
            if data.isUnderlined { styledText = styledText.underline() }
            if data.isStrikethrough { styledText = styledText.strikethrough() }
            return styledText
        }

        if let outline {
            let outlineColor = Color(
                red: outline.color.red, green: outline.color.green, blue: outline.color.blue, opacity: outline.color.alpha
            )
            let outlineText = context.resolve(styled(Text(displayString)).foregroundColor(outlineColor))
            for angleDegrees in stride(from: 0.0, to: 360.0, by: 45.0) {
                let radians = angleDegrees * .pi / 180
                let offset = CGPoint(x: cos(radians) * outline.width, y: sin(radians) * outline.width)
                draw(outlineText, at: point, offset: offset, wrapWidth: data.wrapMode == .none ? nil : wrapWidth, canvasSize: canvasSize, context: &context)
            }
        }

        var mainText = styled(Text(displayString))
        mainText = gradient.map { mainText.foregroundStyle(Self.gradientShapeStyle($0)) } ?? mainText.foregroundColor(color)
        let resolved = context.resolve(mainText)
        draw(resolved, at: point, offset: .zero, wrapWidth: data.wrapMode == .none ? nil : wrapWidth, canvasSize: canvasSize, context: &context)
    }

    private func draw(
        _ resolved: GraphicsContext.ResolvedText,
        at point: CGPoint,
        offset: CGPoint,
        wrapWidth: CGFloat?,
        canvasSize: CGSize,
        context: inout GraphicsContext
    ) {
        if let wrapWidth {
            let height = resolved.measure(in: CGSize(width: wrapWidth, height: .greatestFiniteMagnitude)).height
            let rect = CGRect(x: point.x + offset.x, y: point.y - height / 2 + offset.y, width: wrapWidth, height: height)
            context.draw(resolved, in: rect)
        } else {
            let size = resolved.measure(in: canvasSize)
            context.draw(resolved, at: CGPoint(x: point.x + offset.x, y: point.y - size.height / 2 + offset.y), anchor: .leading)
        }
    }

    private static func font(size: CGFloat, name: String, bold: Bool, italic: Bool) -> Font {
        var font: Font = name.isEmpty ? .system(size: size) : .custom(name, size: size)
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }

    private static func firstEnabled<T>(in effectsList: [Effect], _ extract: (EffectKind) -> T?) -> T? {
        for effect in effectsList where effect.isEnabled {
            if let value = extract(effect.kind) { return value }
        }
        return nil
    }

    private static func gradientShapeStyle(_ gradient: GradientEffect) -> AnyShapeStyle {
        let stops = gradient.stops.map { Gradient.Stop(color: $0.color.color, location: $0.position) }
        switch gradient.kind {
        case .linear:
            let radians = gradient.angleDegrees * .pi / 180
            let start = UnitPoint(x: 0.5 - cos(radians) / 2, y: 0.5 - sin(radians) / 2)
            let end = UnitPoint(x: 0.5 + cos(radians) / 2, y: 0.5 + sin(radians) / 2)
            return AnyShapeStyle(LinearGradient(stops: stops, startPoint: start, endPoint: end))
        case .radial:
            return AnyShapeStyle(RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: 80))
        }
    }

    private func drawCharacter(
        _ data: CharacterClipData,
        clip: Clip,
        in context: inout GraphicsContext,
        canvasSize: CGSize
    ) {
        guard let character = project.character(withID: data.characterID) else { return }
        guard character.tachieKind != .none else { return }
        let localTime = time - clip.startTime
        let shape = data.mouthShape(at: localTime)
        let mouthFrame = data.mouthAnimationFrameIndex(
            at: localTime,
            frameCount: character.mouthAnimationFrames.count,
            transitionDuration: 0.08 / character.defaultMouthSpeed
        )
        guard !data.visibleOnlyWhenSpeaking || shape != .closed else { return }
        let center = Self.canvasPoint(data.position, in: canvasSize)

        let effectiveExpressionID = data.expressionID ?? character.defaultExpressionID
        let selectedExpression = effectiveExpressionID.flatMap { id in
            character.expressions.first(where: { $0.id == id })
        }
        let animationBase = selectedExpression?.animationBaseImageFileName
            ?? character.animationBaseImageFileName
        let selectedImageName: String
        if character.tachieKind == .psd, let animationBase {
            selectedImageName = animationBase
        } else {
            selectedImageName = selectedExpression?.imageFileName ?? character.baseImageFileName
        }
        if let baseImage = imageProvider.image(named: selectedImageName) {
            drawImageCharacter(
                character: character,
                baseImage: baseImage,
                shape: shape,
                mouthFrame: mouthFrame,
                drawPartFrames: character.tachieKind != .psd || animationBase != nil,
                scale: data.scale,
                center: center,
                in: &context,
                canvasSize: canvasSize
            )
        } else {
            drawPlaceholderCharacter(
                character: character,
                shape: shape,
                scale: data.scale,
                center: center,
                in: &context,
                canvasSize: canvasSize
            )
        }
    }

    private static func canvasPoint(_ position: CodablePoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (position.x + 1) * 0.5 * size.width,
            y: (position.y + 1) * 0.5 * size.height
        )
    }

    /// Real art: base image plus, if the current mouth shape has one, a same-size overlay
    /// image drawn in the exact same rect (the standard layered-tachie-parts convention).
    private func drawImageCharacter(
        character: Character,
        baseImage: NSImage,
        shape: MouthShape,
        mouthFrame: Int,
        drawPartFrames: Bool,
        scale: Double,
        center: CGPoint,
        in context: inout GraphicsContext,
        canvasSize: CGSize
    ) {
        let naturalSize = baseImage.size
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        let targetHeight = canvasSize.height * 0.7 * scale
        let targetWidth = targetHeight * (naturalSize.width / naturalSize.height)
        let rect = CGRect(
            x: center.x - targetWidth / 2,
            y: center.y - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )

        context.draw(Image(nsImage: baseImage), in: rect)

        guard drawPartFrames else { return }

        if let mouthFileName = character.mouthAnimationFileName(at: mouthFrame)
            ?? character.mouthImageFileNames[shape],
           let mouthImage = imageProvider.image(named: mouthFileName) {
            context.draw(Image(nsImage: mouthImage), in: rect)
        }

        let eyeFrame = character.eyeAnimationFrameIndex(at: time)
        let eyeShape = character.eyeShape(at: time)
        if let eyeFileName = character.eyeAnimationFileName(at: eyeFrame)
            ?? character.eyeImageFileNames[eyeShape],
           let eyeImage = imageProvider.image(named: eyeFileName) {
            context.draw(Image(nsImage: eyeImage), in: rect)
        }
    }


    /// No art imported yet: a simple placeholder face whose mouth reacts to `shape`, so
    /// lip-sync timing can be verified before any character assets exist.
    private func drawPlaceholderCharacter(
        character: Character,
        shape: MouthShape,
        scale: Double,
        center: CGPoint,
        in context: inout GraphicsContext,
        canvasSize: CGSize
    ) {
        let faceRadius = min(canvasSize.width, canvasSize.height) * 0.12 * scale

        var facePath = Path()
        facePath.addEllipse(in: CGRect(x: center.x - faceRadius, y: center.y - faceRadius, width: faceRadius * 2, height: faceRadius * 2))
        context.fill(facePath, with: .color(.yellow.opacity(0.85)))
        context.stroke(facePath, with: .color(.black.opacity(0.6)), lineWidth: 2)

        for dx in [-0.4, 0.4] {
            var eye = Path()
            let eyeRadius = faceRadius * 0.08
            let eyeCenter = CGPoint(x: center.x + faceRadius * dx, y: center.y - faceRadius * 0.25)
            eye.addEllipse(in: CGRect(x: eyeCenter.x - eyeRadius, y: eyeCenter.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
            context.fill(eye, with: .color(.black))
        }

        let mouthWidth = faceRadius * 0.6
        let mouthHeight: CGFloat
        switch shape {
        case .closed: mouthHeight = faceRadius * 0.03
        case .small: mouthHeight = faceRadius * 0.18
        case .open: mouthHeight = faceRadius * 0.4
        }
        var mouth = Path()
        let mouthOrigin = CGPoint(x: center.x - mouthWidth / 2, y: center.y + faceRadius * 0.35 - mouthHeight / 2)
        mouth.addEllipse(in: CGRect(origin: mouthOrigin, size: CGSize(width: mouthWidth, height: mouthHeight)))
        context.fill(mouth, with: .color(.black.opacity(0.75)))

        let label = Text(character.name).font(.caption).foregroundColor(.white.opacity(0.8))
        context.draw(context.resolve(label), at: CGPoint(x: center.x, y: center.y + faceRadius + 12))
    }
}
