import Foundation
import Vapor

protocol SpeechSynthesizer: Sendable {
    var name: String { get }
    /// Generează vocea pentru `text` în `directory` și întoarce fișierul audio rezultat.
    func synthesize(_ text: String, in directory: URL) async throws -> URL
}

enum SpeechSynthesizers {
    /// `TTS_MODEL` setat -> API compatibil OpenAI `/audio/speech`.
    /// Altfel, pe macOS -> comanda `say` cu vocea românească Ioana (bună pentru dezvoltare).
    static func fromEnvironment(client: any Client) throws -> any SpeechSynthesizer {
        if let model = Environment.get("TTS_MODEL"), !model.isEmpty {
            return OpenAICompatibleSpeech(
                baseURL: Environment.get("TTS_BASE_URL") ?? Environment.get("LLM_BASE_URL") ?? "https://api.openai.com/v1",
                apiKey: Environment.get("TTS_API_KEY") ?? Environment.get("LLM_API_KEY"),
                model: model,
                voice: Environment.get("TTS_VOICE") ?? "alloy",
                instructions: Environment.get("TTS_INSTRUCTIONS"),
                client: client
            )
        }
        #if os(macOS)
        return MacSaySpeech(voice: Environment.get("SAY_VOICE") ?? "Ioana")
        #else
        throw Abort(.internalServerError, reason: "Setează TTS_MODEL (și TTS_API_KEY) pentru generarea vocii.")
        #endif
    }
}

struct OpenAICompatibleSpeech: SpeechSynthesizer {
    var baseURL: String
    var apiKey: String?
    var model: String
    var voice: String
    var instructions: String?
    var client: any Client

    var name: String { "\(model) / \(voice)" }

    private struct Body: Content {
        var model: String
        var input: String
        var voice: String
        var responseFormat = "mp3"
        var instructions: String?

        enum CodingKeys: String, CodingKey {
            case model, input, voice, instructions
            case responseFormat = "response_format"
        }
    }

    func synthesize(_ text: String, in directory: URL) async throws -> URL {
        let body = Body(model: model, input: text, voice: voice, instructions: instructions)
        let response = try await client.post(URI(string: baseURL + "/audio/speech")) { req in
            if let apiKey { req.headers.bearerAuthorization = .init(token: apiKey) }
            try req.content.encode(body, as: .json)
        }
        guard response.status == .ok, let buffer = response.body else {
            let detail = response.body.map { String(buffer: $0) } ?? ""
            throw Abort(.badGateway, reason: "TTS a răspuns cu \(response.status.code): \(detail.prefix(500))")
        }
        let file = directory.appendingPathComponent("voice.mp3")
        try Data(buffer: buffer).write(to: file)
        return file
    }
}

#if os(macOS)
struct MacSaySpeech: SpeechSynthesizer {
    var voice: String

    var name: String { "macOS say / \(voice)" }

    func synthesize(_ text: String, in directory: URL) async throws -> URL {
        let input = directory.appendingPathComponent("narration.txt")
        let output = directory.appendingPathComponent("voice.aiff")
        try text.write(to: input, atomically: true, encoding: .utf8)
        try ProcessRunner.run("say", ["-v", voice, "-f", input.path, "-o", output.path])
        return output
    }
}
#endif
