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

    init(
        items: [FeedItem],
        initialItemID: UUID? = nil,
        isVisible: Bool = true,
        showsSaveButton: Bool = true,
        showsMapButton: Bool = false
    ) {
        self.items = items
        self.initialItemID = initialItemID
        self.isVisible = isVisible
        self.showsSaveButton = showsSaveButton
        self.showsMapButton = showsMapButton
        // Poziția de start trebuie să existe înainte de primul layout, altfel ScrollView pornește
        // de la prima pagină chiar dacă povestea activă e alta.
        _activeItemID = State(initialValue: initialItemID ?? items.first?.id)
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets

            ScrollViewReader { reader in
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
                .task {
                    // Poziția inițială din `scrollPosition` nu e aplicată sigur la prima afișare a unui
                    // LazyVStack, așa că derulăm explicit la povestea aleasă după primul layout.
                    guard let initialItemID, initialItemID != items.first?.id else { return }
                    await Task.yield()
                    reader.scrollTo(initialItemID, anchor: .top)
                }
            }
        }
        .background(.black)
        .onChange(of: items.map(\.id)) { _, newIDs in
            activeItemID = newIDs.first
        }
    }
}
