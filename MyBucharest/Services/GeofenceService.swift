import CoreLocation
import Observation
import UIKit
import UserNotifications

/// Notificări „Ești lângă …” și când aplicația e închisă.
///
/// - `CLMonitor` supraveghează un cerc în jurul celor mai apropiate locuri; când intri într-unul,
///   iOS trezește aplicația în fundal câteva secunde, timp în care trimitem o notificare locală.
/// - iOS permite cel mult 20 de zone per aplicație, așa că le recalculăm când te deplasezi:
///   serviciul „significant location change” trezește aplicația la ~500 m și ne dă locația.
/// - Ambele cer permisiunea de locație „Întotdeauna”.
@Observable
final class GeofenceService: NSObject {
    static let shared = GeofenceService()

    enum Status: Equatable {
        case off
        case needsAlwaysPermission
        case needsNotificationPermission
        case active
    }

    /// Limita iOS e de 20 de condiții per aplicație.
    static let maxMonitoredPlaces = 20
    /// Același loc nu te anunță de mai multe ori într-un interval scurt.
    static let perPlaceCooldown: TimeInterval = 6 * 60 * 60
    /// Când intri deodată în raza mai multor locuri, primești o singură notificare.
    static let globalCooldown: TimeInterval = 60
    /// Sub această rază, detecția iOS devine nesigură.
    static let minimumRegionRadius: CLLocationDistance = 100

    private(set) var isEnabled: Bool
    private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    private(set) var notificationsAllowed = false
    private(set) var monitoredCount = 0
    /// Locul a cărui notificare a fost atinsă; RootView îl deschide.
    var openedPlaceID: UUID?

    var status: Status {
        guard isEnabled else { return .off }
        guard locationAuthorization == .authorizedAlways else { return .needsAlwaysPermission }
        guard notificationsAllowed else { return .needsNotificationPermission }
        return .active
    }

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var places: [CachedPlace]
    @ObservationIgnored private var lastRefreshLocation: CLLocation?

    private static let monitorName = "MyBucharestPlaces"
    private static let enabledKey = "geofence.enabled"
    private static let placesKey = "geofence.places"
    private static let notifiedKey = "geofence.lastNotified"
    private static let lastAlertKey = "geofence.lastAlert"

    /// Copia locală a locurilor: când iOS trezește aplicația în fundal, nu ne putem baza pe server.
    struct CachedPlace: Codable {
        let id: UUID
        let name: String
        let summary: String
        let latitude: Double
        let longitude: Double

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    override init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        places = UserDefaults.standard.data(forKey: Self.placesKey)
            .flatMap { try? JSONDecoder().decode([CachedPlace].self, from: $0) } ?? []
        super.init()
        locationManager.delegate = self
        locationAuthorization = locationManager.authorizationStatus
        // Delegatul trebuie setat înainte să termine pornirea, ca atingerea unei notificări
        // să deschidă locul chiar și când aplicația era închisă.
        UNUserNotificationCenter.current().delegate = self
    }

    /// Apelat la fiecare pornire, inclusiv când iOS trezește aplicația în fundal pentru o zonă
    /// sau o schimbare de locație: trebuie să reluăm imediat ascultarea evenimentelor.
    func resume() {
        Task { await refreshStatus() }
        guard isEnabled else { return }
        locationManager.startMonitoringSignificantLocationChanges()
        Task { await startMonitor() }
    }

    func setEnabled(_ enabled: Bool, around location: CLLocation?) async {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)

        guard enabled else {
            locationManager.stopMonitoringSignificantLocationChanges()
            await stopMonitor()
            return
        }

