import Foundation
import Testing
@testable import VMSCore

@Test func clipContainsTime() {
    let clip = Clip(startTime: 1, duration: 2, content: .text(TextClipData(text: "hi")))
    #expect(!clip.contains(time: 0.5))
    #expect(clip.contains(time: 1))
    #expect(clip.contains(time: 2.9))
    #expect(!clip.contains(time: 3))
}

@Test func bulkClipMatcherKeepsCharacterVoiceAndSubtitleTogether() {
    let sourceID = UUID()
    let otherID = UUID()
    var audio = Clip(
        startTime: 1, duration: 2,
        content: .audio(AudioClipData(fileName: "a.wav", sourceText: "今日はテストです"))
    )
    let subtitle = Clip(
        startTime: 1, duration: 2,
        content: .text(TextClipData(text: "今日はテストです"))
    )
    if case .audio(var data) = audio.content {
        data.linkedSubtitleClipID = subtitle.id
        audio.content = .audio(data)
    }
    let character = Clip(
        startTime: 1, duration: 2,
        content: .character(CharacterClipData(characterID: sourceID, linkedAudioClipID: audio.id))
    )
    let otherAudio = Clip(
        startTime: 4, duration: 2,
        content: .audio(AudioClipData(fileName: "b.wav", sourceText: "今日はテストです"))
    )
    let unrelated = Clip(
        startTime: 4, duration: 2,
        content: .character(CharacterClipData(characterID: otherID, linkedAudioClipID: otherAudio.id))
    )
    let timeline = Timeline(tracks: [
        Track(name: "一括編集テスト", clips: [audio, subtitle, character, otherAudio, unrelated])
    ])

    let matched = BulkClipMatcher.matching(
        in: timeline, sourceCharacterID: sourceID, phrase: "テスト"
    )
    #expect(matched.clipIDs == [audio.id, subtitle.id, character.id])
    #expect(matched.audioClipIDs == [audio.id])
    #expect(matched.subtitleClipIDs == [subtitle.id])
    #expect(matched.characterClipIDs == [character.id])
    #expect(!matched.clipIDs.contains(otherAudio.id))
    #expect(BulkClipMatcher.matching(
        in: timeline, sourceCharacterID: sourceID, phrase: "対象外"
    ).clipIDs.isEmpty)
}

@Test func characterBlinkSettingsPreserveOldProjectsAndRenderTiming() throws {
    let legacy = Data(#"{"name":"テスト","baseImageFileName":"body.png"}"#.utf8)
    var character = try JSONDecoder().decode(Character.self, from: legacy)
    #expect(character.eyeShape(at: 0) == .open)
    #expect(character.eyeShape(at: 3.1) == .closed)
    character.blinkInterval = 2
    character.blinkDuration = 0.2
    let restored = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(character))
    #expect(restored.eyeShape(at: 1.7) == .open)
    #expect(restored.eyeShape(at: 1.9) == .closed)
    #expect(restored.eyeShape(at: 2) == .open)
    character.blinkEnabled = false
    #expect(character.eyeShape(at: 1.9) == .open)
    character.blinkEnabled = true
    character.blinkInterval = .nan
    #expect(character.eyeShape(at: .infinity) == .open)
}

@Test func tachieLayerSourceOrderPreservesLegacyProjects() throws {
    let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"口","isVisible":true,"isFolder":false,"children":[],"imageFileName":"mouth.png"}"#.utf8)
    let layer = try JSONDecoder().decode(TachieLayerNode.self, from: legacy)
    #expect(layer.sourceOrder == nil)
    var imported = layer
    imported.sourceOrder = 3
    #expect(try JSONDecoder().decode(TachieLayerNode.self, from: JSONEncoder().encode(imported)) == imported)
}

@Test func characterClipMouthShapeUsesLatestKeyframe() {
    let data = CharacterClipData(
        characterID: UUID(),
        mouthKeyframes: [
            MouthKeyframe(time: 0, shape: .closed),
            MouthKeyframe(time: 0.5, shape: .open),
            MouthKeyframe(time: 1.0, shape: .small)
        ]
    )
    #expect(data.mouthShape(at: 0.2) == .closed)
    #expect(data.mouthShape(at: 0.5) == .open)
    #expect(data.mouthShape(at: 0.9) == .open)
    #expect(data.mouthShape(at: 1.5) == .small)
}

