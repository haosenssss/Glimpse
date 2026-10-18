import AppKit
import GlimpseCore
import os

/// Owns the app state machine and applies its side effects: overlay, request,
/// indicator, temporary hotkeys, history.
@MainActor
final class AppCoordinator {
    private static let errorDisplayDuration: Duration = .seconds(2)
    /// An unpasted answer stops holding Return/Esc after this long (it stays in History).
    private static let readyExpiry: Duration = .seconds(60)
    private nonisolated static let captureTimeout: Duration = .seconds(10)
    /// Region capture includes Glimpse's own windows, so give the closed overlay a moment to leave the screen.
    private nonisolated static let overlaySettleDelay: Duration = .milliseconds(80)
    /// Keeps swallowing Return briefly after a paste so key auto-repeat can't leak into the app.
    private static let returnRepeatGuard: Duration = .milliseconds(600)

    private(set) var phase: AppPhase = .idle {
        didSet { phaseDidChange() }
    }
    private(set) var history = HistoryLog()
    /// The JPEG most recently sent to the model, kept in memory only so it can be checked from the menu.
    private(set) var lastCaptureJPEG: Data?
    private(set) var settings: AppSettings

    private let settingsStore: SettingsStore
    private let keychain: KeychainStore
    private let client = ChatClient()
    private let indicator: StatusIndicator
    private let logger = Logger(subsystem: "com.haosen.glimpse", category: "coordinator")

    private var overlay: SelectionOverlay?
    /// True between mouse-up and the screenshot being taken; the indicator stays hidden so it can't end up in the image.
    private var isCapturing = false
    private var requestTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var returnGuardTask: Task<Void, Never>?
    /// > 0 while one of Glimpse's own dialogs is open; all Glimpse hotkeys are released meanwhile.
    private var modalDepth = 0
    /// Read once; Keychain lookups on every menu open could block on an ACL prompt.
    private var cachedAPIKey: String

    init(settingsStore: SettingsStore, keychain: KeychainStore) {
        self.settingsStore = settingsStore
        self.keychain = keychain
        settings = settingsStore.load()
        cachedAPIKey = keychain.read() ?? ""
        indicator = StatusIndicator(settings: settings.indicator)
        indicator.onPositionChanged = { [weak self] center in self?.saveIndicatorPosition(center) }
    }

    // MARK: - Global hotkeys

    /// Registers the capture and quit shortcuts; returns a message per shortcut that couldn't be registered.
    @discardableResult
    func registerGlobalHotkeys() -> [String] {
        guard modalDepth == 0 else { return [] }
        let manager = HotkeyManager.shared
        var failures: [String] = []
        if !manager.register(.capture, hotkey: settings.captureHotkey, handler: { [weak self] in self?.startCapture() }) {
            failures.append("Capture shortcut \(settings.captureHotkey.displayString) is taken by another app")
        }
        if !manager.register(.quit, hotkey: settings.quitHotkey, handler: { NSApp.terminate(nil) }) {
            failures.append("Quit shortcut \(settings.quitHotkey.displayString) is taken by another app")
        }
        return failures
    }

    /// Runs one of Glimpse's dialogs with every Glimpse hotkey released, so Return/Esc
    /// reach the dialog and the old shortcuts can't swallow one being recorded.
    /// Returns shortcut registration problems to report afterwards.
    func performModal(_ body: () -> Void) -> [String] {
        modalDepth += 1
        HotkeyManager.shared.unregister(.capture)
        HotkeyManager.shared.unregister(.quit)
        updateTemporaryHotkeys()
        body()
        modalDepth -= 1
        updateTemporaryHotkeys()
        return registerGlobalHotkeys()
    }

    // MARK: - Capture flow

    func startCapture() {
        guard modalDepth == 0, let next = phase.applying(.startSelection) else { return }
        flashTask?.cancel()
        phase = next
        let overlay = SelectionOverlay(
            onComplete: { [weak self] rect, screen in self?.selectionFinished(rect: rect, screen: screen) },
            onCancel: { [weak self] in self?.cancel() }
        )
        self.overlay = overlay
        overlay.show()
    }

    func cancel() {
        requestTask?.cancel()
        requestTask = nil
        overlay?.close()
        overlay = nil
        transition(.cancel)
    }

    func confirmPaste() {
        guard case .ready(let answer) = phase else { return }
        transition(.paste)
        swallowReturnRepeat()
        if TextInserter.insert(answer) == .copiedOnly {
            logger.notice("Paste unavailable; answer left on clipboard")
            flash(.error)
        }
    }

