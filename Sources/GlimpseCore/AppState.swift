import Foundation

/// What the app is doing right now. Transitions are pure so the coordinator only
/// has to apply side effects for whatever phase it lands in.
public enum AppPhase: Equatable, Sendable {
    case idle
    case selecting
    case requesting(startedAt: Date)
    case ready(answer: String)
    case failed(message: String)
}

public enum AppEvent: Equatable, Sendable {
    case startSelection
    case selectionCompleted(at: Date)
    case answerReceived(String)
    case requestFailed(String)
    case paste
    case cancel
    case dismissError
    /// A ready answer nobody pasted; frees Return/Esc again.
    case expire
}

public enum IndicatorStyle: Equatable, Sendable {
    case hidden
    case working
    case ready
    case error
}

extension AppPhase {
    /// The next phase, or `nil` when the event makes no sense in this phase.
    public func applying(_ event: AppEvent) -> AppPhase? {
        switch (self, event) {
        case (.idle, .startSelection), (.ready, .startSelection), (.failed, .startSelection):
            return .selecting
        case (.selecting, .selectionCompleted(let date)):
            return .requesting(startedAt: date)
        case (.requesting, .answerReceived(let answer)):
            return .ready(answer: answer)
        case (.requesting, .requestFailed(let message)):
            return .failed(message: message)
        case (.ready, .paste), (.ready, .expire):
            return .idle
        case (.selecting, .cancel), (.requesting, .cancel), (.ready, .cancel), (.failed, .cancel):
            return .idle
        case (.failed, .dismissError):
            return .idle
        default:
            return nil
        }
    }

    public var needsEscapeHotkey: Bool {
        switch self {
        case .selecting, .requesting, .ready: return true
        case .idle, .failed: return false
        }
    }

    public var needsConfirmHotkey: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isBusy: Bool {
        switch self {
        case .selecting, .requesting, .ready: return true
        case .idle, .failed: return false
        }
    }

    public var indicatorStyle: IndicatorStyle {
        switch self {
        case .idle, .selecting: return .hidden
        case .requesting: return .working
        case .ready: return .ready
        case .failed: return .error
        }
    }
}
