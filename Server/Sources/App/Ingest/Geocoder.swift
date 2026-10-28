import Foundation
import Vapor

struct GeocodedPoint: Sendable {
    var latitude: Double
    var longitude: Double
    var displayName: String
}

/// Geocodare prin OpenStreetMap Nominatim, limitată la zona Bucureștiului.
/// Politica Nominatim cere User-Agent identificabil și maximum 1 cerere/secundă.
struct Geocoder {
    var client: any Client
    var contact: String

    func locate(_ query: String) async throws -> GeocodedPoint? {
        struct Query: Content {
            var q: String
            var format = "jsonv2"
            var limit = 1
            var countrycodes = "ro"
            var viewbox = "25.96,44.54,26.25,44.33"
            var bounded = 1
        }
        struct Result: Content {
            var lat: String
            var lon: String
            var display_name: String
        }

        let response = try await client.get("https://nominatim.openstreetmap.org/search") { req in
            try req.query.encode(Query(q: query))
            req.headers.replaceOrAdd(name: .userAgent, value: "MyBucharest/0.1 (\(contact))")
        }
        guard response.status == .ok else { return nil }
        guard
            let first = try response.content.decode([Result].self).first,
            let lat = Double(first.lat),
            let lon = Double(first.lon)
        else {
            return nil
        }
        return GeocodedPoint(latitude: lat, longitude: lon, displayName: first.display_name)
    }
}
