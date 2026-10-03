import Foundation

enum RoundDurationMode: String, CaseIterable, Identifiable, Codable {
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
    @Published var restDurationMode: RestDurationMode = .sixtySeconds {
        didSet { applyRestDurationMode() }
    }
    @Published var customRestSeconds = 90 {
        didSet { applyRestDurationMode() }
    }
    @Published private(set) var restSeconds = 60
    @Published private(set) var selectedMode: TimerModeSlot
    @Published private(set) var modeNames: [TimerModeSlot: String]
    @Published var roundDurationMode: RoundDurationMode = .threeMinutes {
        didSet { applyRoundDurationMode() }
    }
    @Published var customRoundMinutes = 3 {
        didSet { applyRoundDurationMode() }
    }
    @Published private(set) var roundSeconds = 180
    @Published var remainingSeconds = 180
    @Published var preparationSeconds = 5 {
        didSet { updateExternalTimerStateAfterSettingChange() }
    }
    @Published var isRunning = false
    @Published var warningFlashTrigger = 0
    @Published var bellRingTrigger = 0

    let preparationOptions = [0, 5, 10]
    let roundOptions = 1...12
    let customRoundMinuteRange = 1...60
    let customRestSecondRange = 10...600
    let customRestSecondStep = 10
    let maxModeNameLength = 20

    private var timer: Timer?
    private var segmentEndDate: Date?
    private var warningFiredForCurrentRound = false
    private var lastCountdownBeepSecond: Int?
    private let soundPlayer = BellSoundPlayer()
    private let backgroundAlarmScheduler = BoxbellAlarmScheduler()
    private var sessionID = UUID().uuidString
    private var canPlayInAppSounds = true
    private let modeStore = TimerModeStore()
    private var modeSettings: [TimerModeSlot: TimerModeSettings]
    private var isApplyingModeSettings = false

    init() {
        modeSettings = modeStore.loadSettings()
        selectedMode = modeStore.loadSelectedMode()
        modeNames = modeStore.loadNames()
        backgroundAlarmScheduler.cancelScheduledAlarms()
        applyModeSettings(modeSettings[selectedMode] ?? selectedMode.defaultSettings)
    }

    var segmentTotalSeconds: Int {
        switch phase {
        case .ready, .round:
            return roundSeconds
        case .preparation:
            return preparationSeconds
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

    func start() {
        canPlayInAppSounds = true

        if phase == .ready {
            backgroundAlarmScheduler.cancelScheduledAlarms()
            sessionID = UUID().uuidString
            if preparationSeconds > 0 {
                phase = .preparation
                remainingSeconds = preparationSeconds
                lastCountdownBeepSecond = preparationSeconds
            } else {
                phase = .round
                remainingSeconds = roundSeconds
                playBell(.startEnd)
            }
            warningFiredForCurrentRound = false
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        } else {
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        }

        isRunning = true
        scheduleRemainingCountdownBeeps()
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
        soundPlayer.cancelCountdownBeeps()
        stopInAppTimer()
        backgroundAlarmScheduler.cancelScheduledAlarms()
        canPlayInAppSounds = true
        sessionID = UUID().uuidString
        phase = .ready
        currentRound = 1
        remainingSeconds = roundSeconds
        warningFiredForCurrentRound = false
        lastCountdownBeepSecond = nil
    }

    func refreshFromClock() {
        refreshFromClock(playSounds: false)
    }

    func scheduleBackgroundAlarms(languageCode: String) {
        guard isRunning else { return }

        canPlayInAppSounds = false
        soundPlayer.deactivate()
        refreshFromClock(playSounds: false)
        guard phase == .preparation || phase == .round || phase == .rest else { return }

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
        canPlayInAppSounds = true
        scheduleRemainingCountdownBeeps()
    }

    func deactivateInAppAudio() {
        soundPlayer.deactivate()
    }

    private func stopInAppTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        segmentEndDate = nil
    }

    func setCustomRoundMinutes(_ minutes: Int) {
        customRoundMinutes = min(max(minutes, customRoundMinuteRange.lowerBound), customRoundMinuteRange.upperBound)
    }

    func setCustomRestSeconds(_ seconds: Int) {
        customRestSeconds = min(max(seconds, customRestSecondRange.lowerBound), customRestSecondRange.upperBound)
    }

    // 라운드 수 휠: 1~12는 라운드 수, 13은 무제한을 뜻한다.
    let roundCountValues = Array(1...13)
    let unlimitedRoundCountValue = 13
    let roundMinuteValues = Array(1...60)
    var restSecondValues: [Int] { Array(stride(from: customRestSecondRange.lowerBound, through: customRestSecondRange.upperBound, by: customRestSecondStep)) }

    var roundCountValue: Int {
        isInfiniteRounds ? unlimitedRoundCountValue : totalRounds
    }

    func setRoundCountValue(_ value: Int) {
        guard canEditTimerSettings else { return }

        if value >= unlimitedRoundCountValue {
            isInfiniteRounds = true
        } else {
            isInfiniteRounds = false
            totalRounds = min(max(value, roundOptions.lowerBound), roundOptions.upperBound)
        }
    }

    func setRoundMinutes(_ minutes: Int) {
        guard canEditTimerSettings else { return }

        switch minutes {
        case 2:
            roundDurationMode = .twoMinutes
        case 3:
            roundDurationMode = .threeMinutes
        default:
            setCustomRoundMinutes(minutes)
            roundDurationMode = .custom
        }
    }

    func setRestSeconds(_ seconds: Int) {
        guard canEditTimerSettings else { return }

        switch seconds {
        case 30:
            restDurationMode = .thirtySeconds
        case 60:
            restDurationMode = .sixtySeconds
        default:
            setCustomRestSeconds(seconds)
            restDurationMode = .custom
        }
    }

    func setPreparationSeconds(_ seconds: Int) {
        guard canEditTimerSettings, preparationOptions.contains(seconds) else { return }
        preparationSeconds = seconds
    }

    func displayName(for mode: TimerModeSlot) -> String {
        modeNames[mode] ?? mode.symbol
    }

    // 빈 이름을 저장하면 기본 이름(A, B, C)으로 돌아간다.
    func renameMode(_ mode: TimerModeSlot, to name: String) {
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxModeNameLength))

