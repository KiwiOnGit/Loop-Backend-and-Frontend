import AVFoundation
import SwiftUI

struct LoopPlayerView: UIViewRepresentable {
    let url: URL
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.videoGravity = .resizeAspectFill
        context.coordinator.configure(url: url, isActive: isActive, view: view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        context.coordinator.configure(url: url, isActive: isActive, view: uiView)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.stop(view: uiView)
    }

    final class Coordinator {
        private var player: AVPlayer?
        private var observer: NSObjectProtocol?
        private var currentURL: URL?
        private var lastActive = false

        func configure(url: URL, isActive: Bool, view: PlayerContainerView) {
            if currentURL != url {
                stop(view: view)
                currentURL = url
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                player.actionAtItemEnd = .none
                self.player = player
                view.player = player

                observer = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self, weak player] _ in
                    guard self?.lastActive == true else {
                        return
                    }
                    player?.seek(to: .zero)
                    player?.play()
                }
            }

            applyPlayback(isActive)
        }

        func stop(view: PlayerContainerView? = nil) {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            view?.player = nil
            observer = nil
            player = nil
            currentURL = nil
            lastActive = false
        }

        private func applyPlayback(_ isActive: Bool) {
            guard let player else {
                return
            }
            if isActive {
                player.play()
            } else {
                player.pause()
                if lastActive {
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            lastActive = isActive
        }
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }
}
