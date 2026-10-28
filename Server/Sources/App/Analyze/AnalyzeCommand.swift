import Fluent
import Foundation
import Vapor

/// swift run App analyze "https://www.youtube.com/watch?v=..." [--force] [--whisper] [--transcript-only]
///
/// Ia transcriptul clipului (subtitrări YouTube sau, dacă lipsesc, Whisper din audio), îl salvează pe
/// segmente, extrage faptele esențiale etichetate și scrie un raport în Reports/<id>.md.
struct AnalyzeCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "url", help: "Link-ul clipului YouTube")
        var url: String

        @Option(name: "language", help: "Limba vorbită în clip (implicit ro)")
        var language: String?

        @Flag(name: "force", help: "Reanalizează un clip deja analizat")
        var force: Bool

        @Flag(name: "whisper", help: "Folosește Whisper chiar dacă există subtitrări")
        var whisper: Bool

        @Flag(name: "transcript-only", help: "Doar transcriptul, fără extragerea faptelor cu LLM")
        var transcriptOnly: Bool

        @Option(name: "facts", help: "Fișier JSON cu faptele deja extrase ({\"summary\": ..., \"facts\": [...]}), în loc de LLM")
        var factsFile: String?

        init() {}
    }

    /// Formatul fișierului dat cu --facts; aceleași câmpuri pe care le întoarce LLM-ul.
    struct FactsFile: Decodable {
        var summary: String?
        var facts: [ExtractedFact]
    }

    var help: String {
        "Transcrie un clip YouTube și extrage faptele esențiale, etichetate."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let console = context.console
        let db = app.db

        guard let videoID = YouTube.videoID(from: signature.url) else {
            throw Abort(.badRequest, reason: "Nu am putut extrage ID-ul clipului din „\(signature.url)”.")
        }
        guard ProcessRunner.isAvailable("yt-dlp") else {
            throw Abort(.internalServerError, reason: "Lipsește yt-dlp. Pe macOS: brew install yt-dlp")
        }
        let importedFacts = try signature.factsFile.map { path in
            try JSONDecoder().decode(FactsFile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let reportsDirectory = URL(fileURLWithPath: app.directory.workingDirectory).appendingPathComponent("Reports")
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)

        let existing = try await MediaSource.query(on: db)
            .filter(\.$kind == "youtube").filter(\.$externalID == videoID).first()
        let existingFacts = try await existing?.$facts.query(on: db).all() ?? []

        if let existing, !signature.force, importedFacts == nil, signature.transcriptOnly || !existingFacts.isEmpty {
            try await writeReport(for: existing, facts: existingFacts, transcriptOnly: signature.transcriptOnly,
                                  in: reportsDirectory, on: db, console: console)
            console.info("Clipul era deja analizat. Folosește --force ca să-l reanalizezi de la zero.")
            return
        }

        // Verificăm configurația LLM înainte de pașii lungi (descărcare, Whisper).
        let extractor = signature.transcriptOnly || importedFacts != nil
            ? nil
            : FactExtractor(llm: try LLMClient.fromEnvironment(client: app.client))

        let source: MediaSource
        let blocks: [TranscriptBlock]
        if let existing, !signature.force {
            // Transcriptul e salvat dintr-o rulare anterioară (ex. --transcript-only): îl refolosim.
            source = existing
            blocks = try await existing.$segments.query(on: db).sort(\.$position).all()
                .map { TranscriptBlock(start: $0.startSeconds, end: $0.endSeconds, text: $0.text) }
            console.info("Refolosesc transcriptul salvat: „\(existing.title)” (\(blocks.count) segmente).")
        } else {
            (source, blocks) = try await transcribe(videoID: videoID, signature: signature, on: db, console: console)
        }

        if let importedFacts {
            let sourceID = try source.requireID()
            try await Fact.query(on: db).filter(\.$source.$id == sourceID).delete()
            let saved = try await saveFacts(importedFacts.facts, sourceID: sourceID, fallbackStart: 0, on: db)
            source.summary = importedFacts.summary
            try await source.save(on: db)
            console.info("Am importat \(saved.count) fapte din \(signature.factsFile ?? "fișier").")
            try await writeReport(for: source, facts: saved, transcriptOnly: false, in: reportsDirectory, on: db, console: console)
        } else if let extractor {
            let sourceID = try source.requireID()
            let chunks = TranscriptProcessing.chunks(blocks)
            var saved: [Fact] = []
            for (index, chunk) in chunks.enumerated() {
                console.info("Extrag faptele (\(index + 1)/\(chunks.count))…")
                let extracted = try await extractor.extractFacts(title: source.title, channel: source.channel, chunk: chunk)
                saved += try await saveFacts(extracted, sourceID: sourceID, fallbackStart: Int(chunk.first?.start ?? 0), on: db)
            }
            console.info("Am extras \(saved.count) fapte.")

            if !saved.isEmpty {
                console.info("Scriu rezumatul…")
                source.summary = try await extractor.summarize(title: source.title, channel: source.channel, facts: saved)
                try await source.save(on: db)
            }
            try await writeReport(for: source, facts: saved, transcriptOnly: false, in: reportsDirectory, on: db, console: console)
        } else {
            try await writeReport(for: source, facts: [], transcriptOnly: true, in: reportsDirectory, on: db, console: console)
        }
    }

    private func saveFacts(
        _ extracted: [ExtractedFact],
        sourceID: UUID,
        fallbackStart: Int,
        on db: any Database
    ) async throws -> [Fact] {
        var saved: [Fact] = []
        for item in extracted where !item.statement.trimmingCharacters(in: .whitespaces).isEmpty {
            let fact = Fact()
            fact.$source.id = sourceID
            fact.statement = item.statement
            fact.kind = item.kind.flatMap(FactKind.init(rawValue:)) ?? .fact
            fact.startSeconds = item.startSeconds ?? fallbackStart
            fact.endSeconds = item.endSeconds
            fact.places = item.places ?? []
            fact.people = item.people ?? []
            fact.dates = item.dates ?? []
            fact.topics = item.topics ?? []
            fact.importance = min(max(item.importance ?? 2, 1), 3)
            try await fact.save(on: db)
            saved.append(fact)
        }
        return saved
    }

    private func transcribe(
        videoID: String,
        signature: Signature,
        on db: any Database,
        console: any Console
    ) async throws -> (MediaSource, [TranscriptBlock]) {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mybucharest-analyze-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let transcriber = YouTubeTranscriber(
            language: signature.language ?? "ro",
            whisperModel: Environment.get("WHISPER_MODEL") ?? "models/ggml-large-v3-turbo.bin",
            workDirectory: workDirectory
        )
        let url = "https://www.youtube.com/watch?v=\(videoID)"

        console.info("Citesc informațiile clipului…")
        let metadata = try transcriber.metadata(for: url)
        console.info("„\(metadata.title)” – \(metadata.channel ?? metadata.uploader ?? "canal necunoscut")")

        var transcript: Transcript?
        if !signature.whisper {
            console.info("Caut subtitrări…")
            transcript = try transcriber.captions(for: url, metadata: metadata)
        }
        if transcript == nil {
            console.info("Nu există subtitrări potrivite; transcriu audio-ul cu Whisper (poate dura câteva minute)…")
            transcript = try transcriber.whisper(for: url)
        }
        guard let transcript, !transcript.blocks.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Transcriptul a ieșit gol.")
        }
        console.info("Transcript: \(transcript.blocks.count) segmente (\(transcript.origin.label)).")

        let source = try await saveSource(videoID: videoID, url: url, metadata: metadata, transcript: transcript, on: db)
        return (source, transcript.blocks)
    }

    private func writeReport(
        for source: MediaSource,
        facts: [Fact],
        transcriptOnly: Bool,
        in directory: URL,
        on db: any Database,
        console: any Console
    ) async throws {
        let folder = AnalysisReport.folder(for: source, in: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let segments = try await source.$segments.query(on: db).all()
        try AnalysisReport.transcriptText(segments)
            .write(to: folder.appendingPathComponent(AnalysisReport.transcriptFile), atomically: true, encoding: .utf8)

        if !transcriptOnly {
            try AnalysisReport.markdown(source: source, facts: facts)
                .write(to: folder.appendingPathComponent(AnalysisReport.reportFile), atomically: true, encoding: .utf8)
            try AnalysisReport.factsJSON(summary: source.summary, facts: facts)
                .write(to: folder.appendingPathComponent(AnalysisReport.factsFile))
        }
        console.success("Rezultate (\(facts.count) fapte): \(folder.path)")
    }

    private func saveSource(
        videoID: String,
        url: String,
        metadata: YouTubeMetadata,
        transcript: Transcript,
        on db: any Database
    ) async throws -> MediaSource {
        try await db.transaction { db in
            if let old = try await MediaSource.query(on: db)
                .filter(\.$kind == "youtube").filter(\.$externalID == videoID).first() {
                let oldID = try old.requireID()
                try await Fact.query(on: db).filter(\.$source.$id == oldID).delete()
                try await TranscriptSegment.query(on: db).filter(\.$source.$id == oldID).delete()
                try await old.delete(on: db)
            }

            let source = MediaSource()
            source.kind = "youtube"
            source.externalID = videoID
            source.url = url
            source.title = metadata.title
            source.channel = metadata.channel ?? metadata.uploader
            source.durationSeconds = metadata.duration
            source.transcriptOrigin = transcript.origin
            source.language = transcript.language
            try await source.save(on: db)

            let sourceID = try source.requireID()
            for (position, block) in transcript.blocks.enumerated() {
                try await TranscriptSegment(sourceID: sourceID, position: position, block: block).save(on: db)
            }
            return source
        }
    }
}
