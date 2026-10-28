import Fluent
import Foundation

enum PlaceCategory: String, Codable, Sendable, CaseIterable {
    case building
    case street
    case monument
    case church
    case park
    case museum
    case memorial
    case other
}

enum PublicationStatus: String, Codable, Sendable {
    case draft
    case published
}

final class Place: Model, @unchecked Sendable {
    static let schema = "places"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "slug")
    var slug: String

    @Field(key: "summary")
    var summary: String

    @Field(key: "category")
    var category: PlaceCategory

    @Field(key: "latitude")
    var latitude: Double

    @Field(key: "longitude")
    var longitude: Double

    @OptionalField(key: "address")
    var address: String?

    @OptionalField(key: "image_url")
    var imageURL: String?

    @Field(key: "status")
    var status: PublicationStatus

    @Children(for: \.$place)
    var stories: [Story]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        summary: String,
        category: PlaceCategory,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        imageURL: String? = nil,
        status: PublicationStatus = .draft
    ) {
        self.id = id
        self.name = name
        self.slug = Slug.make(from: name)
        self.summary = summary
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.imageURL = imageURL
        self.status = status
    }
}
