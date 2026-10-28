import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlacesStore.self) private var store
    @Environment(ProfileStore.self) private var profile
    @Environment(LocationService.self) private var location

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Hartă", systemImage: "map.fill", value: AppTab.map) {
                MapScreen()
            }
            .badge(router.nearbyPlace == nil ? 0 : 1)

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
        }
        .onChange(of: location.location) { _, newLocation in
            guard let newLocation, let place = store.claimNearbyPlace(for: newLocation) else { return }
            profile.markDiscovered(place)
            withAnimation(.spring) { router.nearbyPlace = place }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
        .environment(PlacesStore())
        .environment(ProfileStore())
        .environment(LocationService())
}
