import Foundation
import Observation

struct DiscoveredPlace: Codable, Identifiable, Hashable {
    let place: PlaceSummary
    let date: Date

    var id: UUID { place.id }
}

/// Progresul local al utilizatorului: povești salvate și locuri descoperite pe teren.
@Observable
final class ProfileStore {
    private(set) var savedStories: [FeedItem] = []
    private(set) var discoveredPlaces: [DiscoveredPlace] = []

    private let defaults: UserDefaults
    private static let savedKey = "profile.savedStories"
    private static let discoveredKey = "profile.discoveredPlaces"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedStories = Self.read([FeedItem].self, key: Self.savedKey, from: defaults) ?? []
        discoveredPlaces = Self.read([DiscoveredPlace].self, key: Self.discoveredKey, from: defaults) ?? []
    }

    func isSaved(_ storyID: UUID) -> Bool {
        savedStories.contains { $0.id == storyID }
    }

    func toggleSave(_ item: FeedItem) {
        if let index = savedStories.firstIndex(where: { $0.id == item.id }) {
            savedStories.remove(at: index)
        } else {
            savedStories.insert(item, at: 0)
        }
        write(savedStories, key: Self.savedKey)
    }

    func removeSaved(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            savedStories.remove(at: index)
        }
        write(savedStories, key: Self.savedKey)
    }

    func markDiscovered(_ place: PlaceSummary) {
        guard !discoveredPlaces.contains(where: { $0.id == place.id }) else { return }
        discoveredPlaces.insert(DiscoveredPlace(place: place, date: .now), at: 0)
        write(discoveredPlaces, key: Self.discoveredKey)
    }

    func reset() {
        savedStories = []
        discoveredPlaces = []
        defaults.removeObject(forKey: Self.savedKey)
        defaults.removeObject(forKey: Self.discoveredKey)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
