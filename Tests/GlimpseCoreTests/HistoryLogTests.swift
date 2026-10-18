import Foundation
import Testing
@testable import GlimpseCore

@Suite struct HistoryLogTests {
    let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func entry(_ outcome: HistoryEntry.Outcome, model: String = "gpt-4o", duration: TimeInterval = 3.14) -> HistoryEntry {
        HistoryEntry(date: Date(timeIntervalSince1970: 52_320), model: model, duration: duration, outcome: outcome)
    }

    @Test func appendsNewestFirstWithoutMutatingOriginal() {
        let empty = HistoryLog()
        let first = empty.appending(entry(.success(answer: "A")))
        let second = first.appending(entry(.success(answer: "B")))

        #expect(empty.entries.isEmpty)
        #expect(first.entries.count == 1)
        #expect(second.entries.map(\.answer) == ["B", "A"])
    }

    @Test func dropsOldestBeyondLimit() {
        let log = (0..<25).reduce(HistoryLog(limit: 20)) { log, index in
            log.appending(entry(.success(answer: "\(index)")))
        }
        #expect(log.entries.count == 20)
        #expect(log.entries.first?.answer == "24")
        #expect(log.entries.last?.answer == "5")
    }

    @Test func clearedLogIsEmpty() {
        let log = HistoryLog().appending(entry(.success(answer: "A")))
        #expect(log.cleared().entries.isEmpty)
        #expect(log.cleared().limit == log.limit)
    }

    @Test func successSummaryShowsPreview() {
        let summary = entry(.success(answer: "B")).summary(timeFormatter: formatter)
        #expect(summary == "✓ 14:32  gpt-4o  3.1s  B")
    }

    @Test func failureSummaryShowsMessage() {
        let summary = entry(.failure(message: "401 Invalid API key")).summary(timeFormatter: formatter)
        #expect(summary == "✕ 14:32  gpt-4o  401 Invalid API key")
    }

    @Test func longMultilineAnswersAreFlattenedAndTruncated() {
        let answer = "1. A\n2. C\n" + String(repeating: "x", count: 100)
        let summary = entry(.success(answer: answer)).summary(timeFormatter: formatter)
        #expect(!summary.contains("\n"))
        #expect(summary.hasSuffix("…"))
        #expect(summary.contains("1. A 2. C"))
    }

    @Test func failuresHaveNoAnswer() {
        #expect(entry(.failure(message: "x")).answer == nil)
    }
}
