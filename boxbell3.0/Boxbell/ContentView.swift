import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var timer = BoxingTimerViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.korean.rawValue
    @State private var isShowingSettings = false
    @State private var isWarningFlashActive = false
    @State private var isBellPressed = false
    @State private var didHandleBellTouch = false
    @State private var digitalShakeOffset: CGFloat = 0

    private var localizer: Localizer {
        Localizer(languageCode: appLanguage)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.045, blue: 0.05),
                    Color(red: 0.11, green: 0.018, blue: 0.018),
                    Color(red: 0.015, green: 0.016, blue: 0.018)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if isPad {
                iPadContent
            } else {
                iPhoneContent
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(timer: timer, appLanguage: $appLanguage, localizer: localizer)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: isRoundWarningActive) {
            await runWarningFlash()
        }
        .task(id: timer.bellRingTrigger) {
            await runDigitalTimerShake()
        }
        .onAppear {
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            updateIdleTimer()
        }
        .onChange(of: timer.isRunning) { _, _ in
            updateIdleTimer()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                timer.cancelBackgroundAlarmsAndRefresh()
            } else {
                timer.deactivateInAppAudio()
                if timer.isRunning {
                    timer.scheduleBackgroundAlarms(languageCode: appLanguage)
                }
            }
            updateIdleTimer()
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = timer.isRunning &&
            scenePhase == .active &&
            !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad ||
            UIDevice.current.model.localizedCaseInsensitiveContains("iPad")
    }

    private var iPhoneContent: some View {
        VStack(spacing: 18) {
            header
            timerDial
            digitalTimer
            settings
                .padding(.top, 8)
            guideText
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 42)
        .padding(.bottom, 24)
    }

    private var iPadContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                header
                timerDial(dialSize: 214, bellSize: 196, topPadding: 2)
                digitalTimer(fontSize: 126)
                settings(spacing: 8, padding: 12, dialSize: 58)
                guideText
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                Color.clear
                    .frame(width: 42, height: 42)

                Text("BOXBELL")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel(localizer.text("settings.title"))
            }

            Text(roundCounterText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var timerDial: some View {
        timerDial(dialSize: 260, bellSize: 238, topPadding: 10)
    }

    private func timerDial(dialSize: CGFloat, bellSize: CGFloat, topPadding: CGFloat) -> some View {
        ZStack {
            Circle()
                .inset(by: 6)
                .fill(.black.opacity(0.2))

            Image("TimeBell")
                .resizable()
                .scaledToFit()
                .frame(width: bellSize, height: bellSize)
                .offset(y: 1)
                .scaleEffect(isBellPressed ? 0.93 : 1)
                .animation(.spring(response: 0.14, dampingFraction: 0.58), value: isBellPressed)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !didHandleBellTouch else { return }
                            didHandleBellTouch = true
                            tapBell()
                        }
                        .onEnded { _ in
                            didHandleBellTouch = false
                        }
                )
            .accessibilityLabel(localizer.text("button.start"))

            if timer.phase == .preparation {
                Text(preparationOverlayText)
                    .font(.system(size: max(48, dialSize * 0.28), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.65), radius: 8, x: 0, y: 3)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            Circle()
                .inset(by: 1)
                .stroke(.white.opacity(0.18), lineWidth: 10)
                .allowsHitTesting(false)

            Circle()
                .inset(by: 1)
                .trim(from: 0, to: timer.progress)
                .stroke(
                    timerRingColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: timer.progress)
                .allowsHitTesting(false)
        }
        .frame(width: dialSize, height: dialSize)
        .frame(maxWidth: .infinity)
        .padding(.top, topPadding)
    }

    private var digitalTimer: some View {
        digitalTimer(fontSize: 180)
    }

    private func digitalTimer(fontSize: CGFloat) -> some View {
        Text(timer.timeText)
            .font(.custom("DS-Digital-Bold", size: fontSize))
            .monospacedDigit()
            .minimumScaleFactor(0.62)
            .foregroundStyle(digitalTimerColor)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .offset(x: digitalShakeOffset)
            .accessibilityLabel(timerStatusText)
    }

    private func tapBell() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        animateBellTap()

        if timer.phase == .ready || timer.phase == .finished {
            timer.start()
        } else {
            timer.reset()
        }
    }

    private func animateBellTap() {
        withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
            isBellPressed = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.58)) {
                isBellPressed = false
            }
        }
    }

    private var settings: some View {
        settings(spacing: 12, padding: 16, dialSize: 66)
    }

    private func settings(
        spacing: CGFloat,
        padding: CGFloat,
        dialSize: CGFloat
    ) -> some View {
        VStack(spacing: spacing) {
            modeSelector
                .padding(padding)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(alignment: .top, spacing: 0) {
                WheelDialButton(
                    values: timer.roundCountValues,
                    selection: timer.roundCountValue,
                    title: localizer.text("setting.rounds"),
                    caption: localizer.text("dial.rounds"),
                    size: dialSize,
                    valueText: roundCountDialText,
                    onChange: timer.setRoundCountValue
                )
                .frame(maxWidth: .infinity)

                WheelDialButton(
                    values: timer.roundMinuteValues,
                    selection: timer.roundSeconds / 60,
                    title: localizer.text("settings.round.duration"),
                    caption: localizer.text("dial.round.duration"),
                    size: dialSize,
                    valueText: { clockText(seconds: $0 * 60) },
                    onChange: timer.setRoundMinutes
                )
                .frame(maxWidth: .infinity)

                WheelDialButton(
                    values: timer.restSecondValues,
                    selection: timer.restSeconds,
                    title: localizer.text("settings.rest.duration"),
                    caption: localizer.text("dial.rest"),
                    size: dialSize,
                    valueText: clockText(seconds:),
                    onChange: timer.setRestSeconds
                )
                .frame(maxWidth: .infinity)

                WheelDialButton(
                    values: timer.preparationOptions,
                    selection: timer.preparationSeconds,
                    title: localizer.text("settings.preparation.countdown"),
                    caption: localizer.text("dial.preparation"),
                    size: dialSize,
                    valueText: clockText(seconds:),
                    onChange: timer.setPreparationSeconds
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, padding)
            .padding(.horizontal, padding / 2)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(!timer.canEditTimerSettings)
            .opacity(timer.canEditTimerSettings ? 1 : 0.48)
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 12) {
            Text(localizer.text("settings.mode"))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            HStack(spacing: 8) {
                ForEach(TimerModeSlot.allCases) { mode in
                    let isSelected = timer.selectedMode == mode

                    Button {
                        timer.selectMode(mode)
                    } label: {
                        Text(mode.symbol)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(isSelected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isSelected ? .white : .white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localizer.format("mode.name", mode.symbol))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .disabled(!timer.canEditTimerSettings)
        .opacity(timer.canEditTimerSettings ? 1 : 0.48)
        .sensoryFeedback(.selection, trigger: timer.selectedMode)
    }

    private var guideText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localizer.text("guide.start"))
            Text(localizer.text("guide.settings.locked"))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, -6)
    }

    private func roundCountDialText(_ value: Int) -> String {
        value >= timer.unlimitedRoundCountValue ? "∞" : "\(value)"
    }

    private func clockText(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var roundCounterText: String {
        if timer.isInfiniteRounds {
            return localizer.format("round.counter.infinite", displayedRound)
        }

        return localizer.format("round.counter", displayedRound, timer.totalRounds)
    }

    private var displayedRound: Int {
        switch timer.phase {
        case .ready, .finished:
            return 0
        case .preparation, .round, .rest:
            return timer.currentRound
        }
    }

    private var timerStatusText: String {
        if timer.phase == .round {
            return localizer.format("round.current", timer.currentRound)
        }

        return localizer.text(timer.phase.titleKey)
    }

    private var preparationOverlayText: String {
        appLanguage == AppLanguage.english.rawValue ? "READY" : "준 비"
    }

    private var timerRingColor: Color {
        if timer.phase == .preparation {
            return .white
        }

        if timer.phase == .rest {
            return .green
        }

        return isWarningFlashActive ? .white : Color(red: 0.9, green: 0.02, blue: 0.015)
    }

    private var digitalTimerColor: Color {
        if timer.phase == .preparation {
            return .white
        }

        if timer.phase == .rest {
            return .green
        }

        return Color(red: 1.0, green: 0.05, blue: 0.03)
    }

    private var isRoundWarningActive: Bool {
        timer.phase == .round && timer.remainingSeconds <= 30 && timer.remainingSeconds > 0
    }

    private func runWarningFlash() async {
        guard isRoundWarningActive else {
            isWarningFlashActive = false
            return
        }

        while isRoundWarningActive {
            isWarningFlashActive.toggle()
            try? await Task.sleep(for: .milliseconds(120))
        }

        isWarningFlashActive = false
    }

    private func runDigitalTimerShake() async {
        guard timer.bellRingTrigger > 0 else { return }

        let offsets: [CGFloat] = [-10, 10, -7, 7, -3, 3, 0]
        for offset in offsets {
            withAnimation(.linear(duration: 0.035)) {
                digitalShakeOffset = offset
            }
            try? await Task.sleep(for: .milliseconds(35))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var timer: BoxingTimerViewModel
    @Binding var appLanguage: String
    let localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section(localizer.text("settings.language")) {
                    SettingsOptionPicker(
                        selection: $appLanguage,
                        options: AppLanguage.allCases.map { ($0.rawValue, localizer.text($0.titleKey)) }
                    )
                    .settingsOptionRow()
                }

                Section {
                    SettingsOptionPicker(
                        selection: Binding(
                            get: { timer.selectedMode },
                            set: { timer.selectMode($0) }
                        ),
                        options: TimerModeSlot.allCases.map { ($0, $0.symbol) }
                    )
                    .settingsOptionRow()
                    .disabled(isRoundDurationLocked)
                } header: {
                    Text(localizer.text("settings.mode"))
                }

                Section(localizer.text("setting.rounds")) {
                    RoundCountBar(
                        values: timer.roundCountValues,
                        selection: timer.roundCountValue,
                        title: localizer.text("setting.rounds"),
                        valueText: roundCountSettingText(for:),
                        onChange: timer.setRoundCountValue
                    )
                    .settingsOptionRow()
                    .disabled(isRoundDurationLocked)
                }

                Section(localizer.text("settings.round.duration")) {
                    SettingsOptionPicker(
                        selection: $timer.roundDurationMode,
                        options: [
                            (.twoMinutes, localizer.text("settings.round.duration.2min")),
                            (.threeMinutes, localizer.text("settings.round.duration.3min")),
                            (.custom, localizer.text("settings.round.duration.custom"))
                        ]
                    )
                    .settingsOptionRow()
                    .disabled(isRoundDurationLocked)

                    if timer.roundDurationMode == .custom {
                        Stepper(
                            localizer.format("minutes.format", timer.customRoundMinutes),
                            value: Binding(
                                get: { timer.customRoundMinutes },
                                set: { timer.setCustomRoundMinutes($0) }
                            ),
                            in: timer.customRoundMinuteRange
                        )
                        .settingsCardRow()
                        .disabled(isRoundDurationLocked)
                    }
                }

                Section(localizer.text("settings.rest.duration")) {
                    SettingsOptionPicker(
                        selection: $timer.restDurationMode,
                        options: [
                            (.thirtySeconds, localizer.format("seconds.format", 30)),
                            (.sixtySeconds, localizer.format("seconds.format", 60)),
                            (.custom, localizer.text("settings.rest.duration.custom"))
                        ]
                    )
                    .settingsOptionRow()
                    .disabled(isRoundDurationLocked)

                    if timer.restDurationMode == .custom {
                        Stepper(
                            localizer.duration(timer.customRestSeconds),
                            value: Binding(
                                get: { timer.customRestSeconds },
                                set: { timer.setCustomRestSeconds($0) }
                            ),
                            in: timer.customRestSecondRange,
                            step: timer.customRestSecondStep
                        )
                        .settingsCardRow()
                        .disabled(isRoundDurationLocked)
                    }
                }

                Section(localizer.text("settings.preparation.countdown")) {
                    SettingsOptionPicker(
                        selection: $timer.preparationSeconds,
                        options: timer.preparationOptions.map { ($0, localizer.format("seconds.format", $0)) }
                    )
                    .settingsOptionRow()
                    .disabled(isRoundDurationLocked)
                }

                Section(localizer.text("settings.app.info")) {
                    HStack {
                        Text(localizer.text("settings.version"))
                        Spacer()
                        Text(appVersionText)
                            .foregroundStyle(.secondary)
                    }

                    Button(localizer.text("settings.terms")) {
                        openURL(BoxbellLink.terms)
                    }

                    Button(localizer.text("settings.more.apps")) {
                        openURL(BoxbellLink.moreApps)
                    }
                }
            }
            .navigationTitle(localizer.text("settings.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizer.text("button.done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0"
    }

    private func roundCountSettingText(for value: Int) -> String {
        if value >= timer.unlimitedRoundCountValue {
            return localizer.text("round.unlimited")
        }

        return localizer.format("round.option", value)
    }

    private var isRoundDurationLocked: Bool {
        !timer.canEditTimerSettings
    }
}

private enum BoxbellLink {
    static let terms = URL(string: "https://gotgam100.github.io/BoxBell/")!
    static let moreApps = URL(string: "itms-apps://itunes.apple.com/search?term=Seunghwa%20Baek&media=software")!
}

// 기본 segmented Picker는 트랙 안에 선택 캡슐이 겹쳐 보이므로, 트랙 없이 버튼을 나란히 배치한다.
struct SettingsOptionPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection

                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            isSelected ? Color(red: 0.9, green: 0.02, blue: 0.015) : Color(.secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// 붉은 막대를 좌우로 드래그해 라운드 수를 고른다. 막대 위에 현재 라운드 수를 겹쳐 표시한다.
struct RoundCountBar: View {
    let values: [Int]
    let selection: Int
    let title: String
    let valueText: (Int) -> String
    let onChange: (Int) -> Void

    @Environment(\.isEnabled) private var isEnabled

    private let barHeight: CGFloat = 48
    private let barShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    private let fillColor = Color(red: 0.9, green: 0.02, blue: 0.015)

    private var selectedIndex: Int {
        values.firstIndex(of: selection) ?? 0
    }

    private var fillFraction: CGFloat {
        CGFloat(selectedIndex + 1) / CGFloat(max(values.count, 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let label = Text(valueText(selection))
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack(alignment: .leading) {
                barShape
                    .fill(Color(.secondarySystemGroupedBackground))

                fillColor
                    .frame(width: proxy.size.width * fillFraction)

                label
                    .foregroundStyle(.primary)

                // 붉은 막대 위에 걸친 부분의 글자는 흰색으로 보이게 한다.
                label
                    .foregroundStyle(.white)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: proxy.size.width * fillFraction)
                    }
            }
            .clipShape(barShape)
            .animation(.snappy(duration: 0.15), value: selection)
            .contentShape(barShape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled, proxy.size.width > 0 else { return }
                        let fraction = min(max(gesture.location.x / proxy.size.width, 0), 1)
                        let index = min(Int(fraction * CGFloat(values.count)), values.count - 1)
                        if values[index] != selection {
                            onChange(values[index])
                        }
                    }
            )
        }
        .frame(height: barHeight)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText(selection))
        .accessibilityAdjustableAction { direction in
            let offset = direction == .increment ? 1 : -1
            let index = min(max(selectedIndex + offset, 0), values.count - 1)
            onChange(values[index])
        }
    }
}

private extension View {
    func settingsOptionRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }

    // 기본 행 배경 대신 모서리가 둥근 네모 카드 배경을 사용한다.
    func settingsCardRow() -> some View {
        padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.top, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}

// 원형 버튼을 위아래로 밀어서 휠 피커처럼 값을 바꾼다. 위로 밀면 다음 값, 아래로 밀면 이전 값.
struct WheelDialButton: View {
    let values: [Int]
    let selection: Int
    let title: String
    let caption: String
    let size: CGFloat
    let valueText: (Int) -> String
    let onChange: (Int) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var dragStartIndex: Int?

    private let stepHeight: CGFloat = 14

    private var selectedIndex: Int {
        values.firstIndex(of: selection) ?? values.firstIndex { $0 >= selection } ?? 0
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(.white.opacity(dragStartIndex == nil ? 0.1 : 0.16))

                Circle()
                    .stroke(
                        dragStartIndex == nil ? Color.white.opacity(0.18) : Color(red: 0.9, green: 0.02, blue: 0.015),
                        lineWidth: 2
                    )

                VStack(spacing: 1) {
                    neighborText(at: selectedIndex + 1)

                    Text(valueText(selection))
                        .font(.system(size: size * 0.29, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())

                    neighborText(at: selectedIndex - 1)
                }
                .padding(.horizontal, 6)
                .animation(.snappy(duration: 0.18), value: selection)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .contentShape(Circle())
            .gesture(dragGesture)

            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 14)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText(selection))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                select(index: selectedIndex + 1)
            case .decrement:
                select(index: selectedIndex - 1)
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func neighborText(at index: Int) -> some View {
        Text(values.indices.contains(index) ? valueText(values[index]) : " ")
            .font(.system(size: size * 0.15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.3))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                guard isEnabled else { return }

                let startIndex = dragStartIndex ?? selectedIndex
                dragStartIndex = startIndex
                let steps = Int((-gesture.translation.height / stepHeight).rounded())
                select(index: startIndex + steps)
            }
            .onEnded { _ in
                dragStartIndex = nil
            }
    }

    private func select(index: Int) {
        let clampedIndex = min(max(index, 0), values.count - 1)
        guard values[clampedIndex] != selection else { return }
        onChange(values[clampedIndex])
    }
}

#Preview {
    ContentView()
}
