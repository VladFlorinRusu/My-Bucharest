import CoreLocation
import Foundation

struct APIClient {
    var baseURL: URL = AppConfig.apiBaseURL
    var session: URLSession = .shared

    enum APIError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "Serverul a răspuns cu eroarea \(code)."
            }
        }
    }

    func places(near coordinate: CLLocationCoordinate2D? = nil) async throws -> [PlaceSummary] {
        try await get("api/v1/places", query: locationQuery(coordinate))
    }

    func feed(near coordinate: CLLocationCoordinate2D? = nil) async throws -> [FeedItem] {
        try await get("api/v1/feed", query: locationQuery(coordinate))
    }

    func place(id: UUID) async throws -> PlaceDetail {
        try await get("api/v1/places/\(id.uuidString)")
    }

    /// Transformă căile relative primite de la server (ex. "/videos/x.mp4") în URL-uri absolute.
    func resolve(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil { return url }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private func locationQuery(_ coordinate: CLLocationCoordinate2D?) -> [URLQueryItem] {
        guard let coordinate else { return [] }
        return [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
        ]
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
