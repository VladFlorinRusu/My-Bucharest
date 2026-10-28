import Fluent
import Foundation
import Vapor

/// swift run App ingest "https://youtube.com/watch?v=..." --transcript transcript.txt
///
/// Trimite transcrierea la LLM, geocodează locurile găsite și le salvează ca draft,
/// cu câte o poveste per curiozitate, legată de segmentul relevant din clip (embed YouTube).
struct IngestCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "video", help: "URL-ul sau ID-ul clipului YouTube")
        var video: String

        @Option(name: "transcript", short: "t", help: "Fișier text cu transcrierea (ideal cu timestamp-uri)")
        var transcript: String?

        @Option(name: "channel", short: "c", help: "Numele canalului, dacă nu folosești YOUTUBE_API_KEY")
        var channel: String?

        @Option(name: "title", help: "Titlul clipului, dacă nu folosești YOUTUBE_API_KEY")
        var title: String?

        @Flag(name: "publish", help: "Publică direct locurile noi (implicit rămân draft pentru revizuire)")
        var publish: Bool

        init() {}
    }

    var help: String {
        "Extrage locuri și curiozități din transcrierea unui clip YouTube."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let console = context.console

        guard let videoID = YouTube.videoID(from: signature.video) else {
            throw Abort(.badRequest, reason: "Nu am putut extrage ID-ul clipului din „\(signature.video)”.")
        }
        guard let transcriptPath = signature.transcript else {
            throw Abort(.badRequest, reason: "Lipsește --transcript <fișier>.")
        }
        let transcript = try String(contentsOfFile: transcriptPath, encoding: .utf8)

        var video = YouTubeVideoInfo(id: videoID, title: signature.title, channel: signature.channel)
        if let apiKey = Environment.get("YOUTUBE_API_KEY") {
            console.info("Citesc metadatele clipului \(videoID)…")
            let info = try await YouTube.fetchInfo(id: videoID, apiKey: apiKey, client: app.client)
            video.title = signature.title ?? info.title
            video.channel = signature.channel ?? info.channel
            video.description = info.description
        }

        console.info("Trimit transcrierea la LLM…")
        let extractor = try LLMExtractor.fromEnvironment(client: app.client)
        let extracted = try await extractor.extractPlaces(video: video, transcript: transcript)
        console.info("LLM a găsit \(extracted.count) locuri.")

        let geocoder = Geocoder(
            client: app.client,
            contact: Environment.get("NOMINATIM_CONTACT") ?? "contact@example.com"
        )
        let db = app.db
        var created = 0, updated = 0, skipped = 0

        for item in extracted {
            let slug = Slug.make(from: item.name)
            let place: Place

            if let existing = try await Place.query(on: db).filter(\.$slug == slug).first() {
                place = existing
                updated += 1
            } else {
                let query = item.searchQuery ?? "\(item.name), București"
                guard let point = try await geocoder.locate(query) else {
                    console.warning("  ✗ \(item.name): nu am găsit coordonate pentru „\(query)”, sar peste.")
                    skipped += 1
                    try await Task.sleep(for: .seconds(1.1))
                    continue
                }
                try await Task.sleep(for: .seconds(1.1))

                place = Place(
                    name: item.name,
                    summary: item.summary,
                    category: item.placeCategory,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    address: point.displayName,
                    status: signature.publish ? .published : .draft
                )
                try await place.save(on: db)
                created += 1
            }

            let placeID = try place.requireID()
            let existingStories = try await place.$stories.query(on: db).all()
            var position = existingStories.count

            for extractedStory in item.stories {
                let duplicate = existingStories.contains {
                    $0.youtubeID == videoID && Slug.make(from: $0.title) == Slug.make(from: extractedStory.title)
                }
                if duplicate { continue }

                let story = Story(
                    placeID: placeID,
                    title: extractedStory.title,
                    body: extractedStory.body,
                    position: position,
                    personalities: extractedStory.personalities ?? []
                )
                story.videoKind = .youtube
                story.youtubeID = videoID
                story.startSeconds = extractedStory.startSeconds
                story.endSeconds = extractedStory.endSeconds
                story.sourceTitle = video.title
                story.sourceChannel = video.channel
                story.sourceURL = video.watchURL
                try await story.save(on: db)
                position += 1
            }
            console.success("  ✓ \(place.name) (\(place.status.rawValue)) – \(item.stories.count) povești")
        }

        console.info("Gata: \(created) locuri noi, \(updated) actualizate, \(skipped) sărite.")
        if !signature.publish, created > 0 {
            console.info("Locurile noi sunt draft. Le vezi cu GET /api/v1/admin/places?status=draft și le publici cu POST …/publish.")
        }
    }
}
