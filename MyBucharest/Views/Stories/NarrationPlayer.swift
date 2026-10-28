import AVFoundation
import SwiftUI

/// Redă vocea unei povești fără video cât timp pagina e activă.
struct NarrationPlayer: View {
    let url: URL
    let isActive: Bool
    var rate: Float = 1

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            .offset(y: -40)
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                update()
            }
            .onChange(of: isActive) { update() }
            .onChange(of: rate) { update() }
            .onDisappear {
                player?.pause()
                isPlaying = false
            }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
                if (note.object as? AVPlayerItem) === player?.currentItem { isPlaying = false }
            }
    }

    private func update() {
        guard let player else { return }
        player.defaultRate = rate
        if isActive {
            if let item = player.currentItem, item.currentTime() >= item.duration {
                player.seek(to: .zero)
            }
            player.rate = rate
        } else {
            player.pause()
        }
        isPlaying = isActive
    }
}
