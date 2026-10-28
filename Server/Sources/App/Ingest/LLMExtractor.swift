import Foundation
import Vapor

struct ExtractedStory: Codable, Sendable {
    var title: String
    var body: String
    var personalities: [String]?
    var startSeconds: Int?
    var endSeconds: Int?
}

struct ExtractedPlace: Codable, Sendable {
    var name: String
    var searchQuery: String?
    var category: String
    var summary: String
    var stories: [ExtractedStory]

    var placeCategory: PlaceCategory { PlaceCategory(rawValue: category) ?? .other }
}

private struct ExtractionResult: Codable {
    var places: [ExtractedPlace]
}

/// Extrage locuri și povești pentru aplicație dintr-o transcriere.
struct LLMExtractor {
    var llm: LLMClient

    static func fromEnvironment(client: any Client) throws -> LLMExtractor {
        LLMExtractor(llm: try LLMClient.fromEnvironment(client: client))
    }

    func extractPlaces(video: YouTubeVideoInfo, transcript: String) async throws -> [ExtractedPlace] {
        let categories = PlaceCategory.allCases.map(\.rawValue).joined(separator: ", ")
        let system = """
        Ești un editor care construiește un ghid de curiozități despre București.
        Primești transcrierea unui videoclip YouTube. Extrage DOAR locurile din București \
        (clădiri, străzi, monumente, biserici, parcuri, muzee, case memoriale) despre care clipul spune ceva concret.

        Reguli:
        - Scrie în limba română, cu diacritice.
        - Reformulează cu propriile cuvinte; nu copia fraze din transcriere.
        - Nu inventa fapte care nu apar în transcriere.
        - "body" are 2-4 propoziții, ca un text de reel.
        - "personalities" = persoane reale menționate în legătură cu acel loc.
        - "searchQuery" = denumirea + adresa/zona, bună pentru geocodare (ex: "Ateneul Român, Strada Benjamin Franklin").
        - "category" este una dintre: \(categories).
        - Dacă transcrierea are timestamp-uri, pune în "startSeconds"/"endSeconds" segmentul (15-60s) \
          în care se vorbește despre acea curiozitate; altfel lasă-le null.

        Răspunde exclusiv cu JSON de forma:
        {"places":[{"name":"","searchQuery":"","category":"","summary":"","stories":[{"title":"","body":"","personalities":[],"startSeconds":null,"endSeconds":null}]}]}
        """
        let user = """
        Titlu: \(video.title ?? "necunoscut")
        Canal: \(video.channel ?? "necunoscut")
        Descriere: \(String((video.description ?? "").prefix(2_000)))

        Transcriere:
        \(String(transcript.prefix(60_000)))
        """

        return try await llm.completeJSON(ExtractionResult.self, system: system, user: user).places
    }
}
