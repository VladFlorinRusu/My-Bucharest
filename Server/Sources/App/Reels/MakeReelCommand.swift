import Fluent
import Foundation
import Vapor

/// swift run App make-reel [--place ateneul-roman] [--limit 3] [--force] [--audio-only]
///
/// Pentru fiecare poveste fără video: generează vocea, caută fotografii libere pe Wikimedia
/// Commons și montează un reel vertical servit din Public/videos. Poveștile cu clip YouTube
/// rămân neatinse.
struct MakeReelCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "place", short: "p", help: "Slug-ul locului (ex. ateneul-roman)")
        var place: String?

        @Option(name: "limit", short: "l", help: "Câte povești să proceseze cel mult")
        var limit: Int?

        @Flag(name: "force", help: "Regenerează și poveștile care au deja voce/reel")
        var force: Bool

        @Flag(name: "audio-only", help: "Generează doar vocea, fără video")
        var audioOnly: Bool

        @Flag(name: "thumbnails", help: "Doar miniaturile lipsă pentru reels-urile deja generate")
        var thumbnailsOnly: Bool

        init() {}
    }

    var help: String {
        "Generează voce AI și reels din fotografii Wikimedia pentru poveștile fără video."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let console = context.console
        let db = app.db

        for tool in ["ffmpeg", "ffprobe"] where !ProcessRunner.isAvailable(tool) {
            throw Abort(.internalServerError, reason: "Lipsește \(tool). Pe macOS: brew install ffmpeg")
        }

        let publicDirectory = URL(fileURLWithPath: app.directory.publicDirectory)
        let thumbnailDirectory = publicDirectory.appendingPathComponent("thumbnails")
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)

        if signature.thumbnailsOnly {
            try await backfillThumbnails(in: publicDirectory, thumbnails: thumbnailDirectory, on: db, console: console)
            return
        }

        let speech = try SpeechSynthesizers.fromEnvironment(client: app.client)
        let photos = WikimediaPhotos(
            client: app.client,
            contact: Environment.get("WIKIMEDIA_CONTACT") ?? Environment.get("NOMINATIM_CONTACT") ?? "contact@example.com"
        )
        console.info("Voce: \(speech.name)")

        let targets = try await selectStories(signature: signature, on: db)
        guard !targets.isEmpty else {
            console.info("Nicio poveste de procesat. Folosește --force ca să regenerezi.")
            return
        }
        console.info("Procesez \(targets.count) povești…")

        let audioDirectory = publicDirectory.appendingPathComponent("audio")
        let videoDirectory = publicDirectory.appendingPathComponent("videos")
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mybucharest-reels-\(UUID().uuidString)")
        for directory in [audioDirectory, videoDirectory, workDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        var photoCache: [UUID: [(file: URL, credit: MediaCredit)]] = [:]
        var done = 0

        for story in targets {
            let storyID = try story.requireID()
            let place = story.place
            console.info("▶ \(place.name) – \(story.title)")

            do {
                let storyWork = workDirectory.appendingPathComponent(storyID.uuidString)
                try FileManager.default.createDirectory(at: storyWork, withIntermediateDirectories: true)

                let rawVoice = try await speech.synthesize("\(story.title). \(story.body)", in: storyWork)
                let audioName = "\(storyID.uuidString.lowercased()).m4a"
                let audioFile = audioDirectory.appendingPathComponent(audioName)
                try ReelRenderer.normalizeAudio(rawVoice, to: audioFile)
                story.audioURL = "/audio/\(audioName)"
                story.aiVoice = true

                if !signature.audioOnly {
                    let placeID = try place.requireID()
                    if photoCache[placeID] == nil {
                        photoCache[placeID] = try await downloadPhotos(for: place, using: photos, into: workDirectory)
                    }
                    let available = photoCache[placeID] ?? []

                    if available.isEmpty {
                        console.warning("  Nu am găsit fotografii libere pentru „\(place.name)”; rămâne doar vocea.")
                    } else {
                        // Rotim ordinea ca povești diferite ale aceluiași loc să nu înceapă cu aceeași poză.
                        let shift = story.position % available.count
                        let ordered = Array(available[shift...] + available[..<shift])
                        let duration = try ReelRenderer.audioDuration(audioFile) + ReelRenderer.tail
                        let used = Array(ordered.prefix(ReelRenderer.photoCount(available: ordered.count, duration: duration)))

                        let videoName = "\(storyID.uuidString.lowercased()).mp4"
                        let videoFile = videoDirectory.appendingPathComponent(videoName)
                        try ReelRenderer.render(photos: used.map(\.file), audio: audioFile, output: videoFile)

                        let thumbnailName = "\(storyID.uuidString.lowercased()).jpg"
                        try ReelRenderer.extractThumbnail(from: videoFile, to: thumbnailDirectory.appendingPathComponent(thumbnailName))
                        story.thumbnailURL = "/thumbnails/\(thumbnailName)"
                        story.videoKind = .hosted
                        story.videoURL = "/videos/\(videoName)"
                        story.youtubeID = nil
                        story.startSeconds = nil
                        story.endSeconds = nil
                        story.mediaCredits = used.map(\.credit)
                    }
                }

                try await story.save(on: db)
                done += 1
                console.success("  ✓ gata\(story.videoKind == .hosted ? " (reel + voce)" : " (voce)")")
            } catch {
                console.error("  ✗ \(error)")
            }
        }

        console.info("Finalizat: \(done)/\(targets.count) povești.")
    }

    private func backfillThumbnails(
        in publicDirectory: URL,
        thumbnails: URL,
        on db: any Database,
        console: any Console
    ) async throws {
        let stories = try await Story.query(on: db)
            .filter(\.$videoKind == .hosted)
            .filter(\.$thumbnailURL == nil)
            .all()
        var done = 0
        for story in stories {
            guard let videoPath = story.videoURL else { continue }
            let video = publicDirectory.appendingPathComponent(videoPath)
            guard FileManager.default.fileExists(atPath: video.path) else {
                console.warning("  ✗ \(story.title): lipsește \(videoPath)")
                continue
            }
            let name = "\(try story.requireID().uuidString.lowercased()).jpg"
            try ReelRenderer.extractThumbnail(from: video, to: thumbnails.appendingPathComponent(name))
            story.thumbnailURL = "/thumbnails/\(name)"
            try await story.save(on: db)
            done += 1
        }
        console.success("Miniaturi generate: \(done)/\(stories.count).")
    }

    private func selectStories(signature: Signature, on db: any Database) async throws -> [Story] {
        let query = Story.query(on: db).with(\.$place).sort(\.$position)
        if let slug = signature.place {
            guard let place = try await Place.query(on: db).filter(\.$slug == slug).first() else {
                throw Abort(.notFound, reason: "Nu există niciun loc cu slug-ul „\(slug)”.")
            }
            query.filter(\.$place.$id == (try place.requireID()))
        }

        let candidates = try await query.all().filter { story in
            if story.videoKind == .youtube { return false }
            if signature.force { return true }
            return signature.audioOnly ? story.audioURL == nil : story.videoKind == nil
        }
        return Array(candidates.prefix(signature.limit ?? .max))
    }

    private func downloadPhotos(
        for place: Place,
        using photos: WikimediaPhotos,
        into directory: URL
    ) async throws -> [(file: URL, credit: MediaCredit)] {
        var found = try await photos.search(place.name, limit: 5)
        if found.count < 2 {
            found += try await photos.search("\(place.name) Bucharest", limit: 5)
        }

        var seen = Set<String>()
        var result: [(file: URL, credit: MediaCredit)] = []
        for (index, photo) in found.enumerated() where seen.insert(photo.credit.sourceURL).inserted {
            let file = directory.appendingPathComponent("\(try place.requireID().uuidString)-\(index).jpg")
            try await photos.download(photo, to: file)
            result.append((file, photo.credit))
            if result.count == 5 { break }
        }
        return result
    }
}
