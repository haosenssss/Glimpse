import Foundation

/// Cleans a model answer before it is pasted into an arbitrary text field.
public enum AnswerPostProcessor {
    public static func process(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripWrappingFence(normalized)
    }

    /// "```lang\n…\n```" around the whole answer becomes just the inner text.
    private static func stripWrappingFence(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.count >= 2,
              lines[0].hasPrefix("```"),
              lines[lines.count - 1] == "```",
              lines.filter({ $0.hasPrefix("```") }).count == 2
        else { return text }

        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
