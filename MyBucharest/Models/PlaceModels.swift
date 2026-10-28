import CoreLocation
import Foundation

enum PlaceCategory: String, Codable, CaseIterable, Hashable {
    case building
    case street
    case monument
    case church
    case park
    case museum
    case memorial
    case other

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlaceCategory(rawValue: raw) ?? .other
    }
}

struct PlaceSummary: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let summary: String
    let category: PlaceCategory
    let latitude: Double
    let longitude: Double
    let imageURL: String?
    let storyCount: Int
    let distanceMeters: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct PlaceDetail: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let summary: String
    let category: PlaceCategory
    let latitude: Double
    let longitude: Double
    let address: String?
    let imageURL: String?
    let stories: [Story]
}

struct Story: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let body: String
    let personalities: [String]
    let video: StoryVideo?
    let source: StorySource?
}

struct StoryVideo: Codable, Hashable {
    enum Kind: String, Codable {
        case hosted
        case youtube
    }

    let kind: Kind
    let url: String?
    let youtubeID: String?
    let startSeconds: Int?
    let endSeconds: Int?
}

struct StorySource: Codable, Hashable {
    let title: String?
    let channel: String?
    let url: String?
}
