import Foundation

public enum ScenarioPlacementSuggestion: String, Codable, CaseIterable, Hashable, Sendable {
    case inherit
    case left
    case right
    case center

    public var displayName: String {
        switch self {
        case .inherit: "前のコマを継承"
        case .left: "左"
        case .right: "右"
        case .center: "中央"
        }
    }
}

public struct ScenarioDraftLine: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var sourceLine: Int
    public var speakerID: UUID?
    public var unresolvedSpeakerName: String?
    public var dialogue: String
    public var durationSeconds: Double
    public var placement: ScenarioPlacementSuggestion
    public var recommendationReason: String?

    public init(
        id: UUID = UUID(),
        sourceLine: Int,
        speakerID: UUID? = nil,
        unresolvedSpeakerName: String? = nil,
        dialogue: String,
        durationSeconds: Double = 3,
        placement: ScenarioPlacementSuggestion = .inherit,
        recommendationReason: String? = nil
    ) {
        self.id = id
        self.sourceLine = sourceLine
        self.speakerID = speakerID
        self.unresolvedSpeakerName = unresolvedSpeakerName
        self.dialogue = dialogue
        self.durationSeconds = durationSeconds
        self.placement = placement
        self.recommendationReason = recommendationReason
    }

    public var needsSpeakerResolution: Bool {
        unresolvedSpeakerName?.isEmpty == false
    }

    public func storyboardCard(frameRate: Double) -> StoryboardCard {
        let safeFPS = frameRate.isFinite && (1...240).contains(frameRate) ? frameRate : 30
        let safeDuration = durationSeconds.isFinite ? min(600, max(1 / safeFPS, durationSeconds)) : 3
        var card = StoryboardCard(
            speakerID: speakerID,
            dialogue: dialogue,
            durationFrames: max(1, Int((safeDuration * safeFPS).rounded()))
        )
        if let speakerID, placement != .inherit {
            var value = StoryboardPlacement()
            switch placement {
            case .inherit: break
            case .left:
                value.position = CodablePoint(x: -0.8, y: 0.88)
                value.scale = 1.4
            case .right:
                value.position = CodablePoint(x: 0.8, y: 0.88)
                value.scale = 1.4
            case .center:
                value.position = CodablePoint(x: 0, y: 0.2)
                value.scale = 1
            }
            card.placements[speakerID] = value
        }
        return card
    }
}

public enum ScenarioDocumentFormat: String, Sendable {
    case text
    case csv
    case json

    public static func infer(fileExtension: String) -> ScenarioDocumentFormat {
        switch fileExtension.lowercased() {
        case "csv", "tsv": .csv
        case "json": .json
        default: .text
        }
    }
}

public enum ScenarioDocumentError: Error, LocalizedError {
    case unreadable
    case invalidFormat
    case noDialogue
    case tooManyLines

    public var errorDescription: String? {
        switch self {
        case .unreadable: "シナリオを文字データとして読み取れませんでした。UTF-8またはShift-JISで保存してください。"
        case .invalidFormat: "シナリオの形式を確認してください。TXT、CSV、JSONに対応しています。"
        case .noDialogue: "読み込めるセリフがありません。"
        case .tooManyLines: "一度に読み込めるセリフは300件までです。"
        }
    }
}

public enum ScenarioDocumentParser {
    public static func parse(
        data: Data,
        format: ScenarioDocumentFormat,
        characters: [Character],
        defaultSpeaker: UUID?,
        defaultDuration: Double = 3
    ) throws -> [ScenarioDraftLine] {
        switch format {
        case .json:
            return try parseJSON(data, characters: characters, defaultSpeaker: defaultSpeaker, defaultDuration: defaultDuration)
        case .text, .csv:
            guard let text = decodeText(data) else { throw ScenarioDocumentError.unreadable }
            if format == .csv {
                return try parseCSV(text, characters: characters, defaultSpeaker: defaultSpeaker, defaultDuration: defaultDuration)
            }
            return try parseText(text, characters: characters, defaultSpeaker: defaultSpeaker, defaultDuration: defaultDuration)
        }
    }

    public static func parseText(
        _ text: String,
        characters: [Character],
        defaultSpeaker: UUID?,
        defaultDuration: Double = 3
    ) throws -> [ScenarioDraftLine] {
        guard text.count <= 200_000 else { throw ScenarioDocumentError.invalidFormat }
        var result: [ScenarioDraftLine] = []
        for (offset, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            var speakerName: String?
            var dialogue = line
            if let tab = line.firstIndex(of: "\t") {
                speakerName = cleaned(String(line[..<tab]))
                dialogue = cleaned(String(line[line.index(after: tab)...])) ?? ""
            } else if let separator = line.firstIndex(where: { $0 == "：" || $0 == ":" }) {
                speakerName = cleaned(String(line[..<separator]))
                dialogue = cleaned(String(line[line.index(after: separator)...])) ?? ""
            }
            guard !dialogue.isEmpty else { continue }
            result.append(makeLine(
                sourceLine: offset + 1, speakerName: speakerName, dialogue: dialogue,
                explicitDuration: nil, characters: characters, defaultSpeaker: defaultSpeaker,
                defaultDuration: defaultDuration
            ))
        }
        return try validated(result)
    }

