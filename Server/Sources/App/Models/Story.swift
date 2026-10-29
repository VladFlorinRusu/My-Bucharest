import Fluent
import Foundation

enum VideoKind: String, Codable, Sendable {
    /// MP4/HLS servit de serverul nostru (conținut propriu sau licențiat).
    case hosted
    /// Embed prin playerul oficial YouTube, cu interval start/end.
    case youtube
}

/// Ce fel de poveste e: aplicația le grupează și le filtrează după tip.
enum StoryKind: String, Codable, Sendable, CaseIterable {
    case history
    case curiosity
    case gossip
    case etymology
    case food
    case legend
    case person
}

/// Atribuirea unei imagini folosite într-un reel (cerută de licențele Creative Commons).
struct MediaCredit: Codable, Sendable, Equatable {
    var title: String
    var author: String
    var license: String
    var licenseURL: String?
    var sourceURL: String
}

final class Story: Model, @unchecked Sendable {
    static let schema = "stories"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "place_id")
    var place: Place

    @Field(key: "title")
    var title: String

    @Field(key: "body")
    var body: String

    @Field(key: "position")
    var position: Int

    @Field(key: "personalities")
    var personalities: [String]

    @OptionalField(key: "video_kind")
    var videoKind: VideoKind?

    @OptionalField(key: "video_url")
    var videoURL: String?

    @OptionalField(key: "youtube_id")
    var youtubeID: String?

    @OptionalField(key: "start_seconds")
    var startSeconds: Int?

    @OptionalField(key: "end_seconds")
    var endSeconds: Int?

    @OptionalField(key: "source_title")
    var sourceTitle: String?

    @OptionalField(key: "source_channel")
    var sourceChannel: String?

    @OptionalField(key: "source_url")
    var sourceURL: String?

    @OptionalField(key: "audio_url")
    var audioURL: String?

    @OptionalField(key: "ai_voice")
    var aiVoice: Bool?

    @OptionalField(key: "media_credits")
    var mediaCredits: [MediaCredit]?

    @OptionalField(key: "story_kind")
    var kind: StoryKind?

    /// Miniatura reel-ului generat (Public/thumbnails); pentru YouTube se folosește miniatura clipului.
    @OptionalField(key: "thumbnail_url")
    var thumbnailURL: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        placeID: Place.IDValue,
        title: String,
        body: String,
        position: Int,
        personalities: [String] = []
    ) {
        self.id = id
        self.$place.id = placeID
        self.title = title
        self.body = body
        self.position = position
        self.personalities = personalities
    }
}
