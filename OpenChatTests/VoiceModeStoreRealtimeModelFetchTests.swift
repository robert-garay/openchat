import XCTest
@testable import OpenChat

/// `MockURLProtocol`'s stub queue is process-global. XCTestCase methods run
/// serially within a process by default, avoiding the cross-test races Swift
/// Testing's default concurrent scheduling would hit here — see
/// `BackgroundCompatibleDataRetryTests` for the same pattern.
@MainActor
final class VoiceModeStoreRealtimeModelFetchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeStore() -> VoiceModeStore {
        VoiceModeStore(
            defaults: UserDefaults(suiteName: "com.openchat.tests.voicemode.fetch.\(UUID().uuidString)")!,
            modelsClient: ProviderModelsClient(session: makeSession())
        )
    }

    func testRefreshFetchesSortsAndAutoSelectsFirstModel() async throws {
        MockURLProtocol.enqueue(json: """
        {
          "data": [
            { "id": "gpt-4o-mini-realtime-preview" },
            { "id": "gpt-4o" },
            { "id": "gpt-4o-realtime-preview" }
          ]
        }
        """)
        let store = makeStore()

        store.refreshRealtimeModelsIfNeeded(baseURL: "https://api.openai.com/v1", apiKey: "sk-test")
        try await waitUntilNotLoading(store)

        XCTAssertEqual(store.realtimeModels.map(\.id), ["gpt-4o-mini-realtime-preview", "gpt-4o-realtime-preview"])
        XCTAssertEqual(store.modelID, "gpt-4o-mini-realtime-preview")
        XCTAssertNil(store.realtimeModelsError)
    }

    func testRefreshSurfacesErrorWithoutTouchingModelID() async throws {
        MockURLProtocol.enqueue(error: URLError(.notConnectedToInternet))
        let store = makeStore()

        store.refreshRealtimeModelsIfNeeded(baseURL: "https://api.openai.com/v1", apiKey: "sk-test")
        try await waitUntilNotLoading(store)

        XCTAssertTrue(store.realtimeModels.isEmpty)
        XCTAssertEqual(store.modelID, "")
        XCTAssertNotNil(store.realtimeModelsError)
    }

    func testRefreshDoesNotOverwriteAnAlreadyChosenModel() async throws {
        MockURLProtocol.enqueue(json: """
        {"data": [{ "id": "gpt-4o-realtime-preview" }]}
        """)
        let store = makeStore()
        store.setModel("gpt-4o-mini-realtime-preview")

        store.refreshRealtimeModelsIfNeeded(baseURL: "https://api.openai.com/v1", apiKey: "sk-test")
        try await waitUntilNotLoading(store)

        XCTAssertEqual(store.modelID, "gpt-4o-mini-realtime-preview")
    }

    private func waitUntilNotLoading(
        _ store: VoiceModeStore,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while store.isLoadingRealtimeModels, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.isLoadingRealtimeModels, "Timed out waiting for the fetch to finish")
    }
}
