import Foundation
import Vapor

struct YouTubeMetadata: Decodable, Sendable {
    struct CaptionFormat: Decodable, Sendable {
        var ext: String?
    }

    var id: String
    var title: String
    var channel: String?
    var uploader: String?
    var duration: Double?
    var language: String?
    var subtitles: [String: [CaptionFormat]]?
    var automaticCaptions: [String: [CaptionFormat]]?

    enum CodingKeys: String, CodingKey {
        case id, title, channel, uploader, duration, language, subtitles
        case automaticCaptions = "automatic_captions"
    }
}

struct Transcript: Sendable {
    var origin: TranscriptOrigin
    var language: String
    var blocks: [TranscriptBlock]
}

/// Obține transcriptul unui clip YouTube: întâi din subtitrări, apoi, dacă lipsesc, cu Whisper din audio.
/// Folosește unelte externe: yt-dlp, iar pentru Whisper și ffmpeg + whisper-cli (whisper.cpp).
struct YouTubeTranscriber {
    var language: String
    var whisperModel: String
    var workDirectory: URL

    func metadata(for url: String) throws -> YouTubeMetadata {
        let json = try ProcessRunner.run("yt-dlp", ["-J", "--no-playlist", "--no-warnings", url])
        return try JSONDecoder().decode(YouTubeMetadata.self, from: Data(json.utf8))
    }

    /// Alege pista de subtitrări în limba cerută: scrise de autor, apoi automate în limba originală.
    /// Subtitrările automate *traduse* din altă limbă sunt ignorate.
    static func pickCaptions(_ metadata: YouTubeMetadata, language: String) -> (key: String, origin: TranscriptOrigin)? {
        let manual = (metadata.subtitles ?? [:]).keys.sorted()
        if let key = manual.first(where: { $0 == language || $0.hasPrefix(language + "-") }) {
            return (key, .manualCaptions)
        }
        let automatic = metadata.automaticCaptions ?? [:]
        if automatic["\(language)-orig"] != nil {
            return ("\(language)-orig", .autoCaptions)
        }
        if metadata.language?.hasPrefix(language) == true, automatic[language] != nil {
            return (language, .autoCaptions)
        }
        return nil
    }

    func captions(for url: String, metadata: YouTubeMetadata) throws -> Transcript? {
        guard let (key, origin) = Self.pickCaptions(metadata, language: language) else { return nil }
        let directory = workDirectory.appendingPathComponent("captions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try ProcessRunner.run("yt-dlp", [
            "--skip-download", "--no-playlist", "--no-warnings",
            origin == .manualCaptions ? "--write-subs" : "--write-auto-subs",
            "--sub-langs", key, "--sub-format", "json3",
            "-o", directory.appendingPathComponent("subs").path,
            url,
        ])

        guard let file = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "json3" })
        else {
            return nil
        }
        let cues = try TranscriptProcessing.parseJSON3(Data(contentsOf: file))
        guard !cues.isEmpty else { return nil }
        return Transcript(origin: origin, language: language, blocks: TranscriptProcessing.mergeIntoBlocks(cues))
    }

    func whisper(for url: String) throws -> Transcript {
        for tool in ["ffmpeg", "whisper-cli"] where !ProcessRunner.isAvailable(tool) {
            throw Abort(.internalServerError, reason: "Lipsește \(tool). Pe macOS: brew install ffmpeg whisper-cpp")
        }
        guard FileManager.default.fileExists(atPath: whisperModel) else {
            throw Abort(.internalServerError, reason: """
            Nu găsesc modelul Whisper la \(whisperModel). Descarcă-l cu:
              mkdir -p models && curl -L -o models/ggml-large-v3-turbo.bin \
            https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
            """)
        }

        let directory = workDirectory.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try ProcessRunner.run("yt-dlp", [
            "-f", "bestaudio", "--no-playlist", "--no-warnings",
            "-o", directory.appendingPathComponent("source.%(ext)s").path,
            url,
        ])
        guard let downloaded = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix("source.") })
        else {
            throw Abort(.internalServerError, reason: "yt-dlp nu a descărcat audio-ul.")
        }

        // whisper.cpp cere WAV mono la 16 kHz.
        let wav = directory.appendingPathComponent("audio.wav")
        try ProcessRunner.run("ffmpeg", [
            "-y", "-loglevel", "error", "-nostats", "-i", downloaded.path,
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav.path,
        ])

        let outputBase = directory.appendingPathComponent("whisper")
        try ProcessRunner.run("whisper-cli", [
            "-m", whisperModel, "-l", language, "-f", wav.path,
            "-oj", "-of", outputBase.path, "-np",
        ])
        let cues = try TranscriptProcessing.parseWhisperJSON(Data(contentsOf: outputBase.appendingPathExtension("json")))
        return Transcript(origin: .whisper, language: language, blocks: TranscriptProcessing.mergeIntoBlocks(cues))
    }
}
