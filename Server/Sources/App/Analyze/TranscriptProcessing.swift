import Foundation

struct TranscriptBlock: Equatable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

enum TranscriptProcessing {
    /// Subtitrări YouTube în formatul `json3` (descărcate cu yt-dlp).
    static func parseJSON3(_ data: Data) throws -> [TranscriptBlock] {
        struct File: Decodable {
            struct Event: Decodable {
                struct Segment: Decodable { var utf8: String? }
                var tStartMs: Int?
                var dDurationMs: Int?
                var segs: [Segment]?
            }
            var events: [Event]?
        }

        return try JSONDecoder().decode(File.self, from: data).events?.compactMap { event in
            guard let start = event.tStartMs, let segments = event.segs else { return nil }
            let text = clean(segments.compactMap(\.utf8).joined())
            guard !text.isEmpty else { return nil }
            let startSeconds = Double(start) / 1000
            return TranscriptBlock(
                start: startSeconds,
                end: startSeconds + Double(event.dDurationMs ?? 0) / 1000,
                text: text
            )
        } ?? []
    }

    /// Ieșirea `whisper-cli -oj`.
    static func parseWhisperJSON(_ data: Data) throws -> [TranscriptBlock] {
        struct File: Decodable {
            struct Item: Decodable {
                struct Offsets: Decodable { var from: Int; var to: Int }
                var offsets: Offsets
                var text: String
            }
            var transcription: [Item]
        }

        return try JSONDecoder().decode(File.self, from: data).transcription.compactMap { item in
            let text = clean(item.text)
            guard !text.isEmpty else { return nil }
            return TranscriptBlock(start: Double(item.offsets.from) / 1000, end: Double(item.offsets.to) / 1000, text: text)
        }
    }

    /// Unește replicile scurte în blocuri de ~20 de secunde, suficient de fine pentru citări.
    static func mergeIntoBlocks(_ cues: [TranscriptBlock], minDuration: Double = 20, maxCharacters: Int = 450) -> [TranscriptBlock] {
        var blocks: [TranscriptBlock] = []
        var current: TranscriptBlock?

        for cue in cues {
            guard var block = current else {
                current = cue
                continue
            }
            block.text += " " + cue.text
            block.end = max(block.end, cue.end)
            if block.end - block.start >= minDuration || block.text.count >= maxCharacters {
                blocks.append(block)
                current = nil
            } else {
                current = block
            }
        }
        if let current { blocks.append(current) }
        return blocks
    }

    /// Împarte transcriptul în bucăți care încap comod într-un singur apel LLM.
    static func chunks(_ blocks: [TranscriptBlock], maxCharacters: Int = 12_000) -> [[TranscriptBlock]] {
        var result: [[TranscriptBlock]] = []
        var current: [TranscriptBlock] = []
        var size = 0
        for block in blocks {
            if size + block.text.count > maxCharacters, !current.isEmpty {
                result.append(current)
                current = []
                size = 0
            }
            current.append(block)
            size += block.text.count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Scoate adnotările de tip „[Muzică]” / „[Aplauze]” și spațiile multiple.
    static func clean(_ text: String) -> String {
        text.replacing(/\[[^\]]{1,24}\]/, with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

enum Timecode {
    /// 754 -> "12:34", 3_725 -> "1:02:05"
    static func format(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Primul an (3-4 cifre) dintr-o dată de tipul „1888”, „1930–1940”, „secolul XIX” -> nil.
    static func firstYear(in text: String) -> Int? {
        text.firstMatch(of: /\d{3,4}/).flatMap { Int($0.output) }
    }
}
