import Foundation

struct ID3Tag {
    var title = ""
    var artist = ""
    var album = ""
    var year = ""
    var genre = ""
    var comment = ""
    var track = ""
    var artwork: Data?
    var artworkMimeType = "image/jpeg"
}

enum ID3Error: LocalizedError {
    case notMPEGFile
    case badTag

    var errorDescription: String? {
        switch self {
        case .notMPEGFile: return "This file has no ID3 tag."
        case .badTag: return "The ID3 tag is damaged."
        }
    }
}

/// Minimal ID3v2 reader/writer (v2.3 and v2.4 read, v2.4 write).
enum ID3 {

    // MARK: - Read

    static func read(from url: URL) throws -> ID3Tag {
        try read(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func read(data: Data) throws -> ID3Tag {
        guard data.count >= 10 else { throw ID3Error.badTag }
        guard String(data: data[0..<3], encoding: .ascii) == "ID3" else { throw ID3Error.notMPEGFile }

        let version = Int(data[3])
        let flags = data[5]
        let tagSize = syncSafeValue(data[6..<10])
        guard tagSize >= 0, 10 + tagSize <= data.count else { throw ID3Error.badTag }

        var bodyStart = 10
        let bodyEnd = 10 + tagSize

        if flags & 0x40 != 0 { // extended header present
            guard bodyStart + 4 <= data.count else { throw ID3Error.badTag }
            let raw = bigEndianValue(data[bodyStart..<(bodyStart + 4)])
            bodyStart += version >= 4 ? syncSafeValue(data[bodyStart..<(bodyStart + 4)]) : Int(raw) + 4
        }

        var tag = ID3Tag()
        var offset = bodyStart
        while offset + 10 <= bodyEnd {
            let identifier = String(data: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            if identifier.isEmpty || identifier.first == "\0" { break } // padding

            let size = version >= 4
                ? syncSafeValue(data[(offset + 4)..<(offset + 8)])
                : Int(bigEndianValue(data[(offset + 4)..<(offset + 8)]))
            let dataStart = offset + 10
            guard size >= 0, dataStart + size <= bodyEnd else { break }

            apply(identifier: identifier, payload: Data(data[dataStart..<(dataStart + size)]), to: &tag)
            offset = dataStart + size
        }
        return tag
    }

    private static func apply(identifier: String, payload: Data, to tag: inout ID3Tag) {
        switch identifier {
        case "TIT2": tag.title = decode(payload)
        case "TPE1": tag.artist = decode(payload)
        case "TALB": tag.album = decode(payload)
        case "TYER", "TDRC": tag.year = decode(payload)
        case "TCON": tag.genre = decode(payload)
        case "TRCK": tag.track = decode(payload)
        case "COMM": tag.comment = decodeComment(payload)
        case "APIC": (tag.artwork, tag.artworkMimeType) = artwork(payload)
        default: break
        }
    }

    // MARK: - Write

    static func write(_ tag: ID3Tag, to url: URL) throws {
        var frames = Data()

        func addText(_ identifier: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            var payload = Data([3]) // UTF-8
            payload.append(Data(trimmed.utf8))
            frames.append(frame(identifier: identifier, payload: payload))
        }

        addText("TIT2", tag.title)
        addText("TPE1", tag.artist)
        addText("TALB", tag.album)
        addText("TDRC", tag.year)
        addText("TCON", tag.genre)
        addText("TRCK", tag.track)

        if !tag.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var payload = Data([3])
            payload.append(Data("eng".utf8))
            payload.append(0) // empty description
            payload.append(Data(tag.comment.utf8))
            frames.append(frame(identifier: "COMM", payload: payload))
        }

        if let artwork = tag.artwork {
            let mime = tag.artworkMimeType
            let safeMime = mime.isEmpty || mime.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                ? "image/jpeg" : mime
            var payload = Data([3])
            payload.append(Data(safeMime.utf8))
            payload.append(0) // mime terminator
            payload.append(3) // picture type: cover
            payload.append(0) // empty description
            payload.append(artwork)
            frames.append(frame(identifier: "APIC", payload: payload))
        }

        var header = Data("ID3".utf8)
        header.append(contentsOf: [4, 0, 0]) // v2.4.0, no flags
        header.append(contentsOf: syncSafeBytes(frames.count))

        let fileManager = FileManager.default
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let fileSize = try input.seekToEnd()
        try input.seek(toOffset: 0)
        let prefix = try input.read(upToCount: 10) ?? Data()
        var audioStart = 0
        if prefix.count >= 10, String(data: prefix[0..<3], encoding: .ascii) == "ID3" {
            let version = Int(prefix[3])
            let tagSize = version >= 4
                ? syncSafeValue(prefix[6..<10])
                : Int(bigEndianValue(prefix[6..<10]))
            guard tagSize >= 0, Int64(10 + tagSize) <= fileSize else { throw ID3Error.badTag }
            audioStart = 10 + tagSize
        }

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try Data().write(to: temporary)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        try output.write(contentsOf: header)
        try output.write(contentsOf: frames)
        try input.seek(toOffset: UInt64(audioStart))
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.close()
        try input.close()
        _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
    }

    private static func frame(identifier: String, payload: Data) -> Data {
        var out = Data(identifier.utf8)
        out.append(contentsOf: syncSafeBytes(payload.count))
        out.append(contentsOf: [0, 0])
        out.append(payload)
        return out
    }

    // MARK: - Decoding helpers

    private static func decode(_ data: Data, skipping skipBytes: Int = 0) -> String {
        guard let first = data.first else { return "" }
        let payload = data.dropFirst(skipBytes + 1)
        switch first {
        case 0: return String(data: payload, encoding: .isoLatin1) ?? ""
        case 1: return String(data: payload, encoding: .utf16) ?? ""
        case 2: return String(data: payload, encoding: .utf16BigEndian) ?? ""
        default: return String(data: payload, encoding: .utf8) ?? ""
        }
    }

    private static func decodeComment(_ payload: Data) -> String {
        // encoding(1) + language(3) + short description (null terminated) + text
        guard payload.count > 4 else { return "" }
        var index = 4
        while index < payload.count, payload[index] != 0 { index += 1 }
        guard index < payload.count else { return "" }
        return decode(payload, skipping: index)
    }

    private static func artwork(_ payload: Data) -> (Data?, String) {
        // encoding(1) + mime (null terminated) + type(1) + description (null terminated) + image
        guard payload.count > 2 else { return (nil, "image/jpeg") }
        var index = 1
        while index < payload.count, payload[index] != 0 { index += 1 }
        guard index < payload.count else { return (nil, "image/jpeg") }
        let mime = String(data: payload[1..<index], encoding: .isoLatin1) ?? "image/jpeg"
        index += 2 // mime terminator + picture type
        while index < payload.count, payload[index] != 0 { index += 1 }
        guard index < payload.count else { return (nil, mime) }
        let image = Data(payload[(index + 1)...])
        return (image.isEmpty ? nil : image, mime)
    }

    private static func syncSafeBytes(_ count: Int) -> [UInt8] {
        [
            UInt8((count >> 21) & 0x7F),
            UInt8((count >> 14) & 0x7F),
            UInt8((count >> 7) & 0x7F),
            UInt8(count & 0x7F)
        ]
    }

    private static func syncSafeValue(_ bytes: Data) -> Int {
        guard bytes.count >= 4 else { return 0 }
        let b = bytes.map { Int($0) }
        return (b[0] & 0x7F) << 21 | (b[1] & 0x7F) << 14 | (b[2] & 0x7F) << 7 | (b[3] & 0x7F)
    }

    private static func bigEndianValue(_ bytes: Data) -> UInt32 {
        var value: UInt32 = 0
        for byte in bytes { value = (value << 8) | UInt32(byte) }
        return value
    }
}
