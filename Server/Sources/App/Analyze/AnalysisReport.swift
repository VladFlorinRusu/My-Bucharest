import Foundation

/// Raportul Markdown al unui clip analizat: rezumat, cronologie, index de persoane/locuri/teme.
enum AnalysisReport {
    static let transcriptFile = "transcript.txt"
    static let reportFile = "raport.md"
    static let factsFile = "fapte.json"

    /// Folderul cu rezultatele unui clip, numit după titlul lui: Reports/<titlu clip>/
    static func folder(for source: MediaSource, in reports: URL) -> URL {
        reports.appendingPathComponent(folderName(title: source.title, fallback: source.externalID), isDirectory: true)
    }

    static func folderName(title: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(120))
    }

    /// Faptele în același format acceptat de `analyze --facts`, ca să poată fi editate și reimportate.
    static func factsJSON(summary: String?, facts: [Fact]) throws -> Data {
        struct ExportedFact: Encodable {
            var statement: String
            var kind: String
            var startSeconds: Int
            var endSeconds: Int?
            var places: [String]
            var people: [String]
            var dates: [String]
            var topics: [String]
            var importance: Int
        }
        struct Export: Encodable {
            var summary: String?
            var facts: [ExportedFact]
        }
        let export = Export(summary: summary, facts: facts.sorted { $0.startSeconds < $1.startSeconds }.map {
            ExportedFact(statement: $0.statement, kind: $0.kind.rawValue, startSeconds: $0.startSeconds,
                         endSeconds: $0.endSeconds, places: $0.places, people: $0.people, dates: $0.dates,
                         topics: $0.topics, importance: $0.importance)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(export)
    }
    static func markdown(source: MediaSource, facts: [Fact]) -> String {
        let videoID = source.externalID
        func link(_ seconds: Int) -> String {
            "[\(Timecode.format(Double(seconds)))](https://youtu.be/\(videoID)?t=\(seconds))"
        }

        var lines: [String] = []
        lines.append("# \(source.title)")
        lines.append("")
        var meta = [source.channel, source.durationSeconds.map { "durată \(Timecode.format($0))" }, source.transcriptOrigin.label]
            .compactMap { $0 }
        meta.append("[clip](\(source.url))")
        lines.append(meta.joined(separator: " · "))
        lines.append("")

        if let summary = source.summary {
            lines += ["## Pe scurt", "", summary, ""]
        }

        let timeline = facts
            .filter { $0.kind == .event && !$0.dates.isEmpty }
            .sorted { (Timecode.firstYear(in: $0.dates[0]) ?? .max, $0.startSeconds) < (Timecode.firstYear(in: $1.dates[0]) ?? .max, $1.startSeconds) }
        if !timeline.isEmpty {
            lines += ["## Cronologie", ""]
            for fact in timeline {
                lines.append("- **\(fact.dates.joined(separator: ", "))**: \(fact.statement) (\(link(fact.startSeconds)))")
            }
            lines.append("")
        }

        for (title, keyPath) in [("Persoane", \Fact.people), ("Locuri", \Fact.places)] {
            let index = self.index(facts, by: keyPath)
            guard !index.isEmpty else { continue }
            lines += ["## \(title)", ""]
            for (name, mentions) in index {
                lines.append("- **\(name)**: \(mentions.map { link($0.startSeconds) }.joined(separator: ", "))")
            }
            lines.append("")
        }

        let topics = index(facts, by: \.topics)
        if !topics.isEmpty {
            lines += ["## Teme", ""]
            lines.append(topics.map { "\($0.key) (\($0.facts.count))" }.joined(separator: " · "))
            lines.append("")
        }

        lines += ["## Toate faptele", ""]
        for fact in facts.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let stars = String(repeating: "★", count: max(1, min(fact.importance, 3)))
            lines.append("### \(link(fact.startSeconds)) \(stars) \(fact.statement)")
            var tags = ["`\(fact.kind.rawValue)`"]
            if !fact.places.isEmpty { tags.append("Locuri: \(fact.places.joined(separator: ", "))") }
            if !fact.people.isEmpty { tags.append("Persoane: \(fact.people.joined(separator: ", "))") }
            if !fact.dates.isEmpty { tags.append("Date: \(fact.dates.joined(separator: ", "))") }
            if !fact.topics.isEmpty { tags.append("Teme: \(fact.topics.joined(separator: ", "))") }
            lines += [tags.joined(separator: " · "), ""]
        }

        return lines.joined(separator: "\n")
    }

    /// Grupează faptele după o etichetă, cu cele mai menționate primele.
    static func index(_ facts: [Fact], by keyPath: KeyPath<Fact, [String]>) -> [(key: String, facts: [Fact])] {
        var groups: [String: [Fact]] = [:]
        for fact in facts {
            for tag in Set(fact[keyPath: keyPath].map { $0.trimmingCharacters(in: .whitespaces) }) where !tag.isEmpty {
                groups[tag, default: []].append(fact)
            }
        }
        return groups
            .map { (key: $0.key, facts: $0.value.sorted { $0.startSeconds < $1.startSeconds }) }
            .sorted { ($0.facts.count, $1.key) > ($1.facts.count, $0.key) }
    }

    static func transcriptText(_ segments: [TranscriptSegment]) -> String {
        segments
            .sorted { $0.position < $1.position }
            .map { "[\(Timecode.format($0.startSeconds))] \($0.text)" }
            .joined(separator: "\n")
    }
}
