import AVFoundation
import SwiftUI

/// Player video pe tot ecranul, în buclă, fără controale – pentru clipuri găzduite pe server.
struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = context.coordinator.player
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if isActive {
            context.coordinator.player.play()
        } else {
            context.coordinator.player.pause()
        }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
    }

    final class Coordinator {
        let player = AVQueuePlayer()
        private let looper: AVPlayerLooper

        init(url: URL) {
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
