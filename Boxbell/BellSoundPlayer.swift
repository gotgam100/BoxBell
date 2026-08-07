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
    private var deactivateWorkItem: DispatchWorkItem?

    init() {
        audioQueue.async { [weak self] in
            self?.configurePassiveAudioSession()
            self?.preparePlayer(for: .startEnd)
            self?.preparePlayer(for: .thirtySeconds)
        }
    }

    func play(_ bell: Bell) {
        audioQueue.async { [weak self] in
            guard let self else { return }

            if let player = players[bell] {
                configureAndActivateAudioSession()
                player.currentTime = 0
                player.play()
                scheduleAudioSessionDeactivation(after: player.duration)
            } else {
                AudioServicesPlaySystemSound(1057)
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func configureAndActivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
    }

    private func configurePassiveAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
        } catch {
            return
        }
    }

    private func scheduleAudioSessionDeactivation(after duration: TimeInterval) {
        deactivateWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                self.configurePassiveAudioSession()
            } catch {
                return
            }
        }

        deactivateWorkItem = workItem
        audioQueue.asyncAfter(deadline: .now() + max(duration, 0.5), execute: workItem)
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
