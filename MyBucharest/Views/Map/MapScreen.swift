import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(PlacesStore.self) private var store
    @Environment(LocationService.self) private var location

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: AppConfig.bucharestCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
    )
    @State private var selectedPlaceID: UUID?
    @State private var presentedPlace: PlaceSummary?
    @State private var nearbyPlace: PlaceSummary?
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
            UserAnnotation()
            ForEach(visiblePlaces) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    PlacePin(category: place.category, isHighlighted: nearbyPlace?.id == place.id)
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
            if let nearbyPlace {
                NearbyBanner(place: nearbyPlace) {
                    presentedPlace = nearbyPlace
                    self.nearbyPlace = nil
                } onDismiss: {
                    withAnimation { self.nearbyPlace = nil }
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
        .onChange(of: location.location) { _, newLocation in
            guard let newLocation, presentedPlace == nil,
                  let place = store.claimNearbyPlace(for: newLocation) else { return }
            withAnimation(.spring) { nearbyPlace = place }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .fullScreenCover(item: $presentedPlace) { place in
            PlaceStoriesView(place: place)
        }
        .task {
            location.start()
            await store.loadPlaces()
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
                .background {
                    if isSelected {
                        Capsule().fill(color.gradient)
                    } else {
                        Capsule().fill(.regularMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct NearbyBanner: View {
    let place: PlaceSummary
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlacePin(category: place.category)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ești lângă")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(place.name)
                    .font(.headline)
                    .lineLimit(1)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

#Preview {
    MapScreen()
        .environment(PlacesStore())
        .environment(LocationService())
}
