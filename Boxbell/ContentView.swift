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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                timer.cancelBackgroundAlarmsAndRefresh()
            } else if timer.isRunning {
                timer.scheduleBackgroundAlarms(languageCode: appLanguage)
            }
        }
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
        ZStack {
            Circle()
                .inset(by: 6)
                .fill(.black.opacity(0.2))

            Image("TimeBell")
                .resizable()
                .scaledToFit()
                .frame(width: 238, height: 238)
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
        .frame(width: 260, height: 260)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private var digitalTimer: some View {
        Text(timer.timeText)
            .font(.custom("DS-Digital-Bold", size: 180))
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
        VStack(spacing: 18) {
            HStack {
                Text(localizer.text("setting.rounds"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer()

                Button {
                    timer.decrementRoundSetting()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(StepperIconButtonStyle())
                .disabled(!timer.canEditTimerSettings)

                Text(timer.roundSettingText)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 48)

                Button {
                    timer.incrementRoundSetting()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(StepperIconButtonStyle())
                .disabled(!timer.canEditTimerSettings || timer.isInfiniteRounds)
            }
            .opacity(timer.canEditTimerSettings ? 1 : 0.48)

            VStack(alignment: .leading, spacing: 10) {
                Text(localizer.text("setting.rest.time"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 10) {
                    ForEach(timer.restOptions, id: \.self) { seconds in
                        restOptionButton(seconds)
                    }
                }
            }
            .opacity(timer.canEditTimerSettings ? 1 : 0.48)
        }
        .padding(18)
        .padding(.top, 10)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var guideText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localizer.text("guide.start"))
            Text(localizer.text("guide.settings.locked"))
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, -6)
    }

    private func restOptionButton(_ seconds: Int) -> some View {
        let isSelected = timer.restSeconds == seconds

        return Button {
            guard timer.canEditTimerSettings else { return }
            timer.restSeconds = seconds
        } label: {
            Text(localizer.format("seconds.format", seconds))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .foregroundStyle(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(isSelected ? .white : .white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!timer.canEditTimerSettings)
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
        case .round, .rest:
            return timer.currentRound
        }
    }

    private var timerStatusText: String {
        if timer.phase == .round {
            return localizer.format("round.current", timer.currentRound)
        }

        return localizer.text(timer.phase.titleKey)
    }

    private var timerRingColor: Color {
        if timer.phase == .rest {
            return .green
        }

        return isWarningFlashActive ? .white : Color(red: 0.9, green: 0.02, blue: 0.015)
    }

    private var digitalTimerColor: Color {
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
                    Picker(localizer.text("settings.language"), selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(localizer.text(language.titleKey)).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(localizer.text("settings.round.duration")) {
                    Picker(localizer.text("settings.round.duration"), selection: $timer.roundDurationMode) {
                        Text(localizer.text("settings.round.duration.2min")).tag(RoundDurationMode.twoMinutes)
                        Text(localizer.text("settings.round.duration.3min")).tag(RoundDurationMode.threeMinutes)
                        Text(localizer.text("settings.round.duration.custom")).tag(RoundDurationMode.custom)
                    }
                    .pickerStyle(.segmented)
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
                        .disabled(isRoundDurationLocked)
                    }
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var isRoundDurationLocked: Bool {
        !timer.canEditTimerSettings
    }
}

private enum BoxbellLink {
    static let terms = URL(string: "https://gotgam100.github.io/BoxBell/")!
    static let moreApps = URL(string: "itms-apps://itunes.apple.com/search?term=Seunghwa%20Baek&media=software")!
}

struct StepperIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.1))
            .clipShape(Circle())
    }
}

#Preview {
    ContentView()
}
