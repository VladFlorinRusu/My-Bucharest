import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(PlacesStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location
    @AppStorage(AppConfig.proximityRadiusKey) private var proximityRadius = AppConfig.defaultProximityRadius

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: AppConfig.bucharestCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
    )
    @State private var selectedPlaceID: UUID?
    @State private var presentedPlace: PlaceSummary?
    @State private var categoryFilter: PlaceCategory?

    private var visiblePlaces: [PlaceSummary] {
        guard let categoryFilter else { return store.places }
        return store.places.filter { $0.category == categoryFilter }
    }

    private var availableCategories: [PlaceCategory] {
        let present = Set(store.places.map(\.category))
        return PlaceCategory.allCases.filter(present.contains)
    }

    var body: some View {
        Map(position: $camera, selection: $selectedPlaceID) {
            if let userCoordinate = location.location?.coordinate {
                MapCircle(center: userCoordinate, radius: proximityRadius)
                    .foregroundStyle(.blue.opacity(0.08))
                    .stroke(.blue.opacity(0.35), lineWidth: 1)
            }
            UserAnnotation()
            ForEach(visiblePlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    PlacePin(
                        category: place.category,
                        isHighlighted: router.nearbyPlace?.id == place.id,
                        isNearby: store.nearbyPlaceIDs.contains(place.id)
                    )
                }
                .tag(place.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaInset(edge: .top) {
            if availableCategories.count > 1 {
                CategoryFilterBar(categories: availableCategories, selection: $categoryFilter)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let nearbyPlace = router.nearbyPlace {
                NearbyBanner(place: nearbyPlace, othersNearby: store.nearbyPlaceIDs.subtracting([nearbyPlace.id]).count) {
                    presentedPlace = nearbyPlace
                    router.nearbyPlace = nil
                } onDismiss: {
                    withAnimation { router.nearbyPlace = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if store.places.isEmpty {
                statusOverlay
            }
        }
        .onChange(of: selectedPlaceID) { _, id in
            guard let id, let place = store.places.first(where: { $0.id == id }) else { return }
            presentedPlace = place
            selectedPlaceID = nil
        }
        .onChange(of: router.nearbyPlace?.id) { _, id in
            // La intrarea în raza unui loc nou, arătăm zona din jurul tău cu locurile care pulsează.
            guard id != nil, let userCoordinate = location.location?.coordinate else { return }
            let span = min(proximityRadius * 3.5, 25_000)
            withAnimation(.smooth) {
                camera = .region(MKCoordinateRegion(
                    center: userCoordinate,
                    latitudinalMeters: span,
                    longitudinalMeters: span
                ))
            }
        }
        .onChange(of: router.placeToOpen, initial: true) { _, place in
            guard let place else { return }
            presentedPlace = place
            router.placeToOpen = nil
        }
        .onChange(of: router.mapFocus, initial: true) { _, focus in
            guard let place = focus?.place else { return }
            categoryFilter = nil
            withAnimation(.smooth) {
                camera = .region(MKCoordinateRegion(
                    center: place.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                ))
            }
        }
        .fullScreenCover(item: $presentedPlace) { place in
            PlaceStoriesView(place: place)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if store.isLoading {
            ProgressView("Se încarcă locurile…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else if let error = store.errorMessage {
            ContentUnavailableView {
                Label("Nu mă pot conecta la server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Reîncearcă") { Task { await store.loadPlaces() } }
                    .buttonStyle(.borderedProminent)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(32)
        }
    }
}

private struct CategoryFilterBar: View {
    let categories: [PlaceCategory]
    @Binding var selection: PlaceCategory?

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: "Toate", symbol: "map.fill", color: .accentColor, isSelected: selection == nil) {
                        selection = nil
                    }
                    ForEach(categories, id: \.self) { category in
                        chip(title: category.title, symbol: category.symbol, color: category.color,
                             isSelected: selection == category) {
                            selection = selection == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, symbol: String, color: Color, isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .glassEffect(isSelected ? .regular.tint(color) : .regular, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct NearbyBanner: View {
    let place: PlaceSummary
    var othersNearby = 0
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlacePin(category: place.category, isNearby: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ești lângă")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(place.name)
                    .font(.headline)
                    .lineLimit(1)
                if othersNearby > 0 {
                    Text(othersNearby == 1 ? "și încă un loc în apropiere" : "și încă \(othersNearby) locuri în apropiere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Vezi", action: onOpen)
                .buttonStyle(.borderedProminent)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Închide")
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

#Preview {
    MapScreen()
        .environment(PlacesStore())
        .environment(AppRouter())
        .environment(LocationService())
}
