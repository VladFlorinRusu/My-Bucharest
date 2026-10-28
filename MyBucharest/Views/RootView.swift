import AudioToolbox
import CoreLocation
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlacesStore.self) private var store
    @Environment(ProfileStore.self) private var profile
    @Environment(LocationService.self) private var location
    @Environment(GeofenceService.self) private var geofence
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppConfig.proximityRadiusKey) private var proximityRadius = AppConfig.defaultProximityRadius

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Hartă", systemImage: "map.fill", value: AppTab.map) {
                MapScreen()
            }
            .badge(store.nearbyPlaceIDs.count)

            Tab("Pentru tine", systemImage: "play.rectangle.on.rectangle.fill", value: AppTab.forYou) {
                ForYouView()
            }

            Tab("Profil", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .task {
            location.start()
            await store.loadPlaces()
            checkProximity(location.location)
        }
        .onChange(of: location.location) { _, newLocation in
            checkProximity(newLocation)
            if let newLocation { geofence.locationChanged(newLocation) }
        }
        .onChange(of: proximityRadius) {
            checkProximity(location.location)
            if let current = location.location { geofence.locationChanged(current, force: true) }
        }
        .onChange(of: store.places) { _, places in
            geofence.cache(places)
            if let current = location.location { geofence.locationChanged(current, force: true) }
            openPlaceFromNotification()
        }
        .onChange(of: geofence.openedPlaceID, initial: true) {
            openPlaceFromNotification()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await geofence.refreshStatus() }
        }
    }

    /// Vibrează și afișează bannerul când intri în raza unor locuri noi.
    private func checkProximity(_ currentLocation: CLLocation?) {
        guard let currentLocation else { return }
        let entered = store.updateProximity(for: currentLocation)
        guard let closest = entered.first else { return }

        entered.forEach(profile.markDiscovered)
        withAnimation(.spring) { router.nearbyPlace = closest }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    /// La pornire din notificare, locurile pot să nu fie încă încărcate; reîncercăm când sosesc.
    private func openPlaceFromNotification() {
        guard
            let id = geofence.openedPlaceID,
            let place = store.places.first(where: { $0.id == id })
        else { return }
        geofence.openedPlaceID = nil
        router.open(place)
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .environment(PlacesStore())
        .environment(ProfileStore())
        .environment(LocationService())
        .environment(GeofenceService.shared)
}
