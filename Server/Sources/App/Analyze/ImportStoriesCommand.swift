import Fluent
import Foundation
import Vapor

/// swift run App import-stories Reports/<id>-places.json [--publish]
///
/// Importă povești grupate pe locuri (de obicei curate din faptele unui clip analizat):
/// găsește sau creează fiecare loc pe hartă și îi adaugă poveștile, fiecare cu tipul ei
/// (istorie, curiozitate, bârfă, etimologie, gastronomie, legendă, personalitate) și cu
/// segmentul din clipul sursă, redat prin embed YouTube.
struct ImportStoriesCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "file", help: "Fișierul JSON cu locurile și poveștile")
        var file: String

        @Flag(name: "publish", help: "Publică locurile noi (implicit rămân draft)")
        var publish: Bool

        init() {}
    }

    struct ImportFile: Decodable {
        struct PlaceEntry: Decodable {
            var name: String
            var category: PlaceCategory
            var summary: String
            /// Variante de căutare pentru geocodare, încercate în ordine.
            var searchQueries: [String]?
            var latitude: Double?
            var longitude: Double?
            var stories: [StoryEntry]
        }

        struct StoryEntry: Decodable {
            var kind: StoryKind
            var title: String
            var body: String
            var personalities: [String]?
            var startSeconds: Int?
            var endSeconds: Int?
        }

        /// Link-ul clipului din care provin poveștile (trebuie să fie deja analizat cu `analyze`).
        var sourceURL: String?
        var places: [PlaceEntry]
    }

    var help: String {
        "Importă povești grupate pe locuri, cu tipul lor și segmentul din clipul sursă."
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let console = context.console
        let db = app.db

        let input = try JSONDecoder().decode(ImportFile.self, from: Data(contentsOf: URL(fileURLWithPath: signature.file)))
        let source = try await input.sourceURL
            .flatMap(YouTube.videoID(from:))
            .asyncFlatMap { id in
                try await MediaSource.query(on: db).filter(\.$kind == "youtube").filter(\.$externalID == id).first()
            }
        let geocoder = Geocoder(client: app.client, contact: Environment.get("NOMINATIM_CONTACT") ?? "contact@example.com")

        var report: [(place: Place, stories: [Story])] = []
        var skipped: [String] = []

        for entry in input.places {
            let place: Place
            if let existing = try await Place.query(on: db).filter(\.$slug == Slug.make(from: entry.name)).first() {
                place = existing
                if signature.publish, place.status != .published {
                    place.status = .published
                    try await place.save(on: db)
                }
            } else {
                guard let point = try await locate(entry, using: geocoder) else {
                    console.warning("✗ \(entry.name): nu am găsit coordonate, sar peste.")
                    skipped.append(entry.name)
                    continue
                }
                place = Place(
                    name: entry.name,
                    summary: entry.summary,
                    category: entry.category,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    address: point.displayName,
                    status: signature.publish ? .published : .draft
                )
                try await place.save(on: db)
            }

            let placeID = try place.requireID()
            let existingStories = try await place.$stories.query(on: db).all()
            var position = existingStories.count
            var added: [Story] = []
            var updated = 0

            for item in entry.stories {
                // Poveștile existente (același titlu) se actualizează din fișier, ca editările să ajungă în aplicație.
                let story: Story
                if let existing = existingStories.first(where: { Slug.make(from: $0.title) == Slug.make(from: item.title) }) {
                    story = existing
                    story.body = item.body
                    story.personalities = item.personalities ?? []
                    updated += 1
                } else {
                    story = Story(placeID: placeID, title: item.title, body: item.body,
                                  position: position, personalities: item.personalities ?? [])
                    added.append(story)
                    position += 1
                }
                story.kind = item.kind
                if let source, let start = item.startSeconds {
                    let segment = Self.clipSegment(start: start, end: item.endSeconds)
                    story.videoKind = .youtube
                    story.youtubeID = source.externalID
                    story.startSeconds = segment.start
                    story.endSeconds = segment.end
                    story.sourceTitle = source.title
                    story.sourceChannel = source.channel
                    story.sourceURL = "https://youtu.be/\(source.externalID)?t=\(start)"
                }
                try await story.save(on: db)
            }

            console.success("✓ \(place.name): \(added.count) noi, \(updated) actualizate (\(place.status.rawValue))")
            report.append((place, existingStories + added))
        }

        let reportFile = URL(fileURLWithPath: signature.file).deletingPathExtension().appendingPathExtension("md")
        try Self.markdown(report).write(to: reportFile, atomically: true, encoding: .utf8)
        console.info("Raport pe locuri: \(reportFile.path)")
        if !skipped.isEmpty {
            console.warning("Fără coordonate: \(skipped.joined(separator: ", ")). Adaugă latitude/longitude în fișier.")
        }
    }

    /// Segmentul redat în aplicație: 20–90 de secunde, ca un reel.
    static func clipSegment(start: Int, end: Int?) -> (start: Int, end: Int) {
        let rawEnd = max(end ?? start + 45, start + 20)
        return (start, min(rawEnd, start + 90))
    }

    private func locate(_ entry: ImportFile.PlaceEntry, using geocoder: Geocoder) async throws -> GeocodedPoint? {
        if let latitude = entry.latitude, let longitude = entry.longitude {
            return GeocodedPoint(latitude: latitude, longitude: longitude, displayName: entry.name)
        }
        for query in entry.searchQueries ?? ["\(entry.name), București"] {
            let point = try await geocoder.locate(query)
            try await Task.sleep(for: .seconds(1.1))
            if let point { return point }
        }
        return nil
    }

    static let kindTitles: [StoryKind: String] = [
        .history: "Istorie", .curiosity: "Curiozitate", .gossip: "Bârfă", .etymology: "Etimologie",
        .food: "Gastronomie", .legend: "Legendă", .person: "Personalitate",
    ]

    static func markdown(_ groups: [(place: Place, stories: [Story])]) -> String {
        var lines = ["# Povești pe locuri", ""]
        var people: [String: [(place: String, title: String)]] = [:]

        for (place, stories) in groups {
            lines += ["## \(place.name)", "", "_\(place.summary)_", ""]
            for kind in StoryKind.allCases {
                let matching = stories.filter { ($0.kind ?? .history) == kind }
                guard !matching.isEmpty else { continue }
                lines.append("**\(kindTitles[kind] ?? kind.rawValue)**")
                for story in matching {
                    let link = story.sourceURL.map { " ([clip](\($0)))" } ?? ""
                    lines.append("- **\(story.title)**: \(story.body)\(link)")
                    for person in story.personalities {
                        people[person, default: []].append((place.name, story.title))
                    }
                }
                lines.append("")
            }
        }

        lines += ["# Personalități", ""]
        for (person, mentions) in people.sorted(by: { ($0.value.count, $1.key) > ($1.value.count, $0.key) }) {
            let places = mentions.map { "\($0.place) („\($0.title)”)" }.joined(separator: "; ")
            lines.append("- **\(person)**: \(places)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension Optional {
    func asyncFlatMap<U>(_ transform: (Wrapped) async throws -> U?) async rethrows -> U? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
