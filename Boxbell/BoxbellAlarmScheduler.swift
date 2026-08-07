import Foundation
import UserNotifications

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
    private let notificationIdentifierPrefix = "boxbell.round.signal."
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
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted, !Task.isCancelled else { return }
        } catch {
            return
        }

        var scheduledIDs: [String] = []
        for event in events {
            guard !Task.isCancelled else { break }

            let id = "\(notificationIdentifierPrefix)\(sessionID).\(UUID().uuidString)"
            do {
                let request = notificationRequest(
                    identifier: id,
                    for: event,
                    languageCode: languageCode
                )
                try await UNUserNotificationCenter.current().add(request)
                scheduledIDs.append(id)
                storeAlarmIDs(scheduledIDs)
            } catch {
                continue
            }
        }
    }

    private func notificationRequest(
        identifier: String,
        for event: BoxbellScheduledAlarm,
        languageCode: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = localizedTitle(for: event, languageCode: languageCode)
        content.sound = UNNotificationSound(named: UNNotificationSoundName(event.kind.soundName))
        content.interruptionLevel = .timeSensitive

        let interval = max(1, event.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
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
        let ids = storedAlarmIDs()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)

        storeAlarmIDs([])
    }

    private func storedAlarmIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: storedAlarmIDsKey) ?? []
    }

    private func storeAlarmIDs(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: storedAlarmIDsKey)
    }
}
