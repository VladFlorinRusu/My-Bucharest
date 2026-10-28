import Fluent
import Vapor

struct FeedItemDTO: Content {
    var place: PlaceSummaryDTO
    var story: StoryDTO
}

struct FeedController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("feed", use: self.index)
    }

    struct FeedQuery: Content {
        var lat: Double?
        var lon: Double?
        var limit: Int?
    }

    /// GET /api/v1/feed?lat=44.43&lon=26.10&limit=50
    /// Cu locație: întâi poveștile locurilor apropiate. Fără locație: cele mai noi.
    @Sendable
    func index(req: Request) async throws -> [FeedItemDTO] {
        let query = try req.query.decode(FeedQuery.self)
        let limit = min(max(query.limit ?? 50, 1), 200)

        let places = try await Place.query(on: req.db)
            .filter(\.$status == .published)
            .with(\.$stories)
            .all()

        var entries: [(place: Place, story: Story, distance: Double?)] = []
        for place in places {
            let distance = query.lat.flatMap { lat in
                query.lon.map { lon in
                    Geo.distance(lat1: lat, lon1: lon, lat2: place.latitude, lon2: place.longitude)
                }
            }
            for story in place.stories {
                entries.append((place, story, distance))
            }
        }

        entries.sort { lhs, rhs in
            if let l = lhs.distance, let r = rhs.distance, l != r { return l < r }
            if lhs.place.id == rhs.place.id { return lhs.story.position < rhs.story.position }
            return (lhs.story.createdAt ?? .distantPast) > (rhs.story.createdAt ?? .distantPast)
        }

        return try entries.prefix(limit).map { entry in
            FeedItemDTO(
                place: try entry.place.toSummaryDTO(distance: entry.distance),
                story: try entry.story.toDTO()
            )
        }
    }
}