@Test func variableMouthFramesUseIntermediateImagesAndRoundTripPSDLayer() throws {
    let layerID = UUID()
    let frames = (0..<5).map { index in
        CharacterPartFrame(
            name: "口\(index)", imageFileName: "mouth-\(index).png",
            sourceLayerID: index == 2 ? layerID : nil
        )
    }
    let character = Character(name: "可変口", baseImageFileName: "base.png", mouthAnimationFrames: frames)
    let restored = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(character))
    #expect(restored.mouthAnimationFrames.count == 5)
    #expect(restored.mouthAnimationFrames[2].sourceLayerID == layerID)
    #expect(restored.mouthImageFileNames[.closed] == "mouth-0.png")
    #expect(restored.mouthImageFileNames[.small] == "mouth-2.png")
    #expect(restored.mouthImageFileNames[.open] == "mouth-4.png")

    let data = CharacterClipData(
        characterID: character.id,
        mouthKeyframes: [MouthKeyframe(time: 1, shape: .open)]
    )
    #expect(data.mouthAnimationFrameIndex(at: 1, frameCount: 5, transitionDuration: 0.1) == 0)
    #expect(data.mouthAnimationFrameIndex(at: 1.05, frameCount: 5, transitionDuration: 0.1) == 2)
    #expect(data.mouthAnimationFrameIndex(at: 1.1, frameCount: 5, transitionDuration: 0.1) == 4)
}

@Test func variableEyeFramesTravelClosedAndBackOpen() {
    let frames = (0..<5).map { CharacterPartFrame(name: "目\($0)", imageFileName: "eye-\($0).png") }
    var character = Character(name: "可変目", baseImageFileName: "base.png", eyeAnimationFrames: frames)
    character.blinkInterval = 2
    character.blinkDuration = 0.2
    #expect(character.eyeAnimationFrameIndex(at: 1.8) == 0)
    #expect(character.eyeAnimationFrameIndex(at: 1.85) == 2)
    #expect(character.eyeAnimationFrameIndex(at: 1.9) == 4)
    #expect(character.eyeAnimationFrameIndex(at: 1.95) == 2)
    #expect(character.eyeAnimationFrameIndex(at: 2.0) == 0)
}

@Test func psdDefaultAnimationDetectsSmoothMouthAndCompoundEyes() throws {
    let mouthNames = ["*んー", "*んへー", "*んあー", "*ほあ", "*ほあー"]
    let mouthLayers = mouthNames.map { TachieLayerNode(name: $0, isVisible: false, imageFileName: "\($0).png") }
    let mouthFolder = TachieLayerNode(name: "!口", isFolder: true, children: mouthLayers)

    let iris = TachieLayerNode(name: "*普通目", imageFileName: "iris.png")
    let pupilFolder = TachieLayerNode(name: "!黒目", isFolder: true, children: [iris])
    let white = TachieLayerNode(name: "*普通白目", imageFileName: "white.png")
    let eyeSet = TachieLayerNode(name: "*目セット", isFolder: true, children: [pupilFolder, white])
    let half = TachieLayerNode(name: "*細め目", isVisible: false, imageFileName: "half.png")
    let closed = TachieLayerNode(name: "*にっこり", isVisible: false, imageFileName: "closed.png")
    let eyeFolder = TachieLayerNode(name: "!目", isFolder: true, children: [eyeSet, half, closed])

    let suggestion = PSDCharacterAnimationDefaultDetector.detect(in: [mouthFolder, eyeFolder])
    #expect(suggestion.mouthFrames.count == 5)
    #expect(suggestion.mouthFrames.map(\.sourceLayerIDs) == mouthLayers.map { [$0.id] })
    #expect(suggestion.eyeFrames.count == 3)
    #expect(suggestion.eyeFrames[0].sourceLayerIDs == [white.id, iris.id])
    #expect(suggestion.eyeFrames[1].sourceLayerIDs == [half.id])
    #expect(suggestion.eyeFrames[2].sourceLayerIDs == [closed.id])

    let character = Character(
        name: "複合目", tachieKind: .psd, baseImageFileName: "base.png",
        layerTree: [mouthFolder, eyeFolder],
        mouthAnimationFrames: suggestion.mouthFrames.map {
            CharacterPartFrame(name: $0.name, sourceLayerIDs: $0.sourceLayerIDs)
        },
        eyeAnimationFrames: suggestion.eyeFrames.map {
            CharacterPartFrame(name: $0.name, sourceLayerIDs: $0.sourceLayerIDs)
        }
    )
    #expect(CharacterPartLayerResolver.exclusionLayerIDs(for: character) == [mouthFolder.id, eyeFolder.id])
    let restored = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(character))
    #expect(restored.eyeAnimationFrames[0].sourceLayerIDs == [white.id, iris.id])
}

