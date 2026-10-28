import SwiftUI

/// Poveștile unui singur loc, deschise de pe hartă.
struct PlaceStoriesView: View {
    let place: PlaceSummary

    @Environment(PlacesStore.self) private var store

    @State private var items: [FeedItem]?
    @State private var errorMessage: String?

    var body: some View {
        StoryCover {
            if let items {
                StoryFeedView(items: items, showsSaveButton: hasStories)
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
        }
        .task { await load() }
    }

    private var hasStories: Bool {
        items?.first?.story.id != place.id
    }

    private func load() async {
        errorMessage = nil
        do {
            let detail = try await store.detail(for: place.id)
            if detail.stories.isEmpty {
                // Locul nu are încă povești: arătăm descrierea lui ca o singură pagină.
                let intro = Story(id: place.id, title: detail.name, body: detail.summary,
                                  personalities: [], video: nil, source: nil)
                items = [FeedItem(place: place, story: intro)]
            } else {
                items = detail.stories.map { FeedItem(place: place, story: $0) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Container pe tot ecranul, cu fundal negru și buton de închidere.
struct StoryCover<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            content

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.clear.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Închide")
            .padding()
        }
        .statusBarHidden()
    }
}
