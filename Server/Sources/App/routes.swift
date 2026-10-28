import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in "ok" }

    let api = app.grouped("api", "v1")
    try api.register(collection: PlacesController())
    try api.register(collection: FeedController())
    try api.grouped("admin")
        .grouped(AdminTokenMiddleware())
        .register(collection: AdminController())
}
