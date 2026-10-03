import AVFoundation
import AudioToolbox
import UIKit

final class BellSoundPlayer {
    enum Bell {
        case startEnd
        case thirtySeconds
        case countdownBeep

        var resourceName: String {
            switch self {
            case .startEnd:
                return "bell_start_end"
            case .thirtySeconds:
                return "bell_30_seconds"
            case .countdownBeep:
                return "countdown_beep"
            }
        }
    }

    private var players: [Bell: AVAudioPlayer] = [:]
    private var scheduledBeepPlayers: [AVAudioPlayer] = []
    private let audioQueue = DispatchQueue(label: "com.baekmac.boxbell.audio")
    private var deactivateWorkItem: DispatchWorkItem?

    init() {
        audioQueue.async { [weak self] in
            self?.configurePassiveAudioSession()
            self?.preparePlayer(for: .startEnd)
            self?.preparePlayer(for: .thirtySeconds)
            self?.preparePlayer(for: .countdownBeep)
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

        if bell == .countdownBeep {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // 비프음을 오디오 장치 시계 기준으로 미리 예약해 간격이 흔들리지 않게 한다.
    // 예약된 동안에는 오디오 세션을 켜 둔 채로 유지한다.
    func scheduleCountdownBeeps(at dates: [Date]) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            stopScheduledBeeps()

            let delays = dates.map { $0.timeIntervalSinceNow }.filter { $0 > 0.05 }
            guard
                let lastDelay = delays.max(),
                let url = Bundle.main.url(forResource: Bell.countdownBeep.resourceName, withExtension: "wav")
            else { return }

            configureAndActivateAudioSession()
            deactivateWorkItem?.cancel()

            for delay in delays {
                guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.prepareToPlay()
                player.play(atTime: player.deviceCurrentTime + delay)
                scheduledBeepPlayers.append(player)
            }

            scheduleAudioSessionDeactivation(after: lastDelay + 1.5)
        }
    }

    func cancelCountdownBeeps() {
        audioQueue.async { [weak self] in
            self?.stopScheduledBeeps()
        }
    }

    func countdownHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func deactivate() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            deactivateWorkItem?.cancel()
            players.values.forEach { $0.stop() }
            stopScheduledBeeps()

            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                configurePassiveAudioSession()
            } catch {
                return
            }
        }
    }

    private func stopScheduledBeeps() {
        scheduledBeepPlayers.forEach { $0.stop() }
        scheduledBeepPlayers.removeAll()
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
                .ambient,
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
