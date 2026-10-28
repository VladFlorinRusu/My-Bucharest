import Fluent

struct CreatePlace: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Place.schema)
            .id()
            .field("name", .string, .required)
            .field("slug", .string, .required)
            .field("summary", .string, .required)
            .field("category", .string, .required)
            .field("latitude", .double, .required)
            .field("longitude", .double, .required)
            .field("address", .string)
            .field("image_url", .string)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "slug")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Place.schema).delete()
    }
}
