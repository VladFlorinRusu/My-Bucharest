import Fluent

struct CreateStory: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Story.schema)
            .id()
            .field("place_id", .uuid, .required, .references(Place.schema, "id", onDelete: .cascade))
            .field("title", .string, .required)
            .field("body", .string, .required)
            .field("position", .int, .required)
            .field("personalities", .array(of: .string), .required)
            .field("video_kind", .string)
            .field("video_url", .string)
            .field("youtube_id", .string)
            .field("start_seconds", .int)
            .field("end_seconds", .int)
            .field("source_title", .string)
            .field("source_channel", .string)
            .field("source_url", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Story.schema).delete()
    }
}
