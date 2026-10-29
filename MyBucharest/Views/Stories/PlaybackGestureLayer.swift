import SwiftUI
import UIKit

/// Atingere = pauză / redare, ținut apăsat = 2×, fără să blocheze derularea feed-ului.
///
/// Gesturile UIKit coexistă nativ cu scroll-ul: atingerea și ținutul apăsat eșuează imediat ce
/// degetul se mișcă, iar glisarea ajunge la feed. Varianta SwiftUI (LongPress + Drag) prelua
/// glisările pornite de pe video și feed-ul derula doar de pe zona cu text.
struct PlaybackGestureLayer: UIViewRepresentable {
    var onTap: () -> Void
    var onHoldChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHold(_:)))
        hold.minimumPressDuration = 0.3
        hold.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.require(toFail: hold)
        tap.delegate = context.coordinator

        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onHoldChanged = onHoldChanged
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void = {}
        var onHoldChanged: (Bool) -> Void = { _ in }

        @objc func handleTap() {
            onTap()
        }

        @objc func handleHold(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began: onHoldChanged(true)
            case .ended, .cancelled, .failed: onHoldChanged(false)
            default: break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
