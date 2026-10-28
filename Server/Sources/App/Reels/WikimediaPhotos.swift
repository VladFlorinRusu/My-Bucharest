import Foundation
import Vapor

struct WikimediaPhoto: Sendable {
    var thumbnailURL: String
    var credit: MediaCredit
}

/// Caută fotografii libere de drepturi pe Wikimedia Commons.
/// Politica Wikimedia cere un User-Agent cu date de contact.
struct WikimediaPhotos {
    var client: any Client
    var contact: String

    private var userAgent: String { "MyBucharest/0.1 (\(contact))" }

    func search(_ query: String, limit: Int) async throws -> [WikimediaPhoto] {
        struct Query: Content {
            var action = "query"
            var format = "json"
            var formatversion = 2
            var generator = "search"
            var gsrsearch: String
            var gsrnamespace = 6
            var gsrlimit = 20
            var prop = "imageinfo"
            var iiprop = "url|size|mime|extmetadata"
            var iiurlwidth = 2000
            var iiextmetadatafilter = "Artist|LicenseShortName|LicenseUrl|ObjectName"
        }

        let response = try await client.get("https://commons.wikimedia.org/w/api.php") { req in
            try req.query.encode(Query(gsrsearch: "\(query) filetype:bitmap"))
            req.headers.replaceOrAdd(name: .userAgent, value: userAgent)
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Wikimedia a răspuns cu \(response.status.code).")
        }

        let pages = try response.content.decode(CommonsResponse.self).query?.pages ?? []
        return pages
            .sorted { ($0.index ?? .max) < ($1.index ?? .max) }
            .compactMap(Self.photo(from:))
            .prefix(limit)
            .map { $0 }
    }

    func download(_ photo: WikimediaPhoto, to file: URL) async throws {
        let response = try await client.get(URI(string: photo.thumbnailURL)) { req in
            req.headers.replaceOrAdd(name: .userAgent, value: userAgent)
        }
        guard response.status == .ok, let buffer = response.body else {
            throw Abort(.badGateway, reason: "Nu am putut descărca \(photo.credit.title).")
        }
        try Data(buffer: buffer).write(to: file)
    }

    /// Licențe care permit reutilizare comercială și modificări (crop, zoom).
    static func isAllowedLicense(_ license: String) -> Bool {
        let value = license.lowercased()
        let terms = value.split { !$0.isLetter && !$0.isNumber }
        if terms.contains("nc") || terms.contains("nd") { return false }
        return value.hasPrefix("cc by") || value.hasPrefix("cc0") || value.contains("public domain") || value.hasPrefix("pd")
    }

    private static func photo(from page: CommonsResponse.Page) -> WikimediaPhoto? {
        guard
            let info = page.imageinfo?.first,
            ["image/jpeg", "image/png"].contains(info.mime),
            info.width >= 1_200,
            let license = info.extmetadata?["LicenseShortName"]?.value,
            isAllowedLicense(license)
        else {
            return nil
        }

        let author = stripHTML(info.extmetadata?["Artist"]?.value ?? "")
        let title = stripHTML(info.extmetadata?["ObjectName"]?.value ?? "")
        return WikimediaPhoto(
            thumbnailURL: info.thumburl ?? info.url,
            credit: MediaCredit(
                title: title.isEmpty ? page.title.replacingOccurrences(of: "File:", with: "") : title,
                author: author.isEmpty ? "Autor necunoscut" : author,
                license: license,
                licenseURL: info.extmetadata?["LicenseUrl"]?.value,
                sourceURL: info.descriptionurl
            )
        )
    }

    static func stripHTML(_ html: String) -> String {
        html.replacing(/<[^>]+>/, with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private struct CommonsResponse: Decodable {
    struct Page: Decodable {
        var title: String
        var index: Int?
        var imageinfo: [ImageInfo]?
    }

    struct ImageInfo: Decodable {
        var url: String
        var thumburl: String?
        var width: Int
        var height: Int
        var mime: String
        var descriptionurl: String
        var extmetadata: [String: Metadata]?
    }

    struct Metadata: Decodable {
        var value: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = (try? container.decode(String.self, forKey: .value)) ?? ""
        }

        enum CodingKeys: String, CodingKey { case value }
    }

    struct Query: Decodable {
        var pages: [Page]
    }

    var query: Query?
}
