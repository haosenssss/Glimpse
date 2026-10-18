import Foundation

/// Drains a chat stream into the final answer, enforcing a total time limit
/// (URLRequest's timeout only covers gaps between packets).
public enum AnswerCollector {
    public static func collect(
        events: AsyncThrowingStream<ChatEvent, Error>,
        timeout: Duration,
        onEvent: @escaping @Sendable (ChatEvent) -> Void = { _ in }
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var answer = ""
                for try await event in events {
                    onEvent(event)
                    if case .content(let text) = event { answer += text }
                }
                guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatError.emptyAnswer
                }
                return answer
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ChatError.timeout(seconds: Int(timeout.components.seconds))
            }
            defer { group.cancelAll() }
            guard let answer = try await group.next() else { throw ChatError.emptyAnswer }
            return answer
        }
    }
}
