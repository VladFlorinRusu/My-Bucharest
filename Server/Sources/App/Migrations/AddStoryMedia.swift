import Fluent

struct AddStoryMedia: AsyncMigration {
    // SQLite acceptă o singură coloană per ALTER TABLE.
    private let fields: [(FieldKey, DatabaseSchema.DataType)] = [
        ("audio_url", .string),
        ("ai_voice", .bool),
        ("media_credits", .json),
    ]

    func prepare(on database: any Database) async throws {
        for (key, type) in fields {
            try await database.schema(Story.schema).field(key, type).update()
        }
    }

    func revert(on database: any Database) async throws {
        for (key, _) in fields.reversed() {
            try await database.schema(Story.schema).deleteField(key).update()
        }
    }
}
