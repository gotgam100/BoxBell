import AlarmKit
import Foundation
import SwiftUI

struct BoxbellAlarmMetadata: AlarmMetadata {
    let sessionID: String
    let eventKind: String
    let round: Int
}

struct BoxbellScheduledAlarm: Codable, Hashable {
    enum Kind: String, Codable {
        case warning
        case roundEnd
        case restEnd
        case finished

        var soundName: String {
            switch self {
            case .warning:
                return "bell_30_seconds.wav"
            case .roundEnd, .restEnd, .finished:
                return "bell_start_end.wav"
            }
        }
    }

    let kind: Kind
    let round: Int
    let fireDate: Date
}

@MainActor
final class BoxbellAlarmScheduler {
    private let storedAlarmIDsKey = "boxbell.scheduledAlarmIDs"
    private let maxInfiniteRoundsToSchedule = 12
    private var schedulingTask: Task<Void, Never>?

    func scheduleSession(
        sessionID: String,
        languageCode: String,
        phase: TimerPhase,
        currentRound: Int,
        totalRounds: Int,
        isInfiniteRounds: Bool,
        roundSeconds: Int,
        restSeconds: Int,
        remainingSeconds: Int
    ) {
        let events = makeSchedule(
            phase: phase,
            currentRound: currentRound,
            totalRounds: totalRounds,
            isInfiniteRounds: isInfiniteRounds,
            roundSeconds: roundSeconds,
            restSeconds: restSeconds,
            remainingSeconds: remainingSeconds
        )

        schedulingTask?.cancel()
        schedulingTask = Task {
            await schedule(events, sessionID: sessionID, languageCode: languageCode)
        }
    }

    func cancelScheduledAlarms() {
        schedulingTask?.cancel()
        schedulingTask = nil
        Task {
            await cancelStoredAlarms()
        }
    }

    private func makeSchedule(
        phase: TimerPhase,
        currentRound: Int,
        totalRounds: Int,
        isInfiniteRounds: Bool,
        roundSeconds: Int,
        restSeconds: Int,
        remainingSeconds: Int
    ) -> [BoxbellScheduledAlarm] {
        guard phase == .round || phase == .rest else { return [] }

        let now = Date()
        let maximumRound = isInfiniteRounds ? currentRound + maxInfiniteRoundsToSchedule - 1 : totalRounds
        var events: [BoxbellScheduledAlarm] = []
        var activePhase = phase
        var activeRound = currentRound
        var segmentOffset = 0
        var segmentRemaining = max(1, remainingSeconds)

        while activeRound <= maximumRound && events.count < 50 {
            switch activePhase {
            case .round:
                if segmentRemaining > 30 {
                    events.append(
                        BoxbellScheduledAlarm(
                            kind: .warning,
                            round: activeRound,
                            fireDate: now.addingTimeInterval(TimeInterval(segmentOffset + segmentRemaining - 30))
                        )
                    )
                }

                let endOffset = segmentOffset + segmentRemaining
                let isLastRound = !isInfiniteRounds && activeRound >= totalRounds
                events.append(
                    BoxbellScheduledAlarm(
                        kind: isLastRound ? .finished : .roundEnd,
                        round: activeRound,
                        fireDate: now.addingTimeInterval(TimeInterval(endOffset))
                    )
                )

                if isLastRound {
                    return events
                }

                activePhase = .rest
                segmentOffset = endOffset
                segmentRemaining = restSeconds
            case .rest:
                let endOffset = segmentOffset + segmentRemaining
                events.append(
                    BoxbellScheduledAlarm(
                        kind: .restEnd,
                        round: activeRound + 1,
                        fireDate: now.addingTimeInterval(TimeInterval(endOffset))
                    )
                )

                activeRound += 1
                activePhase = .round
                segmentOffset = endOffset
                segmentRemaining = roundSeconds
            case .ready, .finished:
                return events
            }
        }

        return events
    }

    private func schedule(
        _ events: [BoxbellScheduledAlarm],
        sessionID: String,
        languageCode: String
    ) async {
        await cancelStoredAlarms()
        guard !events.isEmpty, !Task.isCancelled else { return }

        do {
            let authorization = try await AlarmManager.shared.requestAuthorization()
            guard authorization == .authorized, !Task.isCancelled else { return }
        } catch {
            return
        }

        var scheduledIDs: [UUID] = []
        for event in events {
            guard !Task.isCancelled else { break }

            let id = UUID()
            do {
                let configuration = alarmConfiguration(for: event, sessionID: sessionID, languageCode: languageCode)
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                scheduledIDs.append(id)
                storeAlarmIDs(scheduledIDs)
            } catch {
                continue
            }
        }
    }

    private func alarmConfiguration(
        for event: BoxbellScheduledAlarm,
        sessionID: String,
        languageCode: String
    ) -> AlarmManager.AlarmConfiguration<BoxbellAlarmMetadata> {
        let title = localizedTitle(for: event, languageCode: languageCode)
        let stopText = languageCode == "en" ? "Stop" : "끄기"
        let stopButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: stopText),
            textColor: .white,
            systemImageName: "stop.circle.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: BoxbellAlarmMetadata(
                sessionID: sessionID,
                eventKind: event.kind.rawValue,
                round: event.round
            ),
            tintColor: Color.red
        )

        return AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(event.fireDate),
            attributes: attributes,
            sound: .named(event.kind.soundName)
        )
    }

    private func localizedTitle(for event: BoxbellScheduledAlarm, languageCode: String) -> String {
        if languageCode == "en" {
            switch event.kind {
            case .warning:
                return "Round \(event.round): 30 seconds left"
            case .roundEnd:
                return "Round \(event.round) ended"
            case .restEnd:
                return "Round \(event.round) starts"
            case .finished:
                return "Workout complete"
            }
        }

        switch event.kind {
        case .warning:
            return "\(event.round)라운드 30초 남음"
        case .roundEnd:
            return "\(event.round)라운드 종료"
        case .restEnd:
            return "\(event.round)라운드 시작"
        case .finished:
            return "운동 종료"
        }
    }

    private func cancelStoredAlarms() async {
        let manager = AlarmManager.shared
        let ids = storedAlarmIDs()

        for id in ids {
            try? manager.cancel(id: id)
            try? manager.stop(id: id)
        }

        storeAlarmIDs([])
    }

    private func storedAlarmIDs() -> [UUID] {
        let strings = UserDefaults.standard.stringArray(forKey: storedAlarmIDsKey) ?? []
        return strings.compactMap(UUID.init(uuidString:))
    }

    private func storeAlarmIDs(_ ids: [UUID]) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: storedAlarmIDsKey)
    }
}
