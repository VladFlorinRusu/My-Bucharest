import SwiftUI

/// Feed vertical, pe tot ecranul, cu poveștile unui loc – stil TikTok/Reels.
struct PlaceStoriesView: View {
    let place: PlaceSummary

    @Environment(PlacesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var detail: PlaceDetail?
    @State private var errorMessage: String?
    @State private var activeStoryID: UUID?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let detail {
                feed(for: detail)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Nu am putut încărca povestea", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Reîncearcă") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Închide")
            .padding()
        }
        .statusBarHidden()
        .task { await load() }
    }

    @ViewBuilder
    private func feed(for detail: PlaceDetail) -> some View {
        if detail.stories.isEmpty {
            StoryPage(place: detail, story: nil, isActive: true)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(detail.stories) { story in
                        StoryPage(place: detail, story: story, isActive: activeStoryID == story.id)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(story.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeStoryID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            let loaded = try await store.detail(for: place.id)
            detail = loaded
            activeStoryID = loaded.stories.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
