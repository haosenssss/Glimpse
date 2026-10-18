import Foundation

/// A global shortcut. `modifiers` uses Carbon's flag values so it can be handed
/// straight to `RegisterEventHotKey`.
public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000

    public let keyCode: UInt32
    public let modifiers: UInt32
    public let keyLabel: String

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public var displayString: String {
        let symbols: [(UInt32, String)] = [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
        return symbols.filter { modifiers & $0.0 != 0 }.map(\.1).joined() + keyLabel
    }

    /// ⌘ plus a single key (⌘C, ⌘X, ⌘Q…) belongs to the frontmost app; a global hotkey would steal it everywhere.
    public var isReservedByApps: Bool {
        let isFunctionKey = keyLabel.count > 1 && keyLabel.hasPrefix("F")
        return modifiers == Self.command && !isFunctionKey
    }

    public static func == (lhs: Hotkey, rhs: Hotkey) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }
}

public struct IndicatorSettings: Codable, Equatable, Sendable {
    public static let sizeRange: ClosedRange<Double> = 6...24
    public static let opacityRange: ClosedRange<Double> = 0.1...1
    public static let `default` = IndicatorSettings(size: 10, opacity: 0.35, centerX: nil, centerY: nil)

    public let size: Double
    public let opacity: Double
    /// Center in global screen coordinates; `nil` means the default corner.
    public let centerX: Double?
    public let centerY: Double?

    public init(size: Double, opacity: Double, centerX: Double?, centerY: Double?) {
        self.size = size
        self.opacity = opacity
        self.centerX = centerX
        self.centerY = centerY
    }

    public func clamped() -> IndicatorSettings {
        IndicatorSettings(
            size: min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound),
            opacity: min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound),
            centerX: centerX, centerY: centerY
        )
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public enum ValidationError: Equatable, Sendable {
        case hotkeyConflict
    }

    public static let `default` = AppSettings(
        baseURL: "https://api.openai.com/v1",
        model: "",
        systemPrompt: DefaultPrompt.text,
        captureHotkey: Hotkey(keyCode: 5, modifiers: Hotkey.control | Hotkey.option, keyLabel: "G"),
        quitHotkey: Hotkey(keyCode: 12, modifiers: Hotkey.control | Hotkey.option, keyLabel: "Q"),
        timeoutSeconds: 60,
        indicator: .default
    )

    public var baseURL: String
    public var model: String
    public var systemPrompt: String
    public var captureHotkey: Hotkey
    public var quitHotkey: Hotkey
    public var timeoutSeconds: Double
    public var indicator: IndicatorSettings

    public init(
        baseURL: String, model: String, systemPrompt: String, captureHotkey: Hotkey,
        quitHotkey: Hotkey, timeoutSeconds: Double, indicator: IndicatorSettings
    ) {
        self.baseURL = baseURL
        self.model = model
        self.systemPrompt = systemPrompt
        self.captureHotkey = captureHotkey
        self.quitHotkey = quitHotkey
        self.timeoutSeconds = timeoutSeconds
        self.indicator = indicator
    }

    /// Missing keys fall back to defaults so adding a setting never wipes the others.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? fallback.baseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? fallback.model
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? fallback.systemPrompt
        captureHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .captureHotkey) ?? fallback.captureHotkey
        quitHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .quitHotkey) ?? fallback.quitHotkey
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? fallback.timeoutSeconds
        indicator = try container.decodeIfPresent(IndicatorSettings.self, forKey: .indicator) ?? fallback.indicator
    }

    /// Returns a copy with one field changed.
    public func with<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>, _ value: Value) -> AppSettings {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }

    public var validationErrors: [ValidationError] {
        captureHotkey == quitHotkey ? [.hotkeyConflict] : []
    }
}

public struct SettingsStore: Sendable {
    public static let key = "settings.v1"

    // UserDefaults is thread-safe; it just isn't annotated Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return Self.migrated(settings)
    }

    /// Upgrades an untouched old default prompt and drops hotkeys that would steal app shortcuts.
    private static func migrated(_ settings: AppSettings) -> AppSettings {
        let fallback = AppSettings.default
        let prompt = DefaultPrompt.previousVersions.contains(settings.systemPrompt) ? DefaultPrompt.text : settings.systemPrompt
        return settings
            .with(\.systemPrompt, prompt)
            .with(\.captureHotkey, settings.captureHotkey.isReservedByApps ? fallback.captureHotkey : settings.captureHotkey)
            .with(\.quitHotkey, settings.quitHotkey.isReservedByApps ? fallback.quitHotkey : settings.quitHotkey)
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
