import Testing
@testable import GlimpseCore

@Suite struct ModelCatalogTests {
    @Test func keepsOnlyImageModelsWhenServerReportsModalities() {
        let models = [
            ModelInfo(id: "a/vision", acceptsImages: true),
            ModelInfo(id: "b/text", acceptsImages: false),
            ModelInfo(id: "c/unknown", acceptsImages: nil),
        ]
        #expect(ModelCatalog.selectable(models).map(\.id) == ["a/vision"])
    }

    @Test func keepsEverythingWhenServerSaysNothingAboutImages() {
        let models = [ModelInfo(id: "gpt-4o", acceptsImages: nil), ModelInfo(id: "gpt-4.1", acceptsImages: nil)]
        #expect(ModelCatalog.selectable(models).map(\.id) == ["gpt-4o", "gpt-4.1"])
    }

    @Test func shortListsStayFlat() {
        let groups = ModelCatalog.grouped(["openai/gpt-4o", "google/gemini"], flatLimit: 30)
        #expect(groups == [ModelGroup(name: nil, models: ["openai/gpt-4o", "google/gemini"])])
    }

    @Test func longListsAreGroupedByProviderPrefix() {
        let ids = ["openai/gpt-4o", "google/gemini-2.5-flash", "openai/gpt-4.1", "solo-model"]
        let groups = ModelCatalog.grouped(ids, flatLimit: 2)
        #expect(groups == [
            ModelGroup(name: "google", models: ["google/gemini-2.5-flash"]),
            ModelGroup(name: "openai", models: ["openai/gpt-4o", "openai/gpt-4.1"]),
            ModelGroup(name: nil, models: ["solo-model"]),
        ])
    }
}
