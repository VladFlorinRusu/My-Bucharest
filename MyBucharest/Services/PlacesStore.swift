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
    /// Locația după care e ordonat feed-ul curent.
    private(set) var feedLocation: CLLocation?

    /// Locurile aflate acum în raza de proximitate.
    private(set) var nearbyPlaceIDs: Set<UUID> = []

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

    /// Serverul întoarce feed-ul ordonat după distanța față de `location`, cele mai apropiate primele.
    func loadFeed(near location: CLLocation?) async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        do {
            feed = try await api.feed(near: location?.coordinate)
            feedLocation = location
            feedErrorMessage = nil
        } catch {
            feedErrorMessage = error.localizedDescription
        }
    }

    func feedNeedsReordering(for location: CLLocation?) -> Bool {
        guard let location else { return false }
        guard let feedLocation else { return true }
        return location.distance(from: feedLocation) >= AppConfig.feedRefreshDistance
    }

    func detail(for id: UUID) async throws -> PlaceDetail {
        if let cached = details[id] { return cached }
        let detail = try await api.place(id: id)
        details[id] = detail
        return detail
    }

    /// Actualizează locurile din raza de proximitate și le întoarce pe cele intrate acum în rază
    /// (încă neanunțate), de la cel mai apropiat.
    func updateProximity(for location: CLLocation) -> [PlaceSummary] {
        var nearby: [(place: PlaceSummary, distance: CLLocationDistance)] = []
        for place in places {
            let distance = place.location.distance(from: location)
            if distance <= AppConfig.proximityRadius {
                nearby.append((place, distance))
            } else if distance > AppConfig.proximityResetRadius {
                announcedPlaceIDs.remove(place.id)
            }
        }

        let ids = Set(nearby.map(\.place.id))
        if ids != nearbyPlaceIDs { nearbyPlaceIDs = ids }

        let entered = nearby
            .filter { !announcedPlaceIDs.contains($0.place.id) }
            .sorted { $0.distance < $1.distance }
            .map(\.place)
        announcedPlaceIDs.formUnion(entered.map(\.id))
        return entered
    }
}
