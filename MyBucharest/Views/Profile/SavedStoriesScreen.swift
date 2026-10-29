import SwiftUI

/// Poveștile salvate, ca grid de tile-uri: miniatura sus, numele dedesubt.
struct SavedStoriesScreen: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(PlacesStore.self) private var store

    @State private var presentedItem: FeedItem?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        Group {
            if profile.savedStories.isEmpty {
                ContentUnavailableView(
                    "Nicio poveste salvată",
                    systemImage: "bookmark",
                    description: Text("Apasă „Salvează” pe un reel ca să-l găsești aici.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(profile.savedStories) { item in
                            Button { presentedItem = item } label: {
                                SavedStoryTile(item: item, api: store.api)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Elimină din salvate", systemImage: "bookmark.slash", role: .destructive) {
                                    withAnimation { profile.removeSaved(item.id) }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable { await profile.refreshSaved(using: store.api) }
            }
        }
        .navigationTitle("Salvate")
        .navigationBarTitleDisplayMode(.inline)
        .task { await profile.refreshSaved(using: store.api) }
        .fullScreenCover(item: $presentedItem) { item in
            SavedStoriesView(initialItem: item)
        }
    }
}

private struct SavedStoryTile: View {
    let item: FeedItem
    let api: APIClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StoryThumbnail(item: item, api: api)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if let kind = item.story.kind {
                        Image(systemName: kind.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(kind.color.opacity(0.85), in: Circle())
                            .padding(8)
                    }
                }

            Text(item.story.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(item.place.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Miniatura unei povești; fără imagine, culoarea și simbolul categoriei locului.
struct StoryThumbnail: View {
    let item: FeedItem
    let api: APIClient

    var body: some View {
        // Color.clear ia mărimea propusă de părinte; imaginea o umple și e decupată.
        Color.clear
            .overlay {
                if let url = api.resolve(item.story.thumbnailURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
    }

    private var placeholder: some View {
        let category = item.place.category
        return ZStack {
            LinearGradient(colors: [category.color, category.color.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: category.symbol)
                .font(.title)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// Reels din poveștile salvate, pornind de la cea aleasă.
struct SavedStoriesView: View {
    let initialItem: FeedItem

    @Environment(ProfileStore.self) private var profile
    /// Lista e fixată la deschidere, ca paginile să nu dispară dacă scoți o poveste de la salvate.
    @State private var items: [FeedItem] = []

    var body: some View {
        StoryCover {
            if !items.isEmpty {
                StoryFeedView(items: items, initialItemID: initialItem.id)
            }
        }
        .onAppear {
            if items.isEmpty { items = profile.savedStories }
        }
    }
}