@Test func oldCharacterJSONMigratesFixedImagesToEditableFrames() throws {
    let source = Character(
        name: "旧キャラ", baseImageFileName: "base.png",
        mouthImageFileNames: [.closed: "c.png", .small: "s.png", .open: "o.png"],
        eyeImageFileNames: [.open: "eo.png", .closed: "ec.png"]
    )
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
    json.removeValue(forKey: "mouthAnimationFrames")
    json.removeValue(forKey: "eyeAnimationFrames")
    let character = try JSONDecoder().decode(Character.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(character.mouthAnimationFrames.map(\.imageFileName) == ["c.png", "s.png", "o.png"])
    #expect(character.eyeAnimationFrames.map(\.imageFileName) == ["eo.png", "ec.png"])
}

@Test func psdAnimationFramesReconnectAndExcludeWholeMouthAndEyeCategories() throws {
    let mouthClosed = TachieLayerNode(name: "*んー", isVisible: false, imageFileName: "mouth-closed.png")
    let mouthOpen = TachieLayerNode(name: "*わあー", imageFileName: "mouth-open.png")
    let mouthFolder = TachieLayerNode(
        name: "!口", isFolder: true, children: [mouthClosed, mouthOpen]
    )
    let eyeOpen = TachieLayerNode(name: "*目セット", imageFileName: "eye-open.png")
    let eyeClosed = TachieLayerNode(name: "*目閉じ", isVisible: false, imageFileName: "eye-closed.png")
    let eyeFolder = TachieLayerNode(
        name: "!目", isFolder: true, children: [eyeOpen, eyeClosed]
    )
    let body = TachieLayerNode(name: "体", imageFileName: "body.png")
    let character = Character(
        name: "PSDキャラクター", tachieKind: .psd, baseImageFileName: "base.png",
        layerTree: [mouthFolder, eyeFolder, body],
        mouthAnimationFrames: [
            CharacterPartFrame(name: "通常", imageFileName: mouthClosed.imageFileName),
            CharacterPartFrame(name: "開", imageFileName: mouthOpen.imageFileName)
        ],
        eyeAnimationFrames: [
            CharacterPartFrame(name: "開", imageFileName: eyeOpen.imageFileName),
            CharacterPartFrame(name: "閉", imageFileName: eyeClosed.imageFileName)
        ]
    )

    // Encoding without source IDs models projects created before PSD layer links were saved.
    var restored = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(character))
    #expect(restored.mouthAnimationFrames[0].sourceLayerID == mouthClosed.id)
    #expect(restored.mouthAnimationFrames[1].sourceLayerID == mouthOpen.id)
    #expect(restored.eyeAnimationFrames[0].sourceLayerID == eyeOpen.id)
    #expect(restored.eyeAnimationFrames[1].sourceLayerID == eyeClosed.id)
    #expect(CharacterPartLayerResolver.exclusionLayerIDs(for: restored) == [mouthFolder.id, eyeFolder.id])

    restored.animationBaseImageFileName = "neutral.png"
    let roundTrip = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(restored))
    #expect(roundTrip.animationBaseImageFileName == "neutral.png")
}

@Test func legacyExpressionDecodesWithoutAnimationBase() throws {
    let expression = try JSONDecoder().decode(
        CharacterExpression.self,
        from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"通常","imageFileName":"face.png"}"#.utf8)
    )
    #expect(expression.animationBaseImageFileName == nil)
}

@Test func lipSyncGeneratorClosesMouthBetweenMorae() {
    let timings = [
        MoraTiming(text: "コ", startTime: 0.0, duration: 0.2, isPause: false, vowel: "o"),
        MoraTiming(text: "ン", startTime: 0.2, duration: 0.1, isPause: true, vowel: nil)
    ]
    let keyframes = LipSyncGenerator.keyframes(from: timings)
    #expect(keyframes.first?.shape == .open)
    #expect(keyframes.contains { $0.time == 0.2 && $0.shape == .closed })
}

@Test func fasterCharacterLipSyncClosesMouthSooner() {
    let timings = [MoraTiming(text: "コ", startTime: 1.0, duration: 0.4, isPause: false, vowel: "o")]
    let normal = LipSyncGenerator.keyframes(from: timings, speed: 1.0)
    let fast = LipSyncGenerator.keyframes(from: timings, speed: 2.0)
    #expect(normal.last?.time == 1.4)
    #expect(fast.last?.time == 1.2)
}

