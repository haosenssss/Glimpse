import Foundation
import Testing
@testable import GlimpseCore

@Suite struct AppPhaseTests {
    let now = Date(timeIntervalSince1970: 1_000)

    @Test func idleStartsSelection() {
        #expect(AppPhase.idle.applying(.startSelection) == .selecting)
    }

    @Test func completedSelectionStartsRequest() {
        #expect(AppPhase.selecting.applying(.selectionCompleted(at: now)) == .requesting(startedAt: now))
    }

    @Test func cancellingSelectionReturnsToIdle() {
        #expect(AppPhase.selecting.applying(.cancel) == .idle)
    }

    @Test func answerMakesRequestReady() {
        #expect(AppPhase.requesting(startedAt: now).applying(.answerReceived("B")) == .ready(answer: "B"))
    }

    @Test func failureMakesRequestFailed() {
        #expect(AppPhase.requesting(startedAt: now).applying(.requestFailed("401")) == .failed(message: "401"))
    }

    @Test func requestInFlightIgnoresNewSelection() {
        #expect(AppPhase.requesting(startedAt: now).applying(.startSelection) == nil)
    }

    @Test func cancellingRequestReturnsToIdle() {
        #expect(AppPhase.requesting(startedAt: now).applying(.cancel) == .idle)
    }

    @Test func pastingReadyAnswerReturnsToIdle() {
        #expect(AppPhase.ready(answer: "B").applying(.paste) == .idle)
    }

    @Test func readyAnswerCanBeReplacedByNewSelection() {
        #expect(AppPhase.ready(answer: "B").applying(.startSelection) == .selecting)
    }

    @Test func failedCanBeDismissedOrRetried() {
        #expect(AppPhase.failed(message: "x").applying(.dismissError) == .idle)
        #expect(AppPhase.failed(message: "x").applying(.startSelection) == .selecting)
    }

    @Test(arguments: [
        (AppPhase.idle, AppEvent.paste),
        (AppPhase.idle, AppEvent.answerReceived("B")),
        (AppPhase.idle, AppEvent.cancel),
        (AppPhase.selecting, AppEvent.paste),
        (AppPhase.ready(answer: "B"), AppEvent.answerReceived("C")),
        (AppPhase.failed(message: "x"), AppEvent.paste),
    ])
    func invalidTransitionsAreRejected(phase: AppPhase, event: AppEvent) {
        #expect(phase.applying(event) == nil)
    }

    @Test func readyAnswerExpiresToIdle() {
        #expect(AppPhase.ready(answer: "B").applying(.expire) == .idle)
        #expect(AppPhase.requesting(startedAt: now).applying(.expire) == nil)
        #expect(AppPhase.idle.applying(.expire) == nil)
    }

    @Test func escapeHotkeyOnlyWhileActive() {
        #expect(AppPhase.idle.needsEscapeHotkey == false)
        #expect(AppPhase.selecting.needsEscapeHotkey)
        #expect(AppPhase.requesting(startedAt: now).needsEscapeHotkey)
        #expect(AppPhase.ready(answer: "B").needsEscapeHotkey)
        #expect(AppPhase.failed(message: "x").needsEscapeHotkey == false)
    }

    @Test func confirmHotkeyOnlyWhenReady() {
        #expect(AppPhase.ready(answer: "B").needsConfirmHotkey)
        #expect(AppPhase.requesting(startedAt: now).needsConfirmHotkey == false)
        #expect(AppPhase.idle.needsConfirmHotkey == false)
    }

    @Test func indicatorStyleFollowsPhase() {
        #expect(AppPhase.idle.indicatorStyle == .hidden)
        #expect(AppPhase.selecting.indicatorStyle == .hidden)
        #expect(AppPhase.requesting(startedAt: now).indicatorStyle == .working)
        #expect(AppPhase.ready(answer: "B").indicatorStyle == .ready)
        #expect(AppPhase.failed(message: "x").indicatorStyle == .error)
    }
}
