import Fluent
import Vapor

struct PlacesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let places = routes.grouped("places")
        places.get(use: self.index)
        places.get(":placeID", use: self.show)
    }

    struct NearbyQuery: Content {
        var lat: Double?
        var lon: Double?
        /// Raza în metri; fără ea se întorc toate locurile, sortate după distanță.
        var radius: Double?
    }

    /// GET /api/v1/places?lat=44.43&lon=26.10&radius=2000
    @Sendable
    func index(req: Request) async throws -> [PlaceSummaryDTO] {
        let query = try req.query.decode(NearbyQuery.self)
        let places = try await Place.query(on: req.db)
            .filter(\.$status == .published)
            .with(\.$stories)
            .all()

        guard let lat = query.lat, let lon = query.lon else {
            return try places.map { try $0.toSummaryDTO() }
        }

        return try places
            .map { place in
                (place, Geo.distance(lat1: lat, lon1: lon, lat2: place.latitude, lon2: place.longitude))
            }
            .filter { query.radius == nil || $0.1 <= query.radius! }
            .sorted { $0.1 < $1.1 }
            .map { try $0.0.toSummaryDTO(distance: $0.1) }
    }

    /// GET /api/v1/places/:placeID
    @Sendable
    func show(req: Request) async throws -> PlaceDetailDTO {
        guard
            let id = req.parameters.get("placeID", as: UUID.self),
            let place = try await Place.find(id, on: req.db),
            place.status == .published
        else {
            throw Abort(.notFound)
        }
        let stories = try await place.$stories.query(on: req.db).sort(\.$position).all()
        return try place.toDetailDTO(stories: stories)
    }
}
