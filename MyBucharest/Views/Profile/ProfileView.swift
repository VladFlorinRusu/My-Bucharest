import CoreLocation
import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(PlacesStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var presentedSavedStory: FeedItem?
    @State private var isConfirmingReset = false
    @State private var isShowingAllDiscovered = false

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
                            .accessibilityIdentifier("profile.savedStory")
                        }
                        .onDelete(perform: profile.removeSaved)
                    }
                }

                ProximityRadiusSection()
                
                Section("Locuri descoperite") {
                    if profile.discoveredPlaces.isEmpty {
                        emptyRow("Plimbă-te prin oraș: un loc apare aici când ajungi lângă el.")
                    } else {
                        let discoveredToShow = isShowingAllDiscovered ? profile.discoveredPlaces : Array(profile.discoveredPlaces.prefix(10))
                        ForEach(discoveredToShow) { discovered in
                            Button { router.showOnMap(discovered.place) } label: {
                                row(
                                    title: discovered.place.name,
                                    subtitle: discovered.date.formatted(date: .abbreviated, time: .shortened),
                                    category: discovered.place.category
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if profile.discoveredPlaces.count > 10 && !isShowingAllDiscovered {
                            Button("Afișează mai multe") { isShowingAllDiscovered = true }
                                .buttonStyle(.plain)
                        }
                    }
                }

                BackgroundAlertsSection()

                Section("Despre") {
                    NavigationLink {
                        ServerSettingsView()
                    } label: {
                        LabeledContent("Server", value: AppConfig.apiBaseURL.absoluteString)
                    }
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

/// Raza în care un loc e considerat „în apropiere” (vibrație, banner, pini animați pe hartă).
private struct ProximityRadiusSection: View {
    @Environment(PlacesStore.self) private var store
    @Environment(LocationService.self) private var location
    @AppStorage(AppConfig.proximityRadiusKey) private var savedRadius = AppConfig.defaultProximityRadius

    /// Valoarea de pe slider; se salvează la ridicarea degetului, ca să nu vibreze cât tragi.
    @State private var draftRadius: Double?

    private var radius: Double { draftRadius ?? savedRadius }

    private var placesInRadius: Int? {
        guard let current = location.location else { return nil }
        return store.places.filter { $0.location.distance(from: current) <= radius }.count
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Rază de proximitate", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Text(Self.format(radius))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Self.sliderPosition(forRadius: radius) },
                        set: { draftRadius = Self.radius(forSliderPosition: $0) }
                    ),
                    in: 0...1
                ) {
                    Text("Rază de proximitate")
                } minimumValueLabel: {
                    Text("50 m").font(.caption2)
                } maximumValueLabel: {
                    Text("10 km").font(.caption2)
                } onEditingChanged: { isEditing in
                    guard !isEditing, let draftRadius else { return }
                    savedRadius = draftRadius
                    self.draftRadius = nil
                }
                if let placesInRadius {
                    Text(placesInRadius == 1 ? "Acum: un loc în rază" : "Acum: \(placesInRadius) locuri în rază")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if savedRadius != AppConfig.defaultProximityRadius {
                Button("Revino la \(Self.format(AppConfig.defaultProximityRadius))") {
                    savedRadius = AppConfig.defaultProximityRadius
                }
            }
        } header: {
            Text("Proximitate")
        } footer: {
            Text("Când ajungi la această distanță de un loc, telefonul vibrează, iar pe hartă locul începe să pulseze.")
        }
    }

    static func format(_ meters: Double) -> String {
        guard meters >= 1_000 else { return "\(Int(meters)) m" }
        let km = (meters / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "ro_RO")))
        return "\(km) km"
    }

    /// Scală logaritmică: 50 m – 10 km pe aceeași bară, cu precizie mare la valorile mici.
    static func radius(forSliderPosition position: Double) -> Double {
        let range = AppConfig.proximityRadiusRange
        let raw = range.lowerBound * pow(range.upperBound / range.lowerBound, position)
        let step: Double = raw < 1_000 ? 25 : (raw < 5_000 ? 100 : 500)
        return min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
    }

    static func sliderPosition(forRadius radius: Double) -> Double {
        let range = AppConfig.proximityRadiusRange
        return log(radius / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }
}

/// Activarea notificărilor „Ești lângă …” cu aplicația închisă, plus starea permisiunilor.
private struct BackgroundAlertsSection: View {
    @Environment(GeofenceService.self) private var geofence
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { geofence.isEnabled },
                set: { enabled in Task { await geofence.setEnabled(enabled, around: location.location) } }
            )) {
                Label("Anunță-mă și cu aplicația închisă", systemImage: "bell.badge")
            }
            statusRow
        } header: {
            Text("Notificări în fundal")
        } footer: {
            Text("Când treci pe lângă un loc, primești o notificare chiar dacă aplicația nu e deschisă. iOS permite supravegherea a cel mult \(GeofenceService.maxMonitoredPlaces) locuri deodată, așa că sunt alese cele mai apropiate de tine.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch geofence.status {
        case .off:
            EmptyView()
        case .active:
            Label("Activ: \(geofence.monitoredCount) locuri supravegheate", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsAlwaysPermission:
            permissionRow(
                "Permite accesul la locație „Întotdeauna” ca să funcționeze cu aplicația închisă.",
                systemImage: "location.slash"
            )
        case .needsNotificationPermission:
            permissionRow("Permite notificările pentru MyBucharest.", systemImage: "bell.slash")
        }
    }

    private func permissionRow(_ text: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: systemImage)
                .foregroundStyle(.orange)
            Button("Deschide Setările") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}

/// Adresa serverului, utilă când rulezi pe iPhone și IP-ul Mac-ului se schimbă.
private struct ServerSettingsView: View {
    @Environment(PlacesStore.self) private var store
    @Environment(LocationService.self) private var location

    @State private var address = AppConfig.apiBaseURL.absoluteString
    @State private var status: String?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.0.10:8080", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Adresa serverului")
            } footer: {
                Text("Pe iPhone folosește IP-ul Mac-ului din aceeași rețea Wi-Fi, iar serverul pornește cu `swift run App serve --hostname 0.0.0.0`.")
            }

            Section {
                Button(isChecking ? "Se verifică…" : "Salvează și testează") {
                    Task { await saveAndTest() }
                }
                .disabled(isChecking || URL(string: address)?.host == nil)

                Button("Revino la adresa implicită") {
                    UserDefaults.standard.removeObject(forKey: AppConfig.serverURLKey)
                    address = AppConfig.apiBaseURL.absoluteString
                    Task { await saveAndTest() }
                }
            }

            if let status {
                Section { Text(status) }
            }
        }
        .navigationTitle("Server")
    }

    private func saveAndTest() async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else { return }
        if trimmed != AppConfig.defaultServerURL {
            UserDefaults.standard.set(trimmed, forKey: AppConfig.serverURLKey)
        }

        isChecking = true
        defer { isChecking = false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url.appending(path: "health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                status = "Serverul a răspuns, dar nu cu 200."
                return
            }
            await store.loadPlaces()
            await store.loadFeed(near: location.location)
            status = "Conectat. Am încărcat \(store.places.count) locuri."
        } catch {
            status = "Nu mă pot conecta: \(error.localizedDescription)"
        }
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
