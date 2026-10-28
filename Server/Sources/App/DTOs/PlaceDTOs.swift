import Foundation
import Vapor

struct VideoDTO: Content {
    var kind: VideoKind
    var url: String?
    var youtubeID: String?
    var startSeconds: Int?
    var endSeconds: Int?
}

struct SourceDTO: Content {
    var title: String?
    var channel: String?
    var url: String?
}

struct StoryDTO: Content {
    var id: UUID
    var title: String
    var body: String
    var personalities: [String]
    var video: VideoDTO?
    var source: SourceDTO?
}

struct PlaceSummaryDTO: Content {
    var id: UUID
    var name: String
    var summary: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var imageURL: String?
    var storyCount: Int
    var distanceMeters: Double?
}

struct PlaceDetailDTO: Content {
    var id: UUID
    var name: String
    var summary: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var address: String?
    var imageURL: String?
    var status: PublicationStatus
    var stories: [StoryDTO]
}

// MARK: - Input (admin)

struct StoryInput: Content {
    var title: String
    var body: String
    var personalities: [String]?
    var video: VideoDTO?
    var source: SourceDTO?
}

struct PlaceInput: Content {
    var name: String
    var summary: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var address: String?
    var imageURL: String?
    var status: PublicationStatus?
    var stories: [StoryInput]?
}

// MARK: - Mapping

extension Story {
    func toDTO() throws -> StoryDTO {
        let video = videoKind.map {
            VideoDTO(kind: $0, url: videoURL, youtubeID: youtubeID, startSeconds: startSeconds, endSeconds: endSeconds)
        }
        let hasSource = sourceTitle != nil || sourceChannel != nil || sourceURL != nil
        return StoryDTO(
            id: try requireID(),
            title: title,
            body: body,
            personalities: personalities,
            video: video,
            source: hasSource ? SourceDTO(title: sourceTitle, channel: sourceChannel, url: sourceURL) : nil
        )
    }

    func apply(_ input: StoryInput) {
        title = input.title
        body = input.body
        personalities = input.personalities ?? []
        videoKind = input.video?.kind
        videoURL = input.video?.url
        youtubeID = input.video?.youtubeID
        startSeconds = input.video?.startSeconds
        endSeconds = input.video?.endSeconds
        sourceTitle = input.source?.title
        sourceChannel = input.source?.channel
        sourceURL = input.source?.url
    }
}

extension Place {
    func toSummaryDTO(distance: Double? = nil) throws -> PlaceSummaryDTO {
        PlaceSummaryDTO(
            id: try requireID(),
            name: name,
            summary: summary,
            category: category,
            latitude: latitude,
            longitude: longitude,
            imageURL: imageURL,
            storyCount: $stories.value?.count ?? 0,
            distanceMeters: distance
        )
    }

    func toDetailDTO(stories: [Story]) throws -> PlaceDetailDTO {
        PlaceDetailDTO(
            id: try requireID(),
            name: name,
            summary: summary,
            category: category,
            latitude: latitude,
            longitude: longitude,
            address: address,
            imageURL: imageURL,
            status: status,
            stories: try stories.map { try $0.toDTO() }
        )
    }
}
