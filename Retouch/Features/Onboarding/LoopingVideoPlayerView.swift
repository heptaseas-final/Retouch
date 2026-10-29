//
//  LoopingVideoPlayerView.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 29/10/26.
//


import SwiftUI
import AVFoundation

struct LoopingVideoPlayerView: UIViewRepresentable {
    let videoName: String
    let videoExtension: String

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(videoName: videoName, videoExtension: videoExtension)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
    }
}

final class LoopingPlayerUIView: UIView {
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    init(videoName: String, videoExtension: String) {
        super.init(frame: .zero)

        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            #if DEBUG
            print("⚠️ Onboarding video not found in bundle: \(videoName).\(videoExtension)")
            #endif
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false

        let looper = AVPlayerLooper(player: player, templateItem: item)

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)

        self.queuePlayer = player
        self.playerLooper = looper

        player.play()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func pause() {
        queuePlayer?.pause()
    }

    func resume() {
        queuePlayer?.play()
    }
}
