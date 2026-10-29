import Fluent

struct AddStoryThumbnail: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Story.schema).field("thumbnail_url", .string).update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Story.schema).deleteField("thumbnail_url").update()
    }
}
