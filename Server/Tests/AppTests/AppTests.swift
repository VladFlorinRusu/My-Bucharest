@testable import App
import Fluent
import Testing
import VaporTesting

@Suite("BucharestServer", .serialized)
struct AppTests {
    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Locurile publicate sunt sortate după distanță și filtrate după rază")
    func nearbyPlaces() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "api/v1/places?lat=44.4314&lon=26.0978&radius=500") { res async throws in
                #expect(res.status == .ok)
                let places = try res.content.decode([PlaceSummaryDTO].self)
                #expect(places.first?.name == "Biserica Stavropoleos")
                #expect(!places.contains { $0.name == "Arcul de Triumf" })
                #expect(places.allSatisfy { ($0.distanceMeters ?? .infinity) <= 500 })
            }
        }
    }

    @Test("Detaliul unui loc include poveștile")
    func placeDetail() async throws {
        try await withApp { app in
            let place = try #require(try await Place.query(on: app.db).filter(\.$slug == "ateneul-roman").first())
            try await app.testing().test(.GET, "api/v1/places/\(try place.requireID())") { res async throws in
                #expect(res.status == .ok)
                let detail = try res.content.decode(PlaceDetailDTO.self)
                #expect(detail.stories.count == 1)
            }
        }
    }

    @Test("Feed-ul pune întâi poveștile din apropiere și respectă limita")
    func feed() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "api/v1/feed?lat=44.4672&lon=26.0781&limit=3") { res async throws in
                #expect(res.status == .ok)
                let items = try res.content.decode([FeedItemDTO].self)
                #expect(items.count == 3)
                #expect(items.first?.place.name == "Arcul de Triumf")
            }
        }
    }

    @Test("Vocea și atribuirile fotografiilor ajung în API")
    func storyMedia() async throws {
        try await withApp { app in
            let place = try #require(try await Place.query(on: app.db).filter(\.$slug == "ateneul-roman").first())
            let story = try #require(try await place.$stories.query(on: app.db).first())
            story.audioURL = "/audio/test.m4a"
            story.aiVoice = true
            story.mediaCredits = [MediaCredit(title: "Ateneul", author: "Ana", license: "CC BY-SA 4.0",
                                              licenseURL: nil, sourceURL: "https://commons.wikimedia.org/wiki/File:X.jpg")]
            try await story.save(on: app.db)

            try await app.testing().test(.GET, "api/v1/places/\(try place.requireID())") { res async throws in
                let dto = try #require(try res.content.decode(PlaceDetailDTO.self).stories.first)
                #expect(dto.audioURL == "/audio/test.m4a")
                #expect(dto.aiVoice)
                #expect(dto.credits.first?.author == "Ana")
            }
        }
    }

    @Test("Doar licențele care permit uz comercial și modificări")
    func licenses() {
        #expect(WikimediaPhotos.isAllowedLicense("CC BY-SA 4.0"))
        #expect(WikimediaPhotos.isAllowedLicense("CC0"))
        #expect(WikimediaPhotos.isAllowedLicense("Public domain"))
        #expect(!WikimediaPhotos.isAllowedLicense("CC BY-NC-SA 3.0"))
        #expect(!WikimediaPhotos.isAllowedLicense("CC BY-ND 2.0"))
    }

    @Test("Segmentele cu fade acoperă exact durata vocii")
    func reelTiming() {
        let total = 20.0, count = 4
        let segment = ReelRenderer.segmentDuration(total: total, count: count)
        let offsets = ReelRenderer.transitionOffsets(segment: segment, count: count)
        #expect(offsets.count == 3)
        #expect(abs((offsets.last! + segment) - total) < 0.001)
        #expect(ReelRenderer.photoCount(available: 5, duration: 8) == 2)
        #expect(ReelRenderer.photoCount(available: 5, duration: 2) == 1)
    }

    @Test("Subtitrările json3 devin replici curate, apoi blocuri de ~20 s")
    func json3Parsing() throws {
        let json = """
        {"events":[
          {"tStartMs":0,"dDurationMs":4000,"segs":[{"utf8":"[Muzică]"}]},
          {"tStartMs":4000,"dDurationMs":5000,"segs":[{"utf8":"Ateneul a fost"},{"utf8":" ridicat"}]},
          {"tStartMs":9000,"dDurationMs":10,"aAppend":1,"segs":[{"utf8":"\\n"}]},
          {"tStartMs":9000,"dDurationMs":16000,"segs":[{"utf8":"din donații."}]},
          {"tStartMs":25000,"dDurationMs":3000,"segs":[{"utf8":"Altă idee"}]}
        ]}
        """
        let cues = try TranscriptProcessing.parseJSON3(Data(json.utf8))
        #expect(cues.map(\.text) == ["Ateneul a fost ridicat", "din donații.", "Altă idee"])

        let blocks = TranscriptProcessing.mergeIntoBlocks(cues)
        #expect(blocks.count == 2)
        #expect(blocks[0] == TranscriptBlock(start: 4, end: 25, text: "Ateneul a fost ridicat din donații."))
    }

    @Test("Ieșirea Whisper se parsează cu momentele corecte")
    func whisperParsing() throws {
        let json = #"{"transcription":[{"offsets":{"from":1500,"to":6200},"text":" Bună ziua."}]}"#
        let cues = try TranscriptProcessing.parseWhisperJSON(Data(json.utf8))
        #expect(cues == [TranscriptBlock(start: 1.5, end: 6.2, text: "Bună ziua.")])
    }

    @Test("Se aleg subtitrările în română, fără traduceri automate")
    func captionSelection() {
        typealias Meta = YouTubeMetadata
        let format = [Meta.CaptionFormat(ext: "json3")]
        var meta = Meta(id: "x", title: "t", subtitles: ["ro": format], automaticCaptions: ["ro-orig": format])
        #expect(YouTubeTranscriber.pickCaptions(meta, language: "ro")?.origin == .manualCaptions)

        meta.subtitles = ["live_chat": format]
        #expect(YouTubeTranscriber.pickCaptions(meta, language: "ro")?.key == "ro-orig")

        // Clip în engleză: pista „ro” e o traducere automată și trebuie ignorată.
        meta = Meta(id: "x", title: "t", language: "en", automaticCaptions: ["en-orig": format, "ro": format])
        #expect(YouTubeTranscriber.pickCaptions(meta, language: "ro") == nil)
    }

    @Test("Bucățile pentru LLM nu depășesc limita și păstrează ordinea")
    func chunking() {
        let blocks = (0..<10).map { TranscriptBlock(start: Double($0 * 20), end: Double($0 * 20 + 20), text: String(repeating: "a", count: 300)) }
        let chunks = TranscriptProcessing.chunks(blocks, maxCharacters: 1_000)
        #expect(chunks.map(\.count) == [3, 3, 3, 1])
        #expect(chunks.flatMap { $0 } == blocks)
    }

    @Test("Timecode și extragerea anului")
    func timecode() {
        #expect(Timecode.format(754) == "12:34")
        #expect(Timecode.format(3_725) == "1:02:05")
        #expect(Timecode.firstYear(in: "1930-1940") == 1930)
        #expect(Timecode.firstYear(in: "perioada interbelică") == nil)
    }

    @Test("Rutele de admin cer token")
    func adminRequiresToken() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "api/v1/admin/places") { res async throws in
                #expect(res.status == .serviceUnavailable || res.status == .unauthorized)
            }
        }
    }

    @Test("Extragerea ID-ului YouTube din URL-uri")
    func youtubeIDs() {
        #expect(YouTube.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTube.videoID(from: "https://youtu.be/dQw4w9WgXcQ?t=10") == "dQw4w9WgXcQ")
        #expect(YouTube.videoID(from: "https://youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTube.videoID(from: "nu-e-un-id") == nil)
    }

    @Test("Slug fără diacritice")
    func slug() {
        #expect(Slug.make(from: "Ateneul Român") == "ateneul-roman")
        #expect(Slug.make(from: "Caru' cu Bere") == "caru-cu-bere")
    }
}
