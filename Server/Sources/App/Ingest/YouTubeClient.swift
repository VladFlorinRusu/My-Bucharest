import Foundation
import Vapor

struct YouTubeVideoInfo: Sendable {
    var id: String
    var title: String?
    var channel: String?
    var description: String?

    var watchURL: String { "https://www.youtube.com/watch?v=\(id)" }
}

enum YouTube {
    /// Acceptă ID-ul simplu sau URL-uri de tip watch, youtu.be, shorts și embed.
    static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidID(trimmed) { return trimmed }
        guard let components = URLComponents(string: trimmed) else { return nil }

        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, isValidID(v) {
            return v
        }
        let segments = components.path.split(separator: "/").map(String.init)
        if components.host?.contains("youtu.be") == true, let first = segments.first, isValidID(first) {
            return first
        }
        if let index = segments.firstIndex(where: { ["shorts", "embed", "live"].contains($0) }),
           segments.indices.contains(index + 1),
           isValidID(segments[index + 1]) {
            return segments[index + 1]
        }
        return nil
    }

    static func isValidID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Metadate prin YouTube Data API v3 (necesită YOUTUBE_API_KEY).
    static func fetchInfo(id: String, apiKey: String, client: any Client) async throws -> YouTubeVideoInfo {
        struct Query: Content {
            var part = "snippet"
            var id: String
            var key: String
        }
        struct Response: Content {
            struct Item: Content {
                struct Snippet: Content {
                    var title: String
                    var channelTitle: String
                    var description: String
                }
                var snippet: Snippet
            }
            var items: [Item]
        }

        let response = try await client.get("https://www.googleapis.com/youtube/v3/videos") { req in
            try req.query.encode(Query(id: id, key: apiKey))
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "YouTube API a răspuns cu \(response.status.code).")
        }
        let snippet = try response.content.decode(Response.self).items.first?.snippet
        return YouTubeVideoInfo(id: id, title: snippet?.title, channel: snippet?.channelTitle, description: snippet?.description)
    }
}
