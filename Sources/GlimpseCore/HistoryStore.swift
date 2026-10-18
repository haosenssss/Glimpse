import Foundation

public struct HistoryEntry: Identifiable, Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case success(answer: String)
        case failure(message: String)
    }

    static let previewLength = 40

    public let id: UUID
    public let date: Date
    public let model: String
    public let duration: TimeInterval
    public let outcome: Outcome

    public init(id: UUID = UUID(), date: Date, model: String, duration: TimeInterval, outcome: Outcome) {
        self.id = id
        self.date = date
        self.model = model
        self.duration = duration
        self.outcome = outcome
    }

    public var answer: String? {
        if case .success(let answer) = outcome { return answer }
        return nil
    }

    /// e.g. "✓ 14:32  gpt-4o  3.1s  B" or "✕ 14:28  gpt-4o  401 Invalid API key".
    public func summary(timeFormatter: DateFormatter) -> String {
        let time = timeFormatter.string(from: date)
        switch outcome {
        case .success(let answer):
            let seconds = String(format: "%.1fs", duration)
            return "✓ \(time)  \(model)  \(seconds)  \(Self.preview(answer))"
        case .failure(let message):
            return "✕ \(time)  \(model)  \(Self.preview(message))"
        }
    }

    private static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > previewLength ? String(flat.prefix(previewLength)) + "…" : flat
    }
}

/// In-memory request log, newest first. Never written to disk.
public struct HistoryLog: Equatable, Sendable {
    public static let defaultLimit = 20

    public let entries: [HistoryEntry]
    public let limit: Int

    public init(limit: Int = HistoryLog.defaultLimit) {
        self.init(entries: [], limit: limit)
    }

    private init(entries: [HistoryEntry], limit: Int) {
        self.entries = entries
        self.limit = limit
    }

    public func appending(_ entry: HistoryEntry) -> HistoryLog {
        HistoryLog(entries: Array(([entry] + entries).prefix(limit)), limit: limit)
    }

    public func cleared() -> HistoryLog {
        HistoryLog(limit: limit)
    }
}
