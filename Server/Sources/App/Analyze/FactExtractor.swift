import Foundation
import Vapor

struct ExtractedFact: Decodable, Sendable {
    var statement: String
    var kind: String?
    var startSeconds: Int?
    var endSeconds: Int?
    var places: [String]?
    var people: [String]?
    var dates: [String]?
    var topics: [String]?
    var importance: Int?
}

/// Extrage faptele esențiale dintr-un transcript, cu etichete și momentul din clip.
struct FactExtractor {
    var llm: LLMClient

    static let suggestedTopics = [
        "arhitectură", "urbanism", "istorie politică", "monarhie", "interbelic", "comunism",
        "religie", "cultură", "artă", "literatură", "muzică", "comerț", "gastronomie",
        "viață cotidiană", "transport", "cutremure", "legende", "personalități", "războaie",
    ]

    func extractFacts(title: String, channel: String?, chunk: [TranscriptBlock]) async throws -> [ExtractedFact] {
        let system = """
        Ești documentarist pentru un ghid despre istoria și curiozitățile Bucureștiului.
        Primești un fragment din transcriptul unui clip sau podcast. Fiecare rând începe cu [t=SECUNDE].

        Extrage informațiile esențiale ca listă de fapte. Pentru fiecare fapt:
        - "statement": 1-2 propoziții reformulate, cu diacritice, care se înțeleg fără restul transcriptului.
        - "kind": "event" (ceva ce s-a întâmplat la o dată/perioadă), "fact" (informație descriptivă), \
        "anecdote" (poveste, curiozitate) sau "opinion" (părerea vorbitorului, nu un fapt verificabil).
        - "startSeconds" / "endSeconds": numere întregi, luate din marcajele [t=...] ale rândurilor relevante.
        - "places": locuri din București (denumirea uzuală completă, ex. "Ateneul Român", "Calea Victoriei").
        - "people": persoane reale, cu numele complet când reiese din context.
        - "dates": ani sau perioade ("1888", "1930-1940", "perioada interbelică").
        - "topics": 1-3 teme, preferabil din: \(Self.suggestedTopics.joined(separator: ", ")).
        - "importance": 3 = esențial, 2 = interesant, 1 = detaliu.

        Reguli:
        - Nu inventa nimic ce nu apare în fragment.
        - Ignoră reclamele, salutările, autopromovarea și digresiunile fără legătură cu Bucureștiul.
        - Transcriptul poate avea greșeli de recunoaștere vocală la nume; corectează-le doar dacă ești sigur.
        - Listele goale se scriu [].

        Răspunde exclusiv cu JSON: {"facts":[{"statement":"","kind":"","startSeconds":0,"endSeconds":0,\
        "places":[],"people":[],"dates":[],"topics":[],"importance":2}]}
        """
        let lines = chunk.map { "[t=\(Int($0.start))] \($0.text)" }.joined(separator: "\n")
        let user = """
        Titlu: \(title)
        Canal: \(channel ?? "necunoscut")

        Fragment:
        \(lines)
        """

        struct Response: Decodable { var facts: [ExtractedFact] }
        return try await llm.completeJSON(Response.self, system: system, user: user).facts
    }

    func summarize(title: String, channel: String?, facts: [Fact]) async throws -> String {
        let system = """
        Ești documentarist pentru un ghid despre București. Primești faptele extrase dintr-un clip.
        Scrie un rezumat de 3-5 propoziții, în română, cu diacritice: despre ce este clipul și care sunt \
        cele mai importante informații. Nu adăuga nimic ce nu apare în fapte.
        Răspunde exclusiv cu JSON: {"summary":""}
        """
        let list = facts
            .sorted { $0.importance > $1.importance }
            .prefix(60)
            .map { "- [\(Timecode.format(Double($0.startSeconds)))] \($0.statement)" }
            .joined(separator: "\n")
        let user = "Titlu: \(title)\nCanal: \(channel ?? "necunoscut")\n\nFapte:\n\(list)"

        struct Response: Decodable { var summary: String }
        return try await llm.completeJSON(Response.self, system: system, user: user).summary
    }
}
