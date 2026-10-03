import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .korean:
            return "language.korean"
        case .english:
            return "language.english"
        }
    }
}

struct Localizer {
    var languageCode: String

    func text(_ key: String) -> String {
        guard
            let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }

        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    func duration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes == 0 {
            return format("seconds.format", seconds)
        }

        if seconds == 0 {
            return format("minutes.format", minutes)
        }

        return format("minutes.seconds.format", minutes, seconds)
    }
}
