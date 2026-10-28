import SwiftUI

extension StoryKind {
    var title: String {
        switch self {
        case .history: "Istorie"
        case .curiosity: "Curiozitate"
        case .gossip: "Bârfă"
        case .etymology: "Etimologie"
        case .food: "Gastronomie"
        case .legend: "Legendă"
        case .person: "Personalitate"
        }
    }

    /// Titlul folosit în filtre, la plural.
    var filterTitle: String {
        switch self {
        case .history: "Istorie"
        case .curiosity: "Curiozități"
        case .gossip: "Bârfe"
        case .etymology: "Etimologie"
        case .food: "Gastronomie"
        case .legend: "Legende"
        case .person: "Personalități"
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .curiosity: "sparkles"
        case .gossip: "bubble.left.and.bubble.right.fill"
        case .etymology: "character.book.closed.fill"
        case .food: "fork.knife"
        case .legend: "wand.and.stars"
        case .person: "person.crop.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .history: .blue
        case .curiosity: .yellow
        case .gossip: .pink
        case .etymology: .teal
        case .food: .orange
        case .legend: .purple
        case .person: .indigo
        }
    }
}

struct StoryKindBadge: View {
    let kind: StoryKind

    var body: some View {
        Label(kind.title, systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(kind.color.opacity(0.6)), in: Capsule())
    }
}
