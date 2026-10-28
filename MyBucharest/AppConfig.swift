import CoreLocation
import Foundation

enum AppConfig {
    /// Simulatorul vede serverul de pe Mac la 127.0.0.1. Pe un iPhone real pune IP-ul
    /// Mac-ului din rețeaua locală (ex. http://192.168.1.20:8080) și pornește serverul cu
    /// `swift run App serve --hostname 0.0.0.0`.
    static let apiBaseURL = URL(string: "http://127.0.0.1:8080")!

    /// Distanța la care considerăm că utilizatorul „a ajuns” lângă un loc.
    static let proximityRadius: CLLocationDistance = 75

    static let bucharestCenter = CLLocationCoordinate2D(latitude: 44.4355, longitude: 26.1025)
}
