import Testing
@testable import GlimpseCore

@Suite struct AnswerPostProcessorTests {
    @Test func trimsSurroundingWhitespace() {
        #expect(AnswerPostProcessor.process("\n  B \n") == "B")
    }

    @Test func normalizesLineEndings() {
        #expect(AnswerPostProcessor.process("1. A\r\n2. C") == "1. A\n2. C")
    }

    @Test func stripsWrappingCodeFence() {
        #expect(AnswerPostProcessor.process("```python\nprint(1)\nprint(2)\n```") == "print(1)\nprint(2)")
        #expect(AnswerPostProcessor.process("```\nx = 1\n```\n") == "x = 1")
    }

    @Test func keepsFencesThatDoNotWrapEverything() {
        let text = "Answer:\n```\nx = 1\n```"
        #expect(AnswerPostProcessor.process(text) == text)
    }

    @Test func keepsMultipleFencedBlocks() {
        let text = "```\na\n```\nand\n```\nb\n```"
        #expect(AnswerPostProcessor.process(text) == text)
    }
}
