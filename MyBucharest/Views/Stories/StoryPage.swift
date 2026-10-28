import SwiftUI

struct StoryPage: View {
    let place: PlaceDetail
    /// `nil` când locul nu are încă povești: afișăm doar descrierea locului.
    let story: Story?
    let isActive: Bool

    @Environment(PlacesStore.self) private var store
    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            StoryMediaView(video: story?.video, category: place.category, isActive: isActive, api: store.api)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            caption
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(place.name, systemImage: place.category.symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(place.category.color.opacity(0.85), in: Capsule())

            Text(story?.title ?? place.name)
                .font(.title2.bold())

            Text(story?.body ?? place.summary)
                .font(.body)
                .lineLimit(isExpanded ? nil : 4)
                .onTapGesture { withAnimation(.snappy) { isExpanded.toggle() } }

            if let personalities = story?.personalities, !personalities.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(personalities, id: \.self) { name in
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

            if let source = story?.source, let channel = source.channel ?? source.title {
                sourceView(channel: channel, url: source.url.flatMap(URL.init(string:)))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
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
