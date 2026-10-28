import Fluent
import Foundation

enum TranscriptOrigin: String, Codable, Sendable {
    case manualCaptions = "manual_captions"
    case autoCaptions = "auto_captions"
    case whisper

    var label: String {
        switch self {
        case .manualCaptions: "subtitrări scrise de autor"
        case .autoCaptions: "subtitrări automate YouTube"
        case .whisper: "transcriere Whisper din audio"
        }
    }
}

/// Un clip sau episod de podcast analizat.
final class MediaSource: Model, @unchecked Sendable {
    static let schema = "sources"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "kind")
    var kind: String

    @Field(key: "external_id")
    var externalID: String

    @Field(key: "url")
    var url: String

    @Field(key: "title")
    var title: String

    @OptionalField(key: "channel")
    var channel: String?

    @OptionalField(key: "duration_seconds")
    var durationSeconds: Double?

    @Field(key: "transcript_origin")
    var transcriptOrigin: TranscriptOrigin

    @OptionalField(key: "language")
    var language: String?

    @OptionalField(key: "summary")
    var summary: String?

    @Children(for: \.$source)
    var segments: [TranscriptSegment]

    @Children(for: \.$source)
    var facts: [Fact]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}
}

final class TranscriptSegment: Model, @unchecked Sendable {
    static let schema = "transcript_segments"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "source_id")
    var source: MediaSource

    @Field(key: "position")
    var position: Int

    @Field(key: "start_seconds")
    var startSeconds: Double

    @Field(key: "end_seconds")
    var endSeconds: Double

    @Field(key: "text")
    var text: String

    init() {}

    init(sourceID: UUID, position: Int, block: TranscriptBlock) {
        self.$source.id = sourceID
        self.position = position
        self.startSeconds = block.start
        self.endSeconds = block.end
        self.text = block.text
    }
}

enum FactKind: String, Codable, Sendable {
    case event
    case fact
    case anecdote
    case opinion
}

/// O informație extrasă din transcript, etichetată și legată de momentul din clip.
final class Fact: Model, @unchecked Sendable {
    static let schema = "facts"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "source_id")
    var source: MediaSource

    @Field(key: "statement")
    var statement: String

    @Field(key: "kind")
    var kind: FactKind

    @Field(key: "start_seconds")
    var startSeconds: Int

    @OptionalField(key: "end_seconds")
    var endSeconds: Int?

    @Field(key: "places")
    var places: [String]

    @Field(key: "people")
    var people: [String]

    @Field(key: "dates")
    var dates: [String]

    @Field(key: "topics")
    var topics: [String]

    /// 3 = esențial, 2 = interesant, 1 = detaliu.
    @Field(key: "importance")
    var importance: Int

    init() {}
}
