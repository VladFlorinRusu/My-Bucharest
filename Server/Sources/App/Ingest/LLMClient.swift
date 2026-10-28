import Foundation
import Vapor

/// Client pentru orice API compatibil OpenAI `/chat/completions`
/// (OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio etc.).
struct LLMClient {
    var baseURL: String
    var apiKey: String?
    var model: String
    var client: any Client

    static func fromEnvironment(client: any Client) throws -> LLMClient {
        guard let model = Environment.get("LLM_MODEL"), !model.isEmpty else {
            throw Abort(.internalServerError, reason: "Setează LLM_MODEL (și LLM_API_KEY / LLM_BASE_URL dacă e cazul).")
        }
        return LLMClient(
            baseURL: Environment.get("LLM_BASE_URL") ?? "https://api.openai.com/v1",
            apiKey: Environment.get("LLM_API_KEY"),
            model: model,
            client: client
        )
    }

    /// Trimite un prompt și decodează răspunsul, care trebuie să fie un obiect JSON.
    func completeJSON<T: Decodable>(_ type: T.Type, system: String, user: String) async throws -> T {
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
        guard let content = completion.choices.first?.message.content else {
            throw Abort(.badGateway, reason: "LLM a întors un răspuns gol.")
        }
        return try JSONDecoder().decode(T.self, from: Data(Self.stripCodeFence(content).utf8))
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
