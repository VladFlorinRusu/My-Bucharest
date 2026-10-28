import Fluent
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let path = Environment.get("DATABASE_PATH") ?? "db.sqlite"
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    app.migrations.add(CreatePlace())
    app.migrations.add(CreateStory())
    app.migrations.add(SeedBucharestPlaces())

    app.asyncCommands.use(IngestCommand(), as: "ingest")

    if app.environment != .testing {
        try await app.autoMigrate()
    }

    try routes(app)
}
