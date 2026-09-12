import AppKit
import Foundation

/// A focused PSD reader for character artwork. It supports 8-bit RGB PSD files and
/// raw/PackBits-compressed layer channels. Unsupported adjustment/effect records are
/// safely skipped while the original PSD remains untouched.
enum PSDLayerExtractor {
    struct ExtractedLayer {
        let name: String
        let fileName: String?
        let isVisible: Bool
        let children: [ExtractedLayer]
        var isFolder: Bool { !children.isEmpty || fileName == nil }
    }

    private struct Channel { let id: Int16; let length: Int }
    private struct Record {
        let name: String
        let top: Int
        let left: Int
        let bottom: Int
        let right: Int
        let opacity: UInt8
        let visible: Bool
        let channels: [Channel]
        let sectionType: Int
    }

    static func extract(from url: URL, into directory: URL) throws -> [ExtractedLayer] {
        var reader = Reader(data: try Data(contentsOf: url))
        guard try reader.ascii(4) == "8BPS", try reader.u16() == 1 else { throw failure("PSD形式を確認できません。") }
        try reader.skip(6)
        let channelCount = try reader.u16()
        let height = Int(try reader.u32()), width = Int(try reader.u32())
        let depth = try reader.u16(), colorMode = try reader.u16()
        guard channelCount >= 3, depth == 8, colorMode == 3 else { throw failure("8ビットRGBのPSDに対応しています。") }
        try reader.skipSection32() // color mode
        try reader.skipSection32() // image resources
        let maskLength = Int(try reader.u32())
        let maskEnd = reader.offset + maskLength
        guard reader.offset + 4 <= maskEnd else { return [] }
        let layerInfoLength = Int(try reader.u32())
        let layerInfoEnd = min(maskEnd, reader.offset + layerInfoLength)
        guard layerInfoLength > 2 else { return [] }
        let signedCount = try reader.i16()
        let count = abs(Int(signedCount))
        var records: [Record] = []
        records.reserveCapacity(count)
        for _ in 0..<count {
            let top = Int(try reader.i32()), left = Int(try reader.i32())
            let bottom = Int(try reader.i32()), right = Int(try reader.i32())
            let recordChannelCount = Int(try reader.u16())
            let channels = try (0..<recordChannelCount).map { _ in
                Channel(id: try reader.i16(), length: Int(try reader.u32()))
            }
            try reader.skip(8) // blend signature + key
            let opacity = try reader.u8()
            try reader.skip(1) // clipping
            let flags = try reader.u8()
            try reader.skip(1)
            let extraLength = Int(try reader.u32())
            let extraEnd = reader.offset + extraLength
            try reader.skipSection32() // mask
            try reader.skipSection32() // blending ranges
            var name = try reader.pascalPadded4()
            var sectionType = 0
            while reader.offset + 12 <= extraEnd {
                let signature = try reader.ascii(4)
                let key = try reader.ascii(4)
                let length = Int(try reader.u32())
                let blockEnd = min(extraEnd, reader.offset + length)
                if (signature == "8BIM" || signature == "8B64"), key == "luni", length >= 4 {
                    let scalarCount = Int(try reader.u32())
                    name = try reader.utf16BE(count: min(scalarCount, (blockEnd - reader.offset) / 2))
                }
                // `lsdk` is the nested-group variant used by many character PSDs.
                // Treat it exactly like the older `lsct` section-divider record.
                if (signature == "8BIM" || signature == "8B64"),
                   (key == "lsct" || key == "lsdk"), length >= 4 {
                    sectionType = Int(try reader.u32())
                }
                // Additional layer information inside a layer record is padded to an
                // even byte count. Four-byte padding skips the next tag whenever a
                // Japanese Unicode layer name occupies 2 (mod 4) bytes, which is why
                // only some folder markers were discovered.
                let padding = (2 - (length % 2)) % 2
                reader.offset = min(extraEnd, blockEnd + padding)
            }
            reader.offset = extraEnd
            records.append(Record(name: name.isEmpty ? "名称なし" : name, top: top, left: left, bottom: bottom, right: right, opacity: opacity, visible: flags & 0x02 == 0, channels: channels, sectionType: sectionType))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var rendered: [Int: ExtractedLayer] = [:]
        for (index, record) in records.enumerated() {
            let layerWidth = max(0, record.right - record.left), layerHeight = max(0, record.bottom - record.top)
            var planes: [Int16: [UInt8]] = [:]
            for channel in record.channels {
                let start = reader.offset
                if layerWidth > 0, layerHeight > 0, channel.id == -1 || channel.id == 0 || channel.id == 1 || channel.id == 2 {
                    planes[channel.id] = try decodeChannel(reader: &reader, width: layerWidth, height: layerHeight)
                }
                reader.offset = min(layerInfoEnd, start + channel.length)
            }
            guard layerWidth > 0, layerHeight > 0,
                  let png = makePNG(documentWidth: width, documentHeight: height, record: record, planes: planes) else { continue }
            let fileName = "psd_layer_\(index)_\(UUID().uuidString).png"
            try png.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            rendered[index] = ExtractedLayer(name: record.name, fileName: fileName, isVisible: record.visible, children: [])
        }
        // Layer records run from the visual top toward the bottom, while a PSD group is
        // encoded as: hidden bounding divider, children, folder record. Build with a
        // stack but retain each sibling array's native top-to-bottom order.
        var stack: [[ExtractedLayer]] = [[]]
        for (index, record) in records.enumerated() {
            if record.sectionType == 3 {
                stack.append([])
            } else if record.sectionType == 1 || record.sectionType == 2 {
                if stack.count > 1 {
                    let children = stack.removeLast()
                    stack[stack.count - 1].append(ExtractedLayer(
                        name: record.name, fileName: nil, isVisible: record.visible,
                        children: children))
                }
            } else if let layer = rendered[index] {
                stack[stack.count - 1].append(layer)
            }
        }
        while stack.count > 1 {
            // Preserve readable content if a damaged PSD leaves a group unclosed.
            stack[stack.count - 2].append(contentsOf: stack.removeLast())
        }
        // The PSD record list is bottom-to-top. Store the tree in the order users see in
        // an editor: topmost first. The reviewer and its move buttons therefore use the
        // ordinary convention (index 0 = front/top), while composition draws in reverse.
        func topToBottom(_ nodes: [ExtractedLayer]) -> [ExtractedLayer] {
            nodes.reversed().map { node in
                ExtractedLayer(name: node.name, fileName: node.fileName,
                               isVisible: node.isVisible,
                               children: topToBottom(node.children))
            }
        }
        return topToBottom(stack[0])
    }

    private static func decodeChannel(reader: inout Reader, width: Int, height: Int) throws -> [UInt8] {
        let compression = try reader.u16()
        if compression == 0 { return try reader.bytes(width * height) }
        guard compression == 1 else { throw failure("このPSDのレイヤー圧縮方式にはまだ対応していません。") }
        let lengths = try (0..<height).map { _ in Int(try reader.u16()) }
        var output: [UInt8] = []
        output.reserveCapacity(width * height)
        for length in lengths {
            let end = reader.offset + length
            while reader.offset < end, output.count < width * height {
                let marker = Int8(bitPattern: try reader.u8())
                if marker >= 0 {
                    output.append(contentsOf: try reader.bytes(Int(marker) + 1))
                } else if marker != -128 {
                    let value = try reader.u8()
                    output.append(contentsOf: repeatElement(value, count: 1 - Int(marker)))
                }
            }
            reader.offset = end
        }
        if output.count < width * height { output += repeatElement(0, count: width * height - output.count) }
        return Array(output.prefix(width * height))
    }

    private static func makePNG(documentWidth: Int, documentHeight: Int, record: Record, planes: [Int16: [UInt8]]) -> Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: documentWidth, pixelsHigh: documentHeight, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: documentWidth * 4, bitsPerPixel: 32), let target = bitmap.bitmapData else { return nil }
        memset(target, 0, documentWidth * documentHeight * 4)
        let layerWidth = record.right - record.left, layerHeight = record.bottom - record.top
        for y in 0..<layerHeight where record.top + y >= 0 && record.top + y < documentHeight {
            for x in 0..<layerWidth where record.left + x >= 0 && record.left + x < documentWidth {
                let source = y * layerWidth + x
                let destination = ((record.top + y) * documentWidth + record.left + x) * 4
                target[destination] = planes[0]?[source] ?? 0
                target[destination + 1] = planes[1]?[source] ?? 0
                target[destination + 2] = planes[2]?[source] ?? 0
                let alpha = UInt16(planes[-1]?[source] ?? 255) * UInt16(record.opacity) / 255
                target[destination + 3] = UInt8(alpha)
            }
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "VoiceMovieStudio.PSD", code: 2, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private struct Reader {
        let data: Data
        var offset = 0
        mutating func require(_ count: Int) throws {
            guard count >= 0, offset + count <= data.count else {
                throw failure("PSDファイルの読み取り位置が不正です（位置 \(offset)、要求 \(count)、全体 \(data.count)）。")
            }
        }
        mutating func skip(_ count: Int) throws { try require(count); offset += count }
        mutating func bytes(_ count: Int) throws -> [UInt8] { try require(count); defer { offset += count }; return Array(data[offset..<offset + count]) }
        mutating func u8() throws -> UInt8 { try require(1); defer { offset += 1 }; return data[offset] }
        mutating func u16() throws -> UInt16 { let b = try bytes(2); return UInt16(b[0]) << 8 | UInt16(b[1]) }
        mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
        mutating func u32() throws -> UInt32 { let b = try bytes(4); return b.reduce(0) { ($0 << 8) | UInt32($1) } }
        mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
        mutating func ascii(_ count: Int) throws -> String { String(bytes: try bytes(count), encoding: .ascii) ?? "" }
        mutating func skipSection32() throws { try skip(Int(try u32())) }
        mutating func pascalPadded4() throws -> String {
            let length = Int(try u8()); let value = String(bytes: try bytes(length), encoding: .macOSRoman) ?? ""
            try skip((4 - ((length + 1) % 4)) % 4); return value
        }
        mutating func utf16BE(count: Int) throws -> String {
            var values: [UInt16] = []; values.reserveCapacity(count)
            for _ in 0..<count { values.append(try u16()) }
            return String(decoding: values, as: UTF16.self)
        }
    }
}