@Test func audioQueryMoraTimingsAccountForPrePhonemeLength() {
    let json = """
    {
        "accent_phrases": [
            {
                "moras": [
                    {"text": "コ", "consonant": "k", "consonant_length": 0.1, "vowel": "o", "vowel_length": 0.15, "pitch": 5.0}
                ],
                "accent": 1
            }
        ],
        "speedScale": 1.0,
        "pitchScale": 0.0,
        "intonationScale": 1.0,
        "volumeScale": 1.0,
        "prePhonemeLength": 0.1,
        "postPhonemeLength": 0.1,
        "outputSamplingRate": 24000,
        "outputStereo": false
    }
    """.data(using: .utf8)!

    let query = try! JSONDecoder().decode(VoiceVoxAudioQuery.self, from: json)

    let timings = query.moraTimings()
    #expect(timings.count == 1)
    #expect(timings[0].startTime == 0.1)
    #expect(query.totalDuration() == 0.1 + 0.25 + 0.1)
}

@Test func audioQueryEncodesMixedCaseKeysExactlyLikeVoicevoxExpects() throws {
    // VOICEVOX's /synthesis endpoint rejects the request with HTTP 422 if these
    // top-level fields aren't camelCase (while accent_phrases stays snake_case) — this
    // pins that exact shape so it can't silently regress back to a blanket
    // convertToSnakeCase strategy.
    let mora = VoiceVoxMora(text: "コ", consonant: "k", consonantLength: 0.1, vowel: "o", vowelLength: 0.15, pitch: 5)
    let phrase = VoiceVoxAccentPhrase(moras: [mora], accent: 1, pauseMora: nil, isInterrogative: nil)
    let query = VoiceVoxAudioQuery(
        accentPhrases: [phrase],
        speedScale: 1, pitchScale: 0, intonationScale: 1, volumeScale: 1,
        prePhonemeLength: 0.1, postPhonemeLength: 0.1,
        outputSamplingRate: 24000, outputStereo: false, kana: nil
    )

    let data = try JSONEncoder().encode(query)
    let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(object["speedScale"] != nil)
    #expect(object["prePhonemeLength"] != nil)
    #expect(object["outputSamplingRate"] != nil)
    #expect(object["accent_phrases"] != nil)
    #expect(object["speed_scale"] == nil)
    #expect(object["accentPhrases"] == nil)

    let phrases = object["accent_phrases"] as! [[String: Any]]
    let moras = phrases[0]["moras"] as! [[String: Any]]
    #expect(moras[0]["consonant_length"] != nil)
    #expect(moras[0]["consonantLength"] == nil)
}

@Test func projectPackageRoundTrips() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sourceAssets = tempRoot.appendingPathComponent("SourceAssets")
    try fileManager.createDirectory(at: sourceAssets, withIntermediateDirectories: true)
    let assetFile = sourceAssets.appendingPathComponent("voice_1.wav")
    try Data([0x01, 0x02, 0x03]).write(to: assetFile)

    let project = Project.demo()
    let packageURL = tempRoot.appendingPathComponent("MyProject.\(ProjectPackage.fileExtension)")

    try ProjectPackage.write(project: project, assetsDirectory: sourceAssets, to: packageURL)
    let (loadedProject, loadedAssetsDirectory) = try ProjectPackage.read(from: packageURL)

    #expect(loadedProject.id == project.id)
    #expect(loadedProject.scenes[0].timeline.tracks.count == project.scenes[0].timeline.tracks.count)
    #expect(fileManager.fileExists(atPath: loadedAssetsDirectory.appendingPathComponent("voice_1.wav").path))

    try? fileManager.removeItem(at: tempRoot)
}

@Test func fadeMultiplierRampsInAndOut() {
    let effects = ClipEffects(fadeInDuration: 1, fadeOutDuration: 1)
    #expect(effects.fadeMultiplier(localTime: 0, duration: 4) == 0)
    #expect(effects.fadeMultiplier(localTime: 0.5, duration: 4) == 0.5)
    #expect(effects.fadeMultiplier(localTime: 2, duration: 4) == 1)
    #expect(effects.fadeMultiplier(localTime: 3.5, duration: 4) == 0.5)
    #expect(effects.fadeMultiplier(localTime: 4, duration: 4) == 0)
}

@Test func fadeMultiplierDefaultsToFullyOpaqueWithoutFades() {
    let effects = ClipEffects()
    #expect(effects.fadeMultiplier(localTime: 0, duration: 4) == 1)
    #expect(effects.fadeMultiplier(localTime: 4, duration: 4) == 1)
}