    private static func parseCSV(
        _ text: String,
        characters: [Character],
        defaultSpeaker: UUID?,
        defaultDuration: Double
    ) throws -> [ScenarioDraftLine] {
        let rows = csvRows(text).filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard let first = rows.first else { throw ScenarioDocumentError.noDialogue }
        let normalized = first.map(normalizeHeader)
        let speakerAliases = ["speaker", "character", "name", "話者", "キャラクター", "名前"]
        let dialogueAliases = ["dialogue", "text", "line", "speech", "セリフ", "台詞", "本文"]
        let durationAliases = ["duration", "seconds", "length", "長さ", "秒"]
        let speakerColumn = normalized.firstIndex { speakerAliases.contains($0) }
        let dialogueColumn = normalized.firstIndex { dialogueAliases.contains($0) }
        let durationColumn = normalized.firstIndex { durationAliases.contains($0) }
        let hasHeader = dialogueColumn != nil || speakerColumn != nil || durationColumn != nil
        let body = hasHeader ? Array(rows.dropFirst()) : rows
        var result: [ScenarioDraftLine] = []
        for (offset, row) in body.enumerated() {
            let lineNumber = offset + (hasHeader ? 2 : 1)
            let dialogueIndex = dialogueColumn ?? (row.count >= 2 ? 1 : 0)
            guard row.indices.contains(dialogueIndex), let dialogue = cleaned(row[dialogueIndex]) else { continue }
            let inferredSpeakerIndex: Int? = speakerColumn ?? (row.count >= 2 ? 0 : nil)
            let speakerName = inferredSpeakerIndex.flatMap { row.indices.contains($0) ? cleaned(row[$0]) : nil }
            let explicitDuration = durationColumn.flatMap { row.indices.contains($0) ? Double(row[$0].trimmingCharacters(in: .whitespaces)) : nil }
            result.append(makeLine(
                sourceLine: lineNumber, speakerName: speakerName, dialogue: dialogue,
                explicitDuration: explicitDuration, characters: characters, defaultSpeaker: defaultSpeaker,
                defaultDuration: defaultDuration
            ))
        }
        return try validated(result)
    }

    private static func parseJSON(
        _ data: Data,
        characters: [Character],
        defaultSpeaker: UUID?,
        defaultDuration: Double
    ) throws -> [ScenarioDraftLine] {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw ScenarioDocumentError.invalidFormat }
        let values: [[String: Any]]
        if let array = object as? [[String: Any]] {
            values = array
        } else if let dictionary = object as? [String: Any],
                  let array = (dictionary["lines"] ?? dictionary["dialogues"] ?? dictionary["セリフ"]) as? [[String: Any]] {
            values = array
        } else {
            throw ScenarioDocumentError.invalidFormat
        }
        let speakerKeys = ["speaker", "character", "name", "話者", "キャラクター", "名前"]
        let dialogueKeys = ["dialogue", "text", "line", "speech", "セリフ", "台詞", "本文"]
        let durationKeys = ["duration", "seconds", "length", "長さ", "秒"]
        var result: [ScenarioDraftLine] = []
        for (offset, value) in values.enumerated() {
            guard let dialogue = firstString(in: value, keys: dialogueKeys) else { continue }
            let speaker = firstString(in: value, keys: speakerKeys)
            let duration = firstNumber(in: value, keys: durationKeys)
            result.append(makeLine(
                sourceLine: offset + 1, speakerName: speaker, dialogue: dialogue,
                explicitDuration: duration, characters: characters, defaultSpeaker: defaultSpeaker,
                defaultDuration: defaultDuration
            ))
        }
        return try validated(result)
    }

    private static func makeLine(
        sourceLine: Int,
        speakerName: String?,
        dialogue: String,
        explicitDuration: Double?,
        characters: [Character],
        defaultSpeaker: UUID?,
        defaultDuration: Double
    ) -> ScenarioDraftLine {
        let matches = speakerName.map { name in characters.filter { $0.name == name } } ?? []
        let exact = matches.count == 1 ? matches[0].id : nil
        let unresolved = speakerName != nil && exact == nil ? speakerName : nil
        let duration = explicitDuration.flatMap { $0.isFinite && $0 > 0 ? min(600, $0) : nil }
            ?? min(600, max(0.2, defaultDuration))
        return ScenarioDraftLine(
            sourceLine: sourceLine,
            speakerID: exact ?? (speakerName == nil ? defaultSpeaker : nil),
            unresolvedSpeakerName: unresolved,
            dialogue: dialogue,
            durationSeconds: duration
        )
    }

    private static func validated(_ lines: [ScenarioDraftLine]) throws -> [ScenarioDraftLine] {
        guard !lines.isEmpty else { throw ScenarioDocumentError.noDialogue }
        guard lines.count <= 300 else { throw ScenarioDocumentError.tooManyLines }
        return lines
    }

    private static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .utf16)
    }

    private static func cleaned(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func firstString(in value: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = value[key] as? String, let result = cleaned(string) { return result }
        }
        return nil
    }

    private static func firstNumber(in value: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = value[key] as? NSNumber { return number.doubleValue }
            if let string = value[key] as? String, let number = Double(string) { return number }
        }
        return nil
    }

    private static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if (character == "," || character == "\t"), !quoted {
                row.append(field); field = ""
            } else if (character == "\n" || character == "\r"), !quoted {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" { index = next }
                }
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

public struct ScenarioAIPlanSuggestion: Codable, Hashable, Sendable {
    public var lineIndex: Int
    public var speakerName: String?
    public var durationSeconds: Double
    public var placement: ScenarioPlacementSuggestion
    public var reason: String

    public init(lineIndex: Int, speakerName: String?, durationSeconds: Double, placement: ScenarioPlacementSuggestion, reason: String) {
        self.lineIndex = lineIndex
        self.speakerName = speakerName
        self.durationSeconds = durationSeconds
        self.placement = placement
        self.reason = reason
    }
}

public struct ScenarioAIPlan: Codable, Hashable, Sendable {
    public var summary: String
    public var suggestions: [ScenarioAIPlanSuggestion]

    public init(summary: String, suggestions: [ScenarioAIPlanSuggestion]) {
        self.summary = summary
        self.suggestions = suggestions
    }
}
