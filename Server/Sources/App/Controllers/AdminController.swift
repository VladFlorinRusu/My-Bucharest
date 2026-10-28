import Fluent
import Vapor

/// Endpoint-uri protejate cu `Authorization: Bearer $ADMIN_TOKEN`.
struct AdminController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let places = routes.grouped("places")
        places.get(use: self.index)
        places.post(use: self.create)
        places.group(":placeID") { place in
            place.post("stories", use: self.addStory)
            place.post("publish", use: self.publish)
            place.post("unpublish", use: self.unpublish)
            place.delete(use: self.delete)
        }
        routes.on(.POST, "videos", body: .collect(maxSize: "150mb"), use: self.uploadVideo)
    }

    struct StatusQuery: Content {
        var status: PublicationStatus?
    }

    /// GET /api/v1/admin/places?status=draft
    @Sendable
    func index(req: Request) async throws -> [PlaceDetailDTO] {
        let filter = try req.query.decode(StatusQuery.self)
        var query = Place.query(on: req.db).with(\.$stories).sort(\.$name)
        if let status = filter.status {
            query = query.filter(\.$status == status)
        }
        return try await query.all().map { place in
            try place.toDetailDTO(stories: place.stories.sorted { $0.position < $1.position })
        }
    }

    /// POST /api/v1/admin/places
    @Sendable
    func create(req: Request) async throws -> PlaceDetailDTO {
        let input = try req.content.decode(PlaceInput.self)
        let place = Place(
            name: input.name,
            summary: input.summary,
            category: input.category,
            latitude: input.latitude,
            longitude: input.longitude,
            address: input.address,
            imageURL: input.imageURL,
            status: input.status ?? .draft
        )

        if try await Place.query(on: req.db).filter(\.$slug == place.slug).first() != nil {
            throw Abort(.conflict, reason: "Există deja un loc cu numele „\(input.name)”.")
        }

        let stories = try await req.db.transaction { db -> [Story] in
            try await place.save(on: db)
            let placeID = try place.requireID()
            var saved: [Story] = []
            for (index, storyInput) in (input.stories ?? []).enumerated() {
                let story = Story(placeID: placeID, title: storyInput.title, body: storyInput.body, position: index)
                story.apply(storyInput)
                try await story.save(on: db)
                saved.append(story)
            }
            return saved
        }
        return try place.toDetailDTO(stories: stories)
    }

    /// POST /api/v1/admin/places/:placeID/stories
    @Sendable
    func addStory(req: Request) async throws -> StoryDTO {
        let place = try await findPlace(req)
        let input = try req.content.decode(StoryInput.self)
        let position = try await place.$stories.query(on: req.db).count()
        let story = Story(placeID: try place.requireID(), title: input.title, body: input.body, position: position)
        story.apply(input)
        try await story.save(on: req.db)
        return try story.toDTO()
    }

    @Sendable
    func publish(req: Request) async throws -> HTTPStatus {
        try await setStatus(.published, req: req)
    }

    @Sendable
    func unpublish(req: Request) async throws -> HTTPStatus {
        try await setStatus(.draft, req: req)
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let place = try await findPlace(req)
        try await req.db.transaction { db in
            try await place.$stories.query(on: db).delete()
            try await place.delete(on: db)
        }
        return .noContent
    }

    struct UploadedVideo: Content {
        var url: String
    }

    /// POST /api/v1/admin/videos  (body = fișierul video brut, Content-Type: video/mp4)
    /// Întoarce calea relativă pe care o pui apoi în `video.url` al unei povești.
    @Sendable
    func uploadVideo(req: Request) async throws -> UploadedVideo {
        let allowed: [String: String] = ["mp4": "mp4", "quicktime": "mov"]
        guard
            let contentType = req.headers.contentType,
            contentType.type == "video",
            let ext = allowed[contentType.subType]
        else {
            throw Abort(.unsupportedMediaType, reason: "Sunt acceptate doar video/mp4 și video/quicktime.")
        }
        guard let buffer = req.body.data, buffer.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "Body gol.")
        }

        let directory = req.application.directory.publicDirectory + "videos/"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString.lowercased()).\(ext)"
        try await req.fileio.writeFile(buffer, at: directory + fileName)
        return UploadedVideo(url: "/videos/\(fileName)")
    }

    // MARK: - Helpers

    private func findPlace(_ req: Request) async throws -> Place {
        guard
            let id = req.parameters.get("placeID", as: UUID.self),
            let place = try await Place.find(id, on: req.db)
        else {
            throw Abort(.notFound)
        }
        return place
    }

    private func setStatus(_ status: PublicationStatus, req: Request) async throws -> HTTPStatus {
        let place = try await findPlace(req)
        place.status = status
        try await place.save(on: req.db)
        return .noContent
    }
}