@Test func defaultLayerStackUsesGenericNames() {
    let tracks = Timeline.defaultLayerStack(count: 30)
    #expect(tracks.count == 30)
    #expect(tracks[0].name == "レイヤー1")
    #expect(tracks[1].name == "レイヤー2")
    #expect(tracks[2].name == "レイヤー3")
    #expect(tracks[3].name == "レイヤー4")
    #expect(tracks[29].name == "レイヤー30")
}

@Test func projectAlwaysHasAtLeastOneScene() {
    let project = Project(name: "空プロジェクト", scenes: [])
    #expect(project.scenes.count == 1)
    #expect(project.scenes[0].name == "メイン")
}

@Test func demoProjectHasSingleMainScene() {
    let project = Project.demo()
    #expect(project.scenes.count == 1)
    #expect(project.scenes[0].name == "メイン")
    #expect(project.scenes[0].timeline.tracks.count == 30)
}

@Test func effectKindTemplateProducesImplementedFlag() {
    #expect(EffectKindTemplate.blur.displayName == "ぼかし")
    #expect(EffectKind.defaultInstance(for: .blur).isImplemented)
    #expect(EffectKind.defaultInstance(for: .mosaic).isImplemented)
}

@Test func gradientEffectSortsStopsByPosition() {
    let gradient = GradientEffect(stops: [
        GradientColorStop(position: 1, color: .white),
        GradientColorStop(position: 0, color: .black)
    ])
    #expect(gradient.stops.map(\.position) == [0, 1])
}

@Test func characterDefaultsToAnimatedTachieAndRoundTripsBlinkImages() throws {
    let defaultExpression = CharacterExpression(name: "笑顔", imageFileName: "smile.png")
    let character = Character(
        name: "テスト",
        baseImageFileName: "base.png",
        mouthImageFileNames: [.open: "mouth-open.png"],
        eyeImageFileNames: [.open: "eye-open.png", .closed: "eye-closed.png"],
        expressions: [defaultExpression],
        defaultExpressionID: defaultExpression.id
    )
    #expect(character.tachieKind == .animated)
    #expect(character.tachieKind.isImplemented)
    #expect(!character.layerTree.isEmpty)
    let decoded = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(character))
    #expect(decoded.eyeImageFileNames[.closed] == "eye-closed.png")
    #expect(decoded.expressions.first?.name == "笑顔")
    #expect(decoded.defaultExpressionID == defaultExpression.id)
}

@Test func characterClipExpressionRoundTrips() throws {
    let expressionID = UUID()
    let value = CharacterClipData(characterID: UUID(), expressionID: expressionID)
    let decoded = try JSONDecoder().decode(CharacterClipData.self, from: JSONEncoder().encode(value))
    #expect(decoded.expressionID == expressionID)
}

@Test func codableRoundTripsNewClipEffectsFields() throws {
    var effects = ClipEffects(blendMode: .add, flipHorizontal: true, useZOrder: true, zPosition: 3, clipToAbove: true, notes: "メモ")
    effects.effectsList = [Effect(kind: .blur(radius: 5)), Effect(isEnabled: false, kind: .outline(TextOutlineEffect()))]

    let data = try JSONEncoder().encode(effects)
    let decoded = try JSONDecoder().decode(ClipEffects.self, from: data)

    #expect(decoded.blendMode == .add)
    #expect(decoded.flipHorizontal)
    #expect(decoded.zPosition == 3)
    #expect(decoded.effectsList.count == 2)
    #expect(decoded.effectsList[1].isEnabled == false)
}

@Test func remoteAIAnalysisRoundTripsInsideProject() throws {
    let assetID = UUID()
    let analysis = RemoteAIAnalysis(
        assetID: assetID,
        transcript: [TranscriptSegment(start: 1.2, end: 3.4, text: "重要な発言")],
        highlights: [HighlightCandidate(start: 1.2, end: 3.4, title: "結論", reason: "要点", score: 0.9)],
        summary: "要約"
    )
    let project = Project(name: "AI解析", aiAnalyses: [analysis])
    let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
    #expect(decoded.aiAnalyses == [analysis])
    #expect(decoded.aiAnalyses[0].transcript[0].text == "重要な発言")
}

@Test func oldProjectWithoutAIAnalysesStillDecodes() throws {
    let project = Project(name: "旧形式")
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String: Any]
    object.removeValue(forKey: "aiAnalyses")
    let decoded = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.aiAnalyses.isEmpty)
}
