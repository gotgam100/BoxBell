import Foundation

enum RestDurationMode: String, CaseIterable, Identifiable, Codable {
    case thirtySeconds
    case sixtySeconds
    case custom

    var id: String { rawValue }
}

struct TimerModeSettings: Codable, Equatable {
    var totalRounds: Int
    var isInfiniteRounds: Bool
    var roundDurationMode: RoundDurationMode
    var customRoundMinutes: Int
    var restDurationMode: RestDurationMode
    var customRestSeconds: Int
    var preparationSeconds: Int
}

enum TimerModeSlot: String, CaseIterable, Identifiable, Codable {
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    var symbol: String { rawValue }

    var defaultSettings: TimerModeSettings {
        switch self {
        case .a:
            return TimerModeSettings(
                totalRounds: 3,
                isInfiniteRounds: false,
                roundDurationMode: .threeMinutes,
                customRoundMinutes: 3,
                restDurationMode: .thirtySeconds,
                customRestSeconds: 90,
                preparationSeconds: 5
            )
        case .b:
            return TimerModeSettings(
                totalRounds: 6,
                isInfiniteRounds: false,
                roundDurationMode: .custom,
                customRoundMinutes: 5,
                restDurationMode: .sixtySeconds,
                customRestSeconds: 90,
                preparationSeconds: 10
            )
        case .c:
            return TimerModeSettings(
                totalRounds: 12,
                isInfiniteRounds: false,
                roundDurationMode: .custom,
                customRoundMinutes: 10,
                restDurationMode: .custom,
                customRestSeconds: 120,
                preparationSeconds: 10
            )
        }
    }
}

struct TimerModeStore {
    private let settingsKey = "timerModeSettings.v1"
    private let selectedModeKey = "selectedTimerMode"
    private let defaults = UserDefaults.standard

    func loadSettings() -> [TimerModeSlot: TimerModeSettings] {
        var stored: [String: TimerModeSettings] = [:]
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: TimerModeSettings].self, from: data) {
            stored = decoded
        }

        var settings: [TimerModeSlot: TimerModeSettings] = [:]
        for mode in TimerModeSlot.allCases {
            settings[mode] = stored[mode.rawValue] ?? mode.defaultSettings
        }
        return settings
    }

    func saveSettings(_ settings: [TimerModeSlot: TimerModeSettings]) {
        let stored = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    func loadSelectedMode() -> TimerModeSlot {
        defaults.string(forKey: selectedModeKey).flatMap(TimerModeSlot.init(rawValue:)) ?? .a
    }

    func saveSelectedMode(_ mode: TimerModeSlot) {
        defaults.set(mode.rawValue, forKey: selectedModeKey)
    }
}
