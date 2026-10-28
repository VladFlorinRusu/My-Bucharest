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
    /// Locurile din raza de proximitate sar și emit unde, ca să le vezi imediat pe hartă.
    var isNearby = false

    var body: some View {
        ZStack {
            if isNearby {
                PulseRing(color: category.color)
            }
            Image(systemName: category.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(category.color.gradient, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .phaseAnimator(isNearby ? [0.0, -8.0] : [0.0]) { pin, offset in
                    pin.offset(y: offset)
                } animation: { _ in
                    .easeInOut(duration: 0.55)
                }
        }
        .scaleEffect(isHighlighted || isNearby ? 1.2 : 1)
        .animation(.spring(duration: 0.3), value: isHighlighted || isNearby)
    }
}

private struct PulseRing: View {
    let color: Color
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            ring(delay: 0)
            ring(delay: 0.7)
        }
        .allowsHitTesting(false)
        .onAppear { isExpanded = true }
    }

    private func ring(delay: Double) -> some View {
        Circle()
            .stroke(color, lineWidth: 3)
            .frame(width: 34, height: 34)
            .scaleEffect(isExpanded ? 2.6 : 1)
            .opacity(isExpanded ? 0 : 0.9)
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(delay), value: isExpanded)
    }
}
