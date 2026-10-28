import SwiftUI

extension PlaceCategory {
    var title: String {
        switch self {
        case .building: "Clădiri"
        case .street: "Străzi"
        case .monument: "Monumente"
        case .church: "Biserici"
        case .park: "Parcuri"
        case .museum: "Muzee"
        case .memorial: "Personalități"
        case .other: "Altele"
        }
    }

    var symbol: String {
        switch self {
        case .building: "building.2.fill"
        case .street: "road.lanes"
        case .monument: "building.columns.fill"
        case .church: "cross.fill"
        case .park: "leaf.fill"
        case .museum: "paintpalette.fill"
        case .memorial: "person.fill"
        case .other: "mappin"
        }
    }

    var color: Color {
        switch self {
        case .building: .indigo
        case .street: .orange
        case .monument: .red
        case .church: .brown
        case .park: .green
        case .museum: .purple
        case .memorial: .teal
        case .other: .gray
        }
    }
}

struct PlacePin: View {
    let category: PlaceCategory
    var isHighlighted = false

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(category.color.gradient, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .scaleEffect(isHighlighted ? 1.25 : 1)
            .animation(.spring(duration: 0.3), value: isHighlighted)
    }
}
