import Foundation

enum RoundDurationMode: String, CaseIterable, Identifiable {
    case threeMinutes
    case twoMinutes
    case custom

    var id: String { rawValue }
}

@MainActor
final class BoxingTimerViewModel: ObservableObject {
    @Published var phase: TimerPhase = .ready
    @Published var currentRound = 1
    @Published var totalRounds = 3 {
        didSet { updateExternalTimerStateAfterSettingChange() }
    }
    @Published var isInfiniteRounds = false {
        didSet { updateExternalTimerStateAfterSettingChange() }
    }
    @Published var restSeconds = 60 {
        didSet {
            updateExternalTimerStateAfterSettingChange()
        }
    }
    @Published var roundDurationMode: RoundDurationMode = .threeMinutes {
        didSet { applyRoundDurationMode() }
    }
    @Published var customRoundMinutes = 3 {
        didSet { applyRoundDurationMode() }
    }
    @Published private(set) var roundSeconds = 180
    @Published var remainingSeconds = 180
    @Published var isRunning = false
    @Published var warningFlashTrigger = 0
    @Published var bellRingTrigger = 0

    let restOptions = [30, 60]
    let roundOptions = Array(1...12)
    let customRoundMinuteRange = 1...60

    private var timer: Timer?
    private var segmentEndDate: Date?
    private var warningFiredForCurrentRound = false
    private let soundPlayer = BellSoundPlayer()
    private let backgroundAlarmScheduler = BoxbellAlarmScheduler()
    private var sessionID = UUID().uuidString

    init() {
        backgroundAlarmScheduler.cancelScheduledAlarms()
    }

    var segmentTotalSeconds: Int {
        switch phase {
        case .ready, .round:
            return roundSeconds
        case .rest:
            return restSeconds
        case .finished:
            return roundSeconds
        }
    }

    var progress: Double {
        guard segmentTotalSeconds > 0 else { return 0 }
        return 1 - (Double(remainingSeconds) / Double(segmentTotalSeconds))
    }

    var timeText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var canEditTimerSettings: Bool {
        phase == .ready || phase == .finished
    }

    var roundSettingText: String {
        if isInfiniteRounds {
            return "∞"
        }

        return "\(totalRounds)"
    }

    func start() {
        if phase == .ready {
            backgroundAlarmScheduler.cancelScheduledAlarms()
            sessionID = UUID().uuidString
            phase = .round
            remainingSeconds = roundSeconds
            warningFiredForCurrentRound = false
            playBell(.startEnd)
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        } else {
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        }

        isRunning = true
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func reset() {
        stopInAppTimer()
        backgroundAlarmScheduler.cancelScheduledAlarms()
        sessionID = UUID().uuidString
        phase = .ready
        currentRound = 1
        remainingSeconds = roundSeconds
        warningFiredForCurrentRound = false
    }

    func refreshFromClock() {
        refreshFromClock(playSounds: false)
    }

    func scheduleBackgroundAlarms(languageCode: String) {
        guard isRunning else { return }

        refreshFromClock(playSounds: false)
        guard phase == .round || phase == .rest else { return }

        backgroundAlarmScheduler.scheduleSession(
            sessionID: sessionID,
            languageCode: languageCode,
            phase: phase,
            currentRound: currentRound,
            totalRounds: totalRounds,
            isInfiniteRounds: isInfiniteRounds,
            roundSeconds: roundSeconds,
            restSeconds: restSeconds,
            remainingSeconds: remainingSeconds
        )
    }

    func cancelBackgroundAlarmsAndRefresh() {
        backgroundAlarmScheduler.cancelScheduledAlarms()
        refreshFromClock(playSounds: false)
    }

    private func stopInAppTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        segmentEndDate = nil
    }

    func incrementRoundSetting() {
        guard canEditTimerSettings else { return }

        if isInfiniteRounds {
            return
        }

        if totalRounds >= 12 {
            isInfiniteRounds = true
        } else {
            totalRounds += 1
        }
    }

    func decrementRoundSetting() {
        guard canEditTimerSettings else { return }

        if isInfiniteRounds {
            isInfiniteRounds = false
            totalRounds = 12
        } else if totalRounds > 1 {
            totalRounds -= 1
        }

        currentRound = min(currentRound, totalRounds)
    }

    func setCustomRoundMinutes(_ minutes: Int) {
        customRoundMinutes = min(max(minutes, customRoundMinuteRange.lowerBound), customRoundMinuteRange.upperBound)
    }

    private func tick() {
        guard isRunning else { return }

        refreshFromClock(playSounds: true)
    }

    private func advancePhase(playSound: Bool) {
        switch phase {
        case .ready:
            phase = .round
            remainingSeconds = roundSeconds
            warningFiredForCurrentRound = false
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        case .round:
            if !isInfiniteRounds && currentRound >= totalRounds {
                stopInAppTimer()
                backgroundAlarmScheduler.cancelScheduledAlarms()
                phase = .ready
                currentRound = 1
                remainingSeconds = roundSeconds
                warningFiredForCurrentRound = false
            } else {
                phase = .rest
                remainingSeconds = restSeconds
                warningFiredForCurrentRound = false
                segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            }
            if playSound {
                playBell(.startEnd)
            }
        case .rest:
            currentRound += 1
            phase = .round
            remainingSeconds = roundSeconds
            warningFiredForCurrentRound = false
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            if playSound {
                playBell(.startEnd)
            }
        case .finished:
            reset()
        }
    }

    private func refreshFromClock(playSounds: Bool) {
        guard isRunning, let endDate = segmentEndDate else { return }

        var now = Date()
        var activeEndDate = endDate
        var didCrossBoundary = false

        while now >= activeEndDate && isRunning {
            let boundaryDate = activeEndDate
            didCrossBoundary = true
            advancePhase(playSound: playSounds)
            guard isRunning else { return }
            activeEndDate = boundaryDate.addingTimeInterval(TimeInterval(segmentTotalSeconds))
            segmentEndDate = activeEndDate
            now = Date()
        }

        guard isRunning else { return }

        remainingSeconds = max(0, Int(ceil(activeEndDate.timeIntervalSince(now))))

        if didCrossBoundary {
            segmentEndDate = activeEndDate
        }

        if phase == .round,
           !warningFiredForCurrentRound,
           remainingSeconds <= 30,
           remainingSeconds > 0 {
            warningFiredForCurrentRound = true
            warningFlashTrigger += 1
            if playSounds {
                playBell(.thirtySeconds)
            }
        }
    }

    private func playBell(_ bell: BellSoundPlayer.Bell) {
        bellRingTrigger += 1
        soundPlayer.play(bell)
    }

    private func applyRoundDurationMode() {
        switch roundDurationMode {
        case .threeMinutes:
            roundSeconds = 180
        case .twoMinutes:
            roundSeconds = 120
        case .custom:
            roundSeconds = customRoundMinutes * 60
        }

        if phase == .ready || phase == .finished {
            remainingSeconds = roundSeconds
        }

        updateExternalTimerStateAfterSettingChange()
    }

    private func updateExternalTimerStateAfterSettingChange() {
        if phase == .ready || phase == .finished {
            remainingSeconds = roundSeconds
        }

        if isRunning {
            refreshFromClock(playSounds: false)
        }
    }
}