    private func selectionFinished(rect: CGRect, screen: NSScreen) {
        overlay = nil
        // A queued mouse-up can arrive after Esc already cancelled the selection.
        guard case .selecting = phase else { return }
        let startedAt = Date()
        isCapturing = true
        transition(.selectionCompleted(at: startedAt))

        let snapshot = settings
        let apiKey = cachedAPIKey
        let target = CaptureTarget(rect: rect, screen: screen)
        requestTask = Task { [weak self, client] in
            let result = await Self.fetchAnswer(target: target, settings: snapshot, apiKey: apiKey, client: client) { jpeg in
                Task { @MainActor in self?.captureFinished(jpeg) }
            }
            guard !Task.isCancelled else { return }
            self?.finishRequest(result, startedAt: startedAt, model: snapshot.model)
        }
    }

    private nonisolated static func fetchAnswer(
        target: CaptureTarget?, settings: AppSettings, apiKey: String, client: ChatClient,
        onEncoded: @escaping @Sendable (Data?) -> Void
    ) async -> Result<String, ChatError> {
        do {
            let config = try ChatConfig.make(
                baseURL: settings.baseURL, apiKey: apiKey, model: settings.model,
                systemPrompt: settings.systemPrompt, timeout: settings.timeoutSeconds
            )
            guard let target else { throw ChatError.capture("Display not found") }
            try await Task.sleep(for: overlaySettleDelay)
            let image = try await Deadline.run(captureTimeout, onTimeout: ChatError.capture("Screen capture timed out")) {
                try await ScreenCapturer.capture(target)
            }
            // Capture ignores cancellation; don't upload anything the user already cancelled.
            try Task.checkCancellation()
            let base64 = try ImageEncoder.encodeJPEGBase64(image)
            onEncoded(Data(base64Encoded: base64))
            let request = ChatRequestBuilder.makeRequest(config: config, imageBase64: base64)
            try Task.checkCancellation()
            let raw = try await AnswerCollector.collect(
                events: client.streamAnswer(request: request),
                timeout: .seconds(settings.timeoutSeconds)
            )
            return .success(AnswerPostProcessor.process(raw))
        } catch {
            return .failure(ChatError.wrap(error))
        }
    }

    private func captureFinished(_ jpeg: Data?) {
        lastCaptureJPEG = jpeg
        isCapturing = false
        indicator.show(phase.indicatorStyle)
    }

    private func finishRequest(_ result: Result<String, ChatError>, startedAt: Date, model: String) {
        requestTask = nil
        let duration = Date().timeIntervalSince(startedAt)
        switch result {
        case .success(let answer):
            record(.success(answer: answer), startedAt: startedAt, model: model, duration: duration)
            transition(.answerReceived(answer))
        case .failure(let error):
            // Server messages can echo request details, so keep them out of persisted logs.
            logger.error("Request failed: \(error.shortDescription, privacy: .private)")
            record(.failure(message: error.shortDescription), startedAt: startedAt, model: model, duration: duration)
            transition(.requestFailed(error.shortDescription))
        }
    }

    private func record(_ outcome: HistoryEntry.Outcome, startedAt: Date, model: String, duration: TimeInterval) {
        history = history.appending(HistoryEntry(date: startedAt, model: model.isEmpty ? "—" : model, duration: duration, outcome: outcome))
    }

    // MARK: - State side effects

    private func transition(_ event: AppEvent) {
        guard let next = phase.applying(event) else { return }
        phase = next
    }

