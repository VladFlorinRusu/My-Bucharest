import Fluent

struct CreateMediaSources: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(MediaSource.schema)
            .id()
            .field("kind", .string, .required)
            .field("external_id", .string, .required)
            .field("url", .string, .required)
            .field("title", .string, .required)
            .field("channel", .string)
            .field("duration_seconds", .double)
            .field("transcript_origin", .string, .required)
            .field("language", .string)
            .field("summary", .string)
            .field("created_at", .datetime)
            .unique(on: "kind", "external_id")
            .create()

        try await database.schema(TranscriptSegment.schema)
            .id()
            .field("source_id", .uuid, .required, .references(MediaSource.schema, "id", onDelete: .cascade))
            .field("position", .int, .required)
            .field("start_seconds", .double, .required)
            .field("end_seconds", .double, .required)
            .field("text", .string, .required)
            .create()

        try await database.schema(Fact.schema)
            .id()
            .field("source_id", .uuid, .required, .references(MediaSource.schema, "id", onDelete: .cascade))
            .field("statement", .string, .required)
            .field("kind", .string, .required)
            .field("start_seconds", .int, .required)
            .field("end_seconds", .int)
            .field("places", .array(of: .string), .required)
            .field("people", .array(of: .string), .required)
            .field("dates", .array(of: .string), .required)
            .field("topics", .array(of: .string), .required)
            .field("importance", .int, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Fact.schema).delete()
        try await database.schema(TranscriptSegment.schema).delete()
        try await database.schema(MediaSource.schema).delete()
    }
}
