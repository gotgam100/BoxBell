import AVFoundation
import AudioToolbox
import UIKit

final class BellSoundPlayer {
    enum Bell {
        case startEnd
        case thirtySeconds

        var resourceName: String {
            switch self {
            case .startEnd:
                return "bell_start_end"
            case .thirtySeconds:
                return "bell_30_seconds"
            }
        }
    }

    private var players: [Bell: AVAudioPlayer] = [:]
    private let audioQueue = DispatchQueue(label: "com.baekmac.boxbell.audio")

    init() {
        audioQueue.async { [weak self] in
            self?.prepareAudioSession()
            self?.preparePlayer(for: .startEnd)
            self?.preparePlayer(for: .thirtySeconds)
        }
    }

    func play(_ bell: Bell) {
        audioQueue.async { [weak self] in
            guard let self else { return }

            if let player = players[bell] {
                player.currentTime = 0
                player.play()
            } else {
                AudioServicesPlaySystemSound(1057)
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func prepareAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
    }

    private func preparePlayer(for bell: Bell) {
        guard let url = Bundle.main.url(forResource: bell.resourceName, withExtension: "wav") else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[bell] = player
        } catch {
            players[bell] = nil
        }
    }
}
