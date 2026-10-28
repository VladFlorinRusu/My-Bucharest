import CoreLocation
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
    @Environment(LocationService.self) private var location
    @AppStorage(AppConfig.proximityRadiusKey) private var proximityRadius = AppConfig.defaultProximityRadius
    @State private var isExpanded = false
    @State private var isShowingCredits = false
    @State private var isPaused = false
    @GestureState private var isFastForwarding = false

    private var place: PlaceSummary { item.place }
    private var story: Story { item.story }

    /// Ținutul apăsat redă cu 2× chiar dacă povestea era pe pauză.
    private var isPlaying: Bool { isActive && (!isPaused || isFastForwarding) }

    var body: some View {
        ZStack(alignment: .bottom) {
            StoryMediaView(
                video: story.video,
                audioURL: story.audioURL,
                category: place.category,
                isActive: isPlaying,
                rate: isFastForwarding ? 2 : 1,
                api: store.api
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .gesture(playbackGesture)

            playbackIndicators

            HStack(alignment: .bottom, spacing: 16) {
                caption
                actionRail
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.bottom, safeAreaInsets.bottom + 20)
        }
        .clipped()
        .sensoryFeedback(.impact(weight: .medium), trigger: isFastForwarding) { _, holding in holding }
        .onChange(of: isActive) { _, active in
            if !active { isPaused = false }
        }
    }

    /// 37 m -> „chiar lângă tine”, 184 m -> „la 180 m de tine”, 2 350 m -> „la 2,4 km de tine”
    static func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 50 { return "Chiar lângă tine" }
        if meters < 10_000 { return "La \(Int(meters / 10) * 10) m de tine" }
        let km = (meters / 1_000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "ro_RO")))
        return "La \(km) km de tine"
    }

    /// Atingere = pauză / redare; ținut apăsat = viteză 2× până ridici degetul.
    private var playbackGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isFastForwarding) { value, holding, _ in
                if case .second(true, _) = value { holding = true }
            }
            .exclusively(before: TapGesture().onEnded {
                withAnimation(.snappy) { isPaused.toggle() }
            })
    }

    @ViewBuilder
    private var playbackIndicators: some View {
        if isPaused, !isFastForwarding {
            Image(systemName: "play.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
        }
        if isFastForwarding {
            Label("2×", systemImage: "forward.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, safeAreaInsets.top + 64)
                .allowsHitTesting(false)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(place.name, systemImage: place.category.symbol)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(place.category.color.opacity(0.85), in: Capsule())
                if let kind = story.kind {
                    StoryKindBadge(kind: kind)
                }
            }

            if let distance = location.location?.distance(from: place.location) {
                Label(Self.formatDistance(distance), systemImage: distance <= proximityRadius ? "location.fill" : "location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(distance <= proximityRadius ? .green : .white.opacity(0.85))
            }

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

            mediaDisclosure
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isShowingCredits) {
            CreditsSheet(credits: story.credits ?? [])
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var mediaDisclosure: some View {
        let credits = story.credits ?? []
        if story.aiVoice == true || !credits.isEmpty {
            HStack(spacing: 12) {
                if story.aiVoice == true {
                    Label("Voce generată cu AI", systemImage: "waveform")
                }
                if !credits.isEmpty {
                    Button { isShowingCredits = true } label: {
                        Label("Foto: Wikimedia Commons", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.75))
        }
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
