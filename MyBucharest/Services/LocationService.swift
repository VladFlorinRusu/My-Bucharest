import CoreLocation
import Observation

@Observable
final class LocationService {
    private(set) var location: CLLocation?
    private(set) var isAuthorizationDenied = false

    private var session: CLServiceSession?
    private var updatesTask: Task<Void, Never>?

    func start() {
        guard updatesTask == nil else { return }
        session = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    isAuthorizationDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    if let location = update.location {
                        self.location = location
                    }
                }
            } catch {
                // Fluxul se oprește doar la anulare; nu avem ce recupera.
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
    }
}
