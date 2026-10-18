import Foundation

public struct ModelGroup: Equatable, Sendable {
    /// Provider prefix such as "openai"; `nil` for models without one (or for a flat list).
    public let name: String?
    public let models: [String]

    public init(name: String?, models: [String]) {
        self.name = name
        self.models = models
    }
}

/// Turns a raw `/models` listing into something pickable from a menu.
public enum ModelCatalog {
    public static let defaultFlatLimit = 30

    /// Glimpse always sends an image, so when the server says which models accept
    /// images, only those are offered. Otherwise everything is.
    public static func selectable(_ models: [ModelInfo]) -> [ModelInfo] {
        guard models.contains(where: { $0.acceptsImages != nil }) else { return models }
        return models.filter { $0.acceptsImages == true }
    }

    /// Short lists stay flat; long ones are grouped by the "provider/" prefix
    /// (named groups alphabetically, unprefixed models last).
    public static func grouped(_ ids: [String], flatLimit: Int = defaultFlatLimit) -> [ModelGroup] {
        guard ids.count > flatLimit else { return [ModelGroup(name: nil, models: ids)] }

        var order: [String] = []
        var byProvider: [String: [String]] = [:]
        var unprefixed: [String] = []
        for id in ids {
            guard let slash = id.firstIndex(of: "/") else {
                unprefixed.append(id)
                continue
            }
            let provider = String(id[..<slash])
            if byProvider[provider] == nil { order.append(provider) }
            byProvider[provider, default: []].append(id)
        }

        let named = order.sorted().map { ModelGroup(name: $0, models: byProvider[$0] ?? []) }
        return unprefixed.isEmpty ? named : named + [ModelGroup(name: nil, models: unprefixed)]
    }
}
