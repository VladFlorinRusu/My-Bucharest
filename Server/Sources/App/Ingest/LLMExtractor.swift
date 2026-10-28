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

/// Client pentru orice API compatibil OpenAI `/chat/completions`
/// (OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio etc.).
struct LLMExtractor {
    var baseURL: String
    var apiKey: String?
    var model: String
    var client: any Client

    static func fromEnvironment(client: any Client) throws -> LLMExtractor {
        guard let model = Environment.get("LLM_MODEL"), !model.isEmpty else {
            throw Abort(.internalServerError, reason: "Setează LLM_MODEL (și LLM_API_KEY / LLM_BASE_URL dacă e cazul).")
        }
        return LLMExtractor(
            baseURL: Environment.get("LLM_BASE_URL") ?? "https://api.openai.com/v1",
            apiKey: Environment.get("LLM_API_KEY"),
            model: model,
            client: client
        )
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

        let request = ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            temperature: 0.2,
            responseFormat: .init(type: "json_object")
        )

        let response = try await client.post(URI(string: baseURL + "/chat/completions")) { req in
            if let apiKey { req.headers.bearerAuthorization = .init(token: apiKey) }
            try req.content.encode(request, as: .json)
        }
        guard response.status == .ok else {
            let detail = response.body.map { String(buffer: $0) } ?? ""
            throw Abort(.badGateway, reason: "LLM a răspuns cu \(response.status.code): \(detail.prefix(500))")
        }

        let completion = try response.content.decode(ChatResponse.self)
        guard let content = completion.choices.first?.message.content else { return [] }
        return try JSONDecoder().decode(ExtractionResult.self, from: Data(Self.stripCodeFence(content).utf8)).places
    }

    private static func stripCodeFence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            result = result.drop { $0 != "\n" }.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.hasSuffix("```") { result.removeLast(3) }
        }
        return result
    }
}

private struct ChatRequest: Content {
    struct Message: Content {
        var role: String
        var content: String
    }
    struct ResponseFormat: Content {
        var type: String
    }

    var model: String
    var messages: [Message]
    var temperature: Double
    var responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
    }
}

private struct ChatResponse: Content {
    struct Choice: Content {
        struct Message: Content {
            var content: String?
        }
        var message: Message
    }
    var choices: [Choice]
}
