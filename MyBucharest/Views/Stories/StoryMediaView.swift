import SwiftUI

struct StoryMediaView: View {
    let video: StoryVideo?
    var audioURL: String? = nil
    let category: PlaceCategory
    let isActive: Bool
    var rate: Float = 1
    let api: APIClient

    var body: some View {
        switch video?.kind {
        case .hosted:
            if let url = api.resolve(video?.url) {
                LoopingVideoPlayer(url: url, isActive: isActive, rate: rate)
            } else {
                placeholder
            }
        case .youtube:
            if let id = video?.youtubeID {
                YouTubePlayerView(
                    videoID: id,
                    startSeconds: video?.startSeconds,
                    endSeconds: video?.endSeconds,
                    isActive: isActive,
                    rate: rate
                )
            } else {
                placeholder
            }
        case nil:
            placeholder
                .overlay {
                    if let url = api.resolve(audioURL) {
                        NarrationPlayer(url: url, isActive: isActive, rate: rate)
                    }
                }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [category.color, category.color.opacity(0.4), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: category.symbol)
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(.white.opacity(0.15))
                .offset(y: -80)
        }
    }
}
