import CoreLocation
import Foundation
import Observation

@Observable
final class PlacesStore {
    private(set) var places: [PlaceSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var feed: [FeedItem] = []
    private(set) var isLoadingFeed = false
    private(set) var feedErrorMessage: String?

    let api: APIClient
    private var details: [UUID: PlaceDetail] = [:]
    private var announcedPlaceIDs: Set<UUID> = []

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func loadPlaces() async {
        isLoading = true
        defer { isLoading = false }
        do {
            places = try await api.places()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFeed(near coordinate: CLLocationCoordinate2D?) async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            feed = try await api.feed(near: coordinate)
            feedErrorMessage = nil
        } catch {
            feedErrorMessage = error.localizedDescription
        }
    }

    func detail(for id: UUID) async throws -> PlaceDetail {
        if let cached = details[id] { return cached }
        let detail = try await api.place(id: id)
        details[id] = detail
        return detail
    }

    /// Cel mai apropiat loc aflat în raza de proximitate, anunțat o singură dată pe sesiune.
    func claimNearbyPlace(for location: CLLocation) -> PlaceSummary? {
        let nearby = places
            .filter { !announcedPlaceIDs.contains($0.id) }
            .map { ($0, $0.location.distance(from: location)) }
            .filter { $0.1 <= AppConfig.proximityRadius }
            .min { $0.1 < $1.1 }?
            .0
        if let nearby { announcedPlaceIDs.insert(nearby.id) }
        return nearby
    }
}
