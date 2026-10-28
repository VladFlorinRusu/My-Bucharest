import CoreLocation
import Foundation

enum AppConfig {
    static let serverURLKey = "serverURL"

    /// Simulatorul vede serverul de pe Mac la 127.0.0.1. Pe iPhone e nevoie de IP-ul Mac-ului
    /// din rețeaua locală, iar serverul trebuie pornit cu `swift run App serve --hostname 0.0.0.0`.
    #if targetEnvironment(simulator)
    static let defaultServerURL = "http://127.0.0.1:8080"
    #else
    static let defaultServerURL = "http://192.168.0.85:8080"
    #endif

    /// Adresa setată din Profil are prioritate față de cea implicită.
    static var apiBaseURL: URL {
        UserDefaults.standard.string(forKey: serverURLKey).flatMap(URL.init(string:))
            ?? URL(string: defaultServerURL)!
    }

    /// Distanța la care considerăm că utilizatorul „a ajuns” lângă un loc; se setează din Profil.
    static let proximityRadiusKey = "proximityRadius"
    static let defaultProximityRadius: CLLocationDistance = 200
    static let proximityRadiusRange: ClosedRange<CLLocationDistance> = 50...10_000

    static var proximityRadius: CLLocationDistance {
        let saved = UserDefaults.standard.double(forKey: proximityRadiusKey)
        return saved > 0 ? saved : defaultProximityRadius
    }

    /// Un loc anunțat poate fi anunțat din nou abia după ce te-ai îndepărtat atât de el,
    /// ca să nu vibreze la fiecare oscilație a GPS-ului la marginea razei.
    static var proximityResetRadius: CLLocationDistance { proximityRadius * 2 }
    /// Feed-ul se reordonează după apropiere când te-ai deplasat cel puțin atât.
    static let feedRefreshDistance: CLLocationDistance = 150

    static let bucharestCenter = CLLocationCoordinate2D(latitude: 44.4355, longitude: 26.1025)
}