        notificationsAllowed = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        // Dacă ai dat deja „Cât timp folosesc aplicația”, iOS afișează întrebarea de trecere la „Întotdeauna”.
        locationManager.requestAlwaysAuthorization()
        locationManager.startMonitoringSignificantLocationChanges()
        await startMonitor()
        if let location { await updateMonitoredPlaces(around: location) }
    }

    func refreshStatus() async {
        locationAuthorization = locationManager.authorizationStatus
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = [.authorized, .provisional].contains(settings.authorizationStatus)
    }

    func cache(_ summaries: [PlaceSummary]) {
        guard !summaries.isEmpty else { return }
        places = summaries.map {
            CachedPlace(id: $0.id, name: $0.name, summary: $0.summary, latitude: $0.latitude, longitude: $0.longitude)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(places), forKey: Self.placesKey)
    }

    /// Din prim-plan: recalculează zonele după ce te-ai deplasat sau s-a schimbat raza.
    func locationChanged(_ location: CLLocation, force: Bool = false) {
        guard isEnabled else { return }
        if !force, let last = lastRefreshLocation, location.distance(from: last) < 300 { return }
        Task { await updateMonitoredPlaces(around: location) }
    }

    // MARK: - Zone

    private func startMonitor() async {
        guard monitor == nil else { return }
        let monitor = await CLMonitor(Self.monitorName)
        self.monitor = monitor
        monitoredCount = await monitor.identifiers.count
        eventsTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    await self?.handle(event)
                }
            } catch {
                // Fluxul se închide doar la anulare.
            }
        }
    }

    private func stopMonitor() async {
        eventsTask?.cancel()
        eventsTask = nil
        if let monitor {
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
        }
        monitor = nil
        monitoredCount = 0
        lastRefreshLocation = nil
    }

    private func updateMonitoredPlaces(around location: CLLocation) async {
        if monitor == nil { await startMonitor() }
        guard let monitor else { return }
        lastRefreshLocation = location

        let radius = max(AppConfig.proximityRadius, Self.minimumRegionRadius)
        let nearest = places
            .sorted { $0.location.distance(from: location) < $1.location.distance(from: location) }
            .prefix(Self.maxMonitoredPlaces)
        let wanted = Set(nearest.map(\.id.uuidString))

        for identifier in await monitor.identifiers where !wanted.contains(identifier) {
            await monitor.remove(identifier)
        }
        for place in nearest {
            let condition = CLMonitor.CircularGeographicCondition(center: place.location.coordinate, radius: radius)
            await monitor.add(condition, identifier: place.id.uuidString, assuming: .unsatisfied)
        }
        monitoredCount = nearest.count
    }

    private func handle(_ event: CLMonitor.Event) async {
        guard
            event.state == .satisfied,
            let id = UUID(uuidString: event.identifier),
            let place = places.first(where: { $0.id == id })
        else { return }

        // În prim-plan aplicația are deja bannerul și vibrația ei.
        guard UIApplication.shared.applicationState != .active else { return }
        guard shouldNotify(about: id) else { return }

        let othersInside = await placesInside().subtracting([id]).count
        await sendNotification(for: place, othersNearby: othersInside)
    }

    private func placesInside() async -> Set<UUID> {
        guard let monitor else { return [] }
        var inside: Set<UUID> = []
        for identifier in await monitor.identifiers {
            if await monitor.record(for: identifier)?.lastEvent.state == .satisfied,
               let id = UUID(uuidString: identifier) {
                inside.insert(id)
            }
        }
        return inside
    }

    // MARK: - Notificări

    private func shouldNotify(about id: UUID) -> Bool {
        let now = Date.now.timeIntervalSince1970
        let lastAlert = UserDefaults.standard.double(forKey: Self.lastAlertKey)
        let notified = UserDefaults.standard.dictionary(forKey: Self.notifiedKey) as? [String: Double] ?? [:]
        if now - lastAlert < Self.globalCooldown { return false }
        if let last = notified[id.uuidString], now - last < Self.perPlaceCooldown { return false }
        return true
    }

    private func sendNotification(for place: CachedPlace, othersNearby: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Ești lângă \(place.name)"
        var body = place.summary
        if othersNearby > 0 {
            body += othersNearby == 1 ? " Încă un loc e în apropiere." : " Încă \(othersNearby) locuri sunt în apropiere."
        }
        content.body = body.isEmpty ? "Atinge ca să vezi poveștile locului." : body
        content.sound = .default
        content.userInfo = ["placeID": place.id.uuidString]

        let request = UNNotificationRequest(identifier: "nearby-\(place.id.uuidString)", content: content, trigger: nil)
        guard (try? await UNUserNotificationCenter.current().add(request)) != nil else { return }

        let now = Date.now.timeIntervalSince1970
        var notified = UserDefaults.standard.dictionary(forKey: Self.notifiedKey) as? [String: Double] ?? [:]
        notified[place.id.uuidString] = now
        UserDefaults.standard.set(notified, forKey: Self.notifiedKey)
        UserDefaults.standard.set(now, forKey: Self.lastAlertKey)
    }
}

extension GeofenceService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.locationAuthorization = status }
    }

    /// Vine și când iOS trezește aplicația închisă după o deplasare de ~500 m.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.locationChanged(latest) }
    }
}

extension GeofenceService: UNUserNotificationCenterDelegate {
    /// Cu aplicația deschisă nu afișăm notificarea de sistem: apare bannerul din aplicație.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let rawID = response.notification.request.content.userInfo["placeID"] as? String
        await MainActor.run { self.openedPlaceID = rawID.flatMap(UUID.init(uuidString:)) }
    }
}
