import CoreLocation
import SwiftUI

struct ForYouView: View {
    @Environment(PlacesStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if !store.feed.isEmpty {
                StoryFeedView(
                    items: store.feed,
                    isVisible: router.selectedTab == .forYou,
                    showsMapButton: true
                )
            } else if store.isLoadingFeed {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.feedErrorMessage {
                ContentUnavailableView {
                    Label("Nu mă pot conecta la server", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Reîncearcă") { Task { await reload() } }
                        .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            } else {
                ContentUnavailableView(
                    "Încă nu sunt povești",
                    systemImage: "play.rectangle.on.rectangle",
                    description: Text("Revino după ce adaugi conținut pe server.")
                )
                .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                header
                if router.selectedTab == .forYou, !store.feed.isEmpty, store.feedNeedsReordering(for: location.location) {
                    reorderButton
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: store.feedNeedsReordering(for: location.location))
        }
        .preferredColorScheme(router.selectedTab == .forYou ? .dark : nil)
        // Reîncarcă o dată când sosește prima locație, ca feed-ul să fie sortat după apropiere.
        .task(id: location.location != nil) {
            await reload()
        }
        // Când revii în tab după ce te-ai deplasat, cele mai apropiate povești trec din nou primele.
        .onChange(of: router.selectedTab) { _, tab in
            guard tab == .forYou, store.feedNeedsReordering(for: location.location) else { return }
            Task { await reload() }
        }
    }

    private var reorderButton: some View {
        Button {
            Task { await reload() }
        } label: {
            Label("Arată ce e lângă tine", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(.blue.opacity(0.5)).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pentru tine")
                    .font(.headline)
                if store.feedLocation != nil {
                    Text("Cele mai apropiate primele")
                        .font(.caption)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(.white)
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassEffect(.clear.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reîncarcă")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func reload() async {
        await store.loadFeed(near: location.location)
    }
}
