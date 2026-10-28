import Fluent

struct AddStoryKind: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Story.schema).field("story_kind", .string).update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Story.schema).deleteField("story_kind").update()
    }
}
