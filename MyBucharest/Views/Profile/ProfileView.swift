import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(PlacesStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var presentedSavedStory: FeedItem?
    @State private var isConfirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section("Povești salvate") {
                    if profile.savedStories.isEmpty {
                        emptyRow("Apasă pe semnul de carte dintr-un reel ca să-l salvezi aici.")
                    } else {
                        ForEach(profile.savedStories) { item in
                            Button { presentedSavedStory = item } label: {
                                row(title: item.story.title, subtitle: item.place.name, category: item.place.category)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: profile.removeSaved)
                    }
                }

                Section("Locuri descoperite") {
                    if profile.discoveredPlaces.isEmpty {
                        emptyRow("Plimbă-te prin oraș: un loc apare aici când ajungi lângă el.")
                    } else {
                        ForEach(profile.discoveredPlaces) { discovered in
                            Button { router.showOnMap(discovered.place) } label: {
                                row(
                                    title: discovered.place.name,
                                    subtitle: discovered.date.formatted(date: .abbreviated, time: .shortened),
                                    category: discovered.place.category
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Despre") {
                    LabeledContent("Server", value: AppConfig.apiBaseURL.absoluteString)
                    Button("Resetează progresul", role: .destructive) {
                        isConfirmingReset = true
                    }
                }
            }
            .navigationTitle("Profil")
            .confirmationDialog(
                "Ștergi poveștile salvate și locurile descoperite?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Resetează", role: .destructive) { profile.reset() }
            }
            .fullScreenCover(item: $presentedSavedStory) { item in
                SavedStoriesView(initialItem: item)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Explorator al Bucureștiului")
                .font(.title3.bold())

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    statCard(
                        value: "\(profile.discoveredPlaces.count)",
                        total: store.places.isEmpty ? nil : store.places.count,
                        label: "locuri descoperite",
                        systemImage: "mappin.and.ellipse"
                    )
                    statCard(
                        value: "\(profile.savedStories.count)",
                        total: nil,
                        label: "povești salvate",
                        systemImage: "bookmark.fill"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func statCard(value: String, total: Int?, label: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title.bold())
                if let total {
                    Text("/ \(total)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    private func row(title: String, subtitle: String, category: PlaceCategory) -> some View {
        HStack(spacing: 12) {
            PlacePin(category: category)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// Reels din poveștile salvate, pornind de la cea aleasă.
private struct SavedStoriesView: View {
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