    private func phaseDidChange() {
        updateTemporaryHotkeys()
        if !phase.isBusy { isCapturing = false }
        indicator.show(isCapturing ? .hidden : phase.indicatorStyle)
        expiryTask?.cancel()
        if case .ready = phase {
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: Self.readyExpiry)
                guard !Task.isCancelled else { return }
                self?.transition(.expire)
            }
        }
        if case .failed = phase {
            flashTask = Task { [weak self] in
                try? await Task.sleep(for: Self.errorDisplayDuration)
                guard !Task.isCancelled else { return }
                self?.transition(.dismissError)
            }
        }
    }

    /// Esc and Return are only grabbed while they mean something to Glimpse.
    private func updateTemporaryHotkeys() {
        let manager = HotkeyManager.shared
        guard modalDepth == 0 else {
            [.escape, .confirm, .confirmKeypad].forEach(manager.unregister)
            return
        }
        returnGuardTask?.cancel()
        if phase.needsEscapeHotkey {
            if !manager.isRegistered(.escape) {
                manager.register(.escape, keyCode: KeyCode.escape, modifiers: 0) { [weak self] in self?.cancel() }
            }
        } else {
            manager.unregister(.escape)
        }

        if phase.needsConfirmHotkey {
            manager.register(.confirm, keyCode: KeyCode.returnKey, modifiers: 0) { [weak self] in self?.confirmPaste() }
            manager.register(.confirmKeypad, keyCode: KeyCode.keypadEnter, modifiers: 0) { [weak self] in self?.confirmPaste() }
        } else {
            manager.unregister(.confirm)
            manager.unregister(.confirmKeypad)
        }
    }

    private func swallowReturnRepeat() {
        let manager = HotkeyManager.shared
        manager.register(.confirm, keyCode: KeyCode.returnKey, modifiers: 0) {}
        manager.register(.confirmKeypad, keyCode: KeyCode.keypadEnter, modifiers: 0) {}
        returnGuardTask = Task { [weak self] in
            try? await Task.sleep(for: Self.returnRepeatGuard)
            guard !Task.isCancelled, let self, !self.phase.needsConfirmHotkey else { return }
            manager.unregister(.confirm)
            manager.unregister(.confirmKeypad)
        }
    }

    /// Briefly shows a style while idle (e.g. × when a paste fell back to the clipboard).
    private func flash(_ style: IndicatorStyle) {
        flashTask?.cancel()
        indicator.show(style)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: Self.errorDisplayDuration)
            guard !Task.isCancelled, let self, self.phase == .idle else { return }
            self.indicator.show(.hidden)
        }
    }

    // MARK: - Settings

    private(set) var availableModels: [String] = []
    private(set) var modelListError: String?
    private(set) var isFetchingModels = false
    private var modelRefreshGeneration = 0

    var apiKey: String { cachedAPIKey }
    var needsSetup: Bool { settings.model.isEmpty || apiKey.isEmpty }
    var isEditingIndicator: Bool { indicator.isEditing }

    /// Applies and saves a settings change right away. Returns problems to show the user.
    @discardableResult
    func update(_ change: (AppSettings) -> AppSettings) -> [String] {
        let next = change(settings)
        if next.validationErrors.contains(.hotkeyConflict) {
            return ["Capture and Quit shortcuts must be different."]
        }
        settingsStore.save(next)
        settings = next
        indicator.apply(next.indicator)
        return registerGlobalHotkeys()
    }

    func setAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try keychain.save(trimmed)
        cachedAPIKey = trimmed
    }

    /// Fetches `/models` for the current base URL and key; the result is shown next time the menu opens.
    /// If the server only answers with `/v1` appended, the saved base URL is corrected.
    func refreshModels() {
        modelRefreshGeneration += 1
        let generation = modelRefreshGeneration
        isFetchingModels = true
        modelListError = nil
        let baseURL = settings.baseURL
        let key = apiKey
        Task { [weak self, client] in
            let result: Result<(baseURL: URL, models: [ModelInfo]), ChatError>
            do {
                let url = try BaseURLValidator.validate(baseURL)
                result = .success(try await client.discoverModels(baseURL: url, apiKey: key))
            } catch {
                result = .failure(ChatError.wrap(error))
            }
            // A newer refresh (e.g. after another base URL edit) supersedes this one.
            guard let self, generation == self.modelRefreshGeneration else { return }
            self.finishModelRefresh(result, requestedBaseURL: baseURL)
        }
    }

    private func finishModelRefresh(_ result: Result<(baseURL: URL, models: [ModelInfo]), ChatError>, requestedBaseURL: String) {
        isFetchingModels = false
        switch result {
        case .success(let found):
            if found.baseURL.absoluteString != requestedBaseURL, settings.baseURL == requestedBaseURL {
                update { $0.with(\.baseURL, found.baseURL.absoluteString) }
            }
            availableModels = ModelCatalog.selectable(found.models).map(\.id)
            modelListError = availableModels.isEmpty ? "No image-capable models found" : nil
        case .failure(let error):
            availableModels = []
            modelListError = error.shortDescription
        }
    }

    func beginIndicatorEditing() {
        indicator.beginEditing()
    }

    func endIndicatorEditing() {
        indicator.endEditing()
        indicator.show(phase.indicatorStyle)
    }

    private func saveIndicatorPosition(_ center: CGPoint) {
        let current = settings.indicator
        settings = settings.with(\.indicator, IndicatorSettings(size: current.size, opacity: current.opacity, centerX: center.x, centerY: center.y))
        settingsStore.save(settings)
    }

    // MARK: - History

    func clearHistory() {
        history = history.cleared()
    }

    func copyAnswer(entryID: UUID) {
        guard let answer = history.entries.first(where: { $0.id == entryID })?.answer else { return }
        TextInserter.copy(answer)
    }
}