        if trimmedName.isEmpty || trimmedName == mode.symbol {
            modeNames[mode] = nil
        } else {
            modeNames[mode] = trimmedName
        }
        modeStore.saveNames(modeNames)
    }

    // 모든 모드의 이름과 설정을 앱을 처음 설치했을 때의 상태로 되돌린다.
    func resetAllModes() {
        guard canEditTimerSettings else { return }

        modeNames = [:]
        modeStore.saveNames(modeNames)

        for mode in TimerModeSlot.allCases {
            modeSettings[mode] = mode.defaultSettings
        }
        modeStore.saveSettings(modeSettings)

        selectedMode = .a
        modeStore.saveSelectedMode(.a)
        applyModeSettings(TimerModeSlot.a.defaultSettings)
    }

    func selectMode(_ mode: TimerModeSlot) {
        guard canEditTimerSettings, mode != selectedMode else { return }

        selectedMode = mode
        modeStore.saveSelectedMode(mode)
        applyModeSettings(modeSettings[mode] ?? mode.defaultSettings)
    }

    private func tick() {
        guard isRunning else { return }

        refreshFromClock(playSounds: canPlayInAppSounds)
    }

    private func advancePhase(playSound: Bool) {
        switch phase {
        case .ready:
            if preparationSeconds > 0 {
                phase = .preparation
                remainingSeconds = preparationSeconds
            } else {
                phase = .round
                remainingSeconds = roundSeconds
                if playSound {
                    playBell(.startEnd)
                }
            }
            warningFiredForCurrentRound = false
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        case .preparation:
            phase = .round
            remainingSeconds = roundSeconds
            warningFiredForCurrentRound = false
            segmentEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            if playSound {
                playBell(.startEnd)
            }
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
        playCountdownHapticIfNeeded(playHaptic: playSounds)

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

    // 준비 카운트다운에서 1초가 지날 때마다 비프음이 울리도록 남은 비프음을 정확한 시각에 예약한다.
    // 5초 설정이면 1~4초 지점에 4번 울리고, 5초 지점에는 라운드 시작 벨이 울린다.
    private func scheduleRemainingCountdownBeeps() {
        guard isRunning, canPlayInAppSounds, phase == .preparation, let endDate = segmentEndDate else { return }

        let beepDates = (1..<max(preparationSeconds, 1)).map {
            endDate.addingTimeInterval(TimeInterval($0 - preparationSeconds))
        }
        soundPlayer.scheduleCountdownBeeps(at: beepDates)
    }

    // 비프음은 미리 예약되어 있으므로 매초 진동만 낸다.
    private func playCountdownHapticIfNeeded(playHaptic: Bool) {
        guard phase == .preparation, remainingSeconds > 0 else {
            lastCountdownBeepSecond = nil
            return
        }

        guard remainingSeconds != lastCountdownBeepSecond else { return }

        lastCountdownBeepSecond = remainingSeconds
        if playHaptic {
            soundPlayer.countdownHaptic()
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

    private func applyRestDurationMode() {
        switch restDurationMode {
        case .thirtySeconds:
            restSeconds = 30
        case .sixtySeconds:
            restSeconds = 60
        case .custom:
            restSeconds = customRestSeconds
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

        saveSelectedModeSettings()
    }

    private var currentModeSettings: TimerModeSettings {
        TimerModeSettings(
            totalRounds: totalRounds,
            isInfiniteRounds: isInfiniteRounds,
            roundDurationMode: roundDurationMode,
            customRoundMinutes: customRoundMinutes,
            restDurationMode: restDurationMode,
            customRestSeconds: customRestSeconds,
            preparationSeconds: preparationSeconds
        )
    }

    private func applyModeSettings(_ settings: TimerModeSettings) {
        // 여러 값을 차례로 바꾸는 동안 반쯤 바뀐 설정이 저장되지 않도록 막는다.
        isApplyingModeSettings = true
        totalRounds = min(max(settings.totalRounds, roundOptions.lowerBound), roundOptions.upperBound)
        isInfiniteRounds = settings.isInfiniteRounds
        customRoundMinutes = min(max(settings.customRoundMinutes, customRoundMinuteRange.lowerBound), customRoundMinuteRange.upperBound)
        roundDurationMode = settings.roundDurationMode
        customRestSeconds = min(max(settings.customRestSeconds, customRestSecondRange.lowerBound), customRestSecondRange.upperBound)
        restDurationMode = settings.restDurationMode
        preparationSeconds = preparationOptions.contains(settings.preparationSeconds) ? settings.preparationSeconds : 5
        currentRound = 1
        isApplyingModeSettings = false
    }

    private func saveSelectedModeSettings() {
        guard !isApplyingModeSettings else { return }

        modeSettings[selectedMode] = currentModeSettings
        modeStore.saveSettings(modeSettings)
    }
}
