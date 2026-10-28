import Foundation
import Observation

enum AppTab: Hashable {
    case map
    case forYou
    case profile
}

/// Starea de navigare partajată între tab-uri.
@Observable
final class AppRouter {
    struct MapFocus: Equatable {
        let id = UUID()
        let place: PlaceSummary
    }

    var selectedTab: AppTab = .map
    /// Locul lângă care tocmai a ajuns utilizatorul; afișat ca banner pe hartă.
    var nearbyPlace: PlaceSummary?
    private(set) var mapFocus: MapFocus?

    func showOnMap(_ place: PlaceSummary) {
        mapFocus = MapFocus(place: place)
        selectedTab = .map
    }
}
