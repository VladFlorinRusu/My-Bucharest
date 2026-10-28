import SwiftUI

/// Poveștile unui singur loc, deschise de pe hartă.
struct PlaceStoriesView: View {
    let place: PlaceSummary

    @Environment(PlacesStore.self) private var store

    @State private var items: [FeedItem]?
    @State private var errorMessage: String?
    @State private var kindFilter: StoryKind?

    var body: some View {
        StoryCover {
            if let items {
                StoryFeedView(items: filtered(items), showsSaveButton: hasStories)
                    .overlay(alignment: .topLeading) {
                        let kinds = availableKinds(in: items)
                        if kinds.count > 1 {
                            KindFilterBar(kinds: kinds, selection: $kindFilter)
                        }
                    }
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

    private func filtered(_ items: [FeedItem]) -> [FeedItem] {
        guard let kindFilter else { return items }
        return items.filter { ($0.story.kind ?? .history) == kindFilter }
    }

    private func availableKinds(in items: [FeedItem]) -> [StoryKind] {
        let present = Set(items.map { $0.story.kind ?? .history })
        return StoryKind.allCases.filter(present.contains)
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

/// Filtrul după tipul poveștii: istorie, curiozități, bârfe, etimologie etc.
private struct KindFilterBar: View {
    let kinds: [StoryKind]
    @Binding var selection: StoryKind?

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: "Toate", symbol: "square.grid.2x2.fill", color: .white, kind: nil)
                    ForEach(kinds, id: \.self) { kind in
                        chip(title: kind.filterTitle, symbol: kind.symbol, color: kind.color, kind: kind)
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 72)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 8)
    }

    private func chip(title: String, symbol: String, color: Color, kind: StoryKind?) -> some View {
        let isSelected = selection == kind
        return Button {
            withAnimation(.snappy) { selection = kind }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(
                    isSelected ? .regular.tint(color.opacity(0.7)).interactive() : .clear.interactive(),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
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
