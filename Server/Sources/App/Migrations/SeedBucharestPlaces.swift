import Fluent

/// Câteva locuri publicate, ca aplicația să aibă ce afișa înainte de primul ingest.
struct SeedBucharestPlaces: AsyncMigration {
    private struct Seed {
        let name: String
        let category: PlaceCategory
        let latitude: Double
        let longitude: Double
        let address: String
        let summary: String
        let storyTitle: String
        let storyBody: String
        let personalities: [String]
        var storyKind: StoryKind = .history
    }

    private let seeds: [Seed] = [
        Seed(
            name: "Ateneul Român",
            category: .building,
            latitude: 44.44130, longitude: 26.09730,
            address: "Strada Benjamin Franklin 1-3",
            summary: "Sala de concerte simbol a Bucureștiului, inaugurată în 1888.",
            storyTitle: "„Dați un leu pentru Ateneu!”",
            storyBody: "Construcția a fost finanțată în mare parte printr-o subscripție publică: bucureștenii erau îndemnați să doneze câte un leu. Clădirea a fost proiectată de arhitectul francez Albert Galleron, iar în interior se află o frescă de circa 75 de metri care ilustrează istoria românilor.",
            personalities: ["Albert Galleron", "Costin Petrescu"],
            storyKind: .curiosity
        ),
        Seed(
            name: "Palatul Parlamentului",
            category: .building,
            latitude: 44.42750, longitude: 26.08750,
            address: "Strada Izvor 2-4",
            summary: "Una dintre cele mai mari clădiri administrative din lume.",
            storyTitle: "Un cartier întreg pentru un palat",
            storyBody: "Lucrările au început în 1984, după demolarea unei mari părți din cartierul istoric Uranus. Proiectul a fost coordonat de arhitecta Anca Petrescu, care avea puțin peste 30 de ani când a câștigat concursul.",
            personalities: ["Anca Petrescu"]
        ),
        Seed(
            name: "Arcul de Triumf",
            category: .monument,
            latitude: 44.46720, longitude: 26.07810,
            address: "Piața Arcul de Triumf",
            summary: "Monument dedicat independenței și Marii Uniri.",
            storyTitle: "Trei arcuri în același loc",
            storyBody: "Primul arc, din lemn, a fost ridicat în 1878 pentru întoarcerea trupelor din Războiul de Independență. A urmat unul din beton și ipsos în 1922, iar forma de piatră de astăzi, proiectată de Petre Antonescu, a fost inaugurată în 1936.",
            personalities: ["Petre Antonescu"]
        ),
        Seed(
            name: "Hanul lui Manuc",
            category: .building,
            latitude: 44.43070, longitude: 26.10030,
            address: "Strada Franceză 62-64",
            summary: "Cel mai vechi han din București care încă funcționează.",
            storyTitle: "Unde s-a negociat pacea din 1812",
            storyBody: "Hanul a fost ridicat în 1808 de negustorul armean Manuc Bei. În 1812, aici au avut loc negocieri premergătoare Tratatului de pace de la București, încheiat între Imperiul Rus și Imperiul Otoman.",
            personalities: ["Manuc Bei"]
        ),
        Seed(
            name: "Biserica Stavropoleos",
            category: .church,
            latitude: 44.43140, longitude: 26.09780,
            address: "Strada Stavropoleos 4",
            summary: "Bijuterie a stilului brâncovenesc în Centrul Vechi.",
            storyTitle: "O biserică mai veche decât cartierul din jur",
            storyBody: "Biserica a fost construită în 1724 de ieromonahul grec Ioanichie Stratonikeas, în jurul unui han care susținea mănăstirea. Hanul a dispărut, dar biserica a supraviețuit și păstrează o colecție importantă de manuscrise și muzică bizantină.",
            personalities: ["Ioanichie Stratonikeas"]
        ),
        Seed(
            name: "Palatul CEC",
            category: .building,
            latitude: 44.43130, longitude: 26.09630,
            address: "Calea Victoriei 13",
            summary: "Sediul istoric al Casei de Depuneri, cu cupola de sticlă și metal.",
            storyTitle: "Construit pe locul unei mănăstiri",
            storyBody: "Palatul, inaugurat în 1900 și proiectat de arhitectul francez Paul Gottereau, a fost ridicat pe locul fostei mănăstiri Sfântul Ioan cel Mare. Este unul dintre cele mai fotografiate edificii de pe Calea Victoriei.",
            personalities: ["Paul Gottereau"]
        ),
        Seed(
            name: "Caru' cu Bere",
            category: .building,
            latitude: 44.43170, longitude: 26.09860,
            address: "Strada Stavropoleos 5",
            summary: "Berărie istorică, deschisă în 1879.",
            storyTitle: "O berărie în stil neogotic",
            storyBody: "Localul a fost deschis în 1879, iar clădirea neogotică de azi, cu vitralii și picturi murale, datează din 1899. Interiorul a rămas aproape neschimbat de peste un secol.",
            personalities: []
        ),
    ]

    func prepare(on database: any Database) async throws {
        for seed in seeds {
            let place = Place(
                name: seed.name,
                summary: seed.summary,
                category: seed.category,
                latitude: seed.latitude,
                longitude: seed.longitude,
                address: seed.address,
                status: .published
            )
            try await place.save(on: database)
            let story = Story(
                placeID: try place.requireID(),
                title: seed.storyTitle,
                body: seed.storyBody,
                position: 0,
                personalities: seed.personalities
            )
            story.kind = seed.storyKind
            try await story.save(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        let slugs = seeds.map { Slug.make(from: $0.name) }
        try await Place.query(on: database).filter(\.$slug ~~ slugs).delete()
    }
}
