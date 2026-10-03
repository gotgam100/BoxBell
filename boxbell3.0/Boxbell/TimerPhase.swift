import Foundation

enum TimerPhase: String, Codable, Hashable {
    case ready
    case preparation
    case round
    case rest
    case finished

    var titleKey: String {
        switch self {
        case .ready:
            return "phase.ready"
        case .preparation:
            return "phase.preparation"
        case .round:
            return "phase.round"
        case .rest:
            return "phase.rest"
        case .finished:
            return "phase.finished"
        }
    }
}
