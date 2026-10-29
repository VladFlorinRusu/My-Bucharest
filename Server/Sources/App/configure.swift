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
    app.migrations.add(AddStoryMedia())
    app.migrations.add(AddStoryKind())
    app.migrations.add(AddStoryThumbnail())
    app.migrations.add(SeedBucharestPlaces())
    app.migrations.add(CreateMediaSources())

    app.asyncCommands.use(IngestCommand(), as: "ingest")
    app.asyncCommands.use(MakeReelCommand(), as: "make-reel")
    app.asyncCommands.use(AnalyzeCommand(), as: "analyze")
    app.asyncCommands.use(ImportStoriesCommand(), as: "import-stories")

    if app.environment != .testing {
        try await app.autoMigrate()
    }

    try routes(app)
}
