import Foundation

/// Runs an async operation with an upper time bound; the slower branch is cancelled.
public enum Deadline {
    public static func run<T: Sendable>(
        _ limit: Duration,
        onTimeout error: Error & Sendable,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw error
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw error }
            return value
        }
    }
}
