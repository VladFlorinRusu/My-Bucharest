import SwiftUI

struct StoryPage: View {
    let item: FeedItem
    let isActive: Bool
    var safeAreaInsets = EdgeInsets()
    var showsSaveButton = true
    var showsMapButton = false

    @Environment(PlacesStore.self) private var store
    @Environment(ProfileStore.self) private var profile
    @Environment(AppRouter.self) private var router
    @State private var isExpanded = false

    private var place: PlaceSummary { item.place }
    private var story: Story { item.story }

    var body: some View {
        ZStack(alignment: .bottom) {
            StoryMediaView(video: story.video, category: place.category, isActive: isActive, api: store.api)

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 16) {
                caption
                actionRail
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.bottom, safeAreaInsets.bottom + 20)
        }
        .clipped()
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(place.name, systemImage: place.category.symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(place.category.color.opacity(0.85), in: Capsule())

            Text(story.title)
                .font(.title2.bold())

            Text(story.body)
                .font(.body)
                .lineLimit(isExpanded ? nil : 4)
                .onTapGesture { withAnimation(.snappy) { isExpanded.toggle() } }

            if !story.personalities.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(story.personalities, id: \.self) { name in
                            Label(name, systemImage: "person.fill")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.18), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let source = story.source, let channel = source.channel ?? source.title {
                sourceView(channel: channel, url: source.url.flatMap(URL.init(string:)))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRail: some View {
        VStack(spacing: 18) {
            if showsSaveButton {
                let isSaved = profile.isSaved(story.id)
                railButton(
                    title: isSaved ? "Salvat" : "Salvează",
                    systemImage: isSaved ? "bookmark.fill" : "bookmark"
                ) {
                    profile.toggleSave(item)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isSaved)
            }
            if showsMapButton {
                railButton(title: "Hartă", systemImage: "map") {
                    router.showOnMap(place)
                }
            }
        }
    }

    private func railButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .glassEffect(.clear.interactive(), in: Circle())
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sourceView(channel: String, url: URL?) -> some View {
        let label = Label("Sursa: \(channel)", systemImage: "play.rectangle.fill")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        if let url {
            Link(destination: url) { label }
        } else {
            label
        }
    }
}
