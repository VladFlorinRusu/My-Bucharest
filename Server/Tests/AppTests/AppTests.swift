@testable import App
import Fluent
import Testing
import VaporTesting

@Suite("BucharestServer", .serialized)
struct AppTests {
    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Locurile publicate sunt sortate după distanță și filtrate după rază")
    func nearbyPlaces() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "api/v1/places?lat=44.4314&lon=26.0978&radius=500") { res async throws in
                #expect(res.status == .ok)
                let places = try res.content.decode([PlaceSummaryDTO].self)
                #expect(places.first?.name == "Biserica Stavropoleos")
                #expect(!places.contains { $0.name == "Arcul de Triumf" })
                #expect(places.allSatisfy { ($0.distanceMeters ?? .infinity) <= 500 })
            }
        }
    }

    @Test("Detaliul unui loc include poveștile")
    func placeDetail() async throws {
        try await withApp { app in
            let place = try #require(try await Place.query(on: app.db).filter(\.$slug == "ateneul-roman").first())
            try await app.testing().test(.GET, "api/v1/places/\(try place.requireID())") { res async throws in
                #expect(res.status == .ok)
                let detail = try res.content.decode(PlaceDetailDTO.self)
                #expect(detail.stories.count == 1)
            }
        }
    }

    @Test("Feed-ul pune întâi poveștile din apropiere și respectă limita")
    func feed() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "api/v1/feed?lat=44.4672&lon=26.0781&limit=3") { res async throws in
                #expect(res.status == .ok)
                let items = try res.content.decode([FeedItemDTO].self)
                #expect(items.count == 3)
                #expect(items.first?.place.name == "Arcul de Triumf")
            }
        }
    }

    @Test("Rutele de admin cer token")
    func adminRequiresToken() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "api/v1/admin/places") { res async throws in
                #expect(res.status == .serviceUnavailable || res.status == .unauthorized)
            }
        }
    }

    @Test("Extragerea ID-ului YouTube din URL-uri")
    func youtubeIDs() {
        #expect(YouTube.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTube.videoID(from: "https://youtu.be/dQw4w9WgXcQ?t=10") == "dQw4w9WgXcQ")
        #expect(YouTube.videoID(from: "https://youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTube.videoID(from: "nu-e-un-id") == nil)
    }

    @Test("Slug fără diacritice")
    func slug() {
        #expect(Slug.make(from: "Ateneul Român") == "ateneul-roman")
        #expect(Slug.make(from: "Caru' cu Bere") == "caru-cu-bere")
    }
}
