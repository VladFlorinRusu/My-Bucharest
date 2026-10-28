import SwiftUI

/// Feed vertical, paginat, pe tot ecranul – stil TikTok/Reels.
struct StoryFeedView: View {
    let items: [FeedItem]
    var initialItemID: UUID?
    /// `false` când feed-ul nu e pe ecran (alt tab selectat), ca să nu ruleze video în fundal.
    var isVisible = true
    var showsSaveButton = true
    var showsMapButton = false

    @State private var activeItemID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        StoryPage(
                            item: item,
                            isActive: isVisible && activeItemID == item.id,
                            safeAreaInsets: insets,
                            showsSaveButton: showsSaveButton,
                            showsMapButton: showsMapButton
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeItemID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .background(.black)
        .onAppear {
            if activeItemID == nil {
                activeItemID = initialItemID ?? items.first?.id
            }
        }
        .onChange(of: items) { _, newItems in
            if let activeItemID, newItems.contains(where: { $0.id == activeItemID }) { return }
            activeItemID = newItems.first?.id
        }
    }
}
