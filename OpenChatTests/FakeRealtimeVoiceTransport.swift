import Foundation
@testable import OpenChat

/// In-memory `RealtimeVoiceTransport` double: records every outbound frame and
/// lets tests push inbound frames without a real WebSocket connection.
/// Shared by `RealtimeVoiceSessionTests` and `VoiceConversationControllerTests`.
actor FakeRealtimeVoiceTransport: RealtimeVoiceTransport {
    private(set) var connectedURL: URL?
    private(set) var connectedAPIKey: String?
    private(set) var sentPayloads: [Data] = []
    private(set) var closeCallCount = 0

    private nonisolated let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(of: Data.self)
        self.stream = stream
        self.continuation = continuation
    }

    func connect(url: URL, apiKey: String) async throws {
        connectedURL = url
        connectedAPIKey = apiKey
    }

    func send(_ data: Data) async throws {
        sentPayloads.append(data)
    }

    nonisolated func receive() -> AsyncThrowingStream<Data, Error> {
        stream
    }

    func close() async {
        closeCallCount += 1
        continuation.finish()
    }

    /// Test helper: pushes one raw server frame into the event stream.
    func simulateReceive(_ json: String) {
        continuation.yield(Data(json.utf8))
    }

    func simulateFinish(throwing error: Error? = nil) {
        continuation.finish(throwing: error)
    }

    /// Raw JSON bytes only — `[String: Any]` isn't `Sendable`, so callers
    /// decode it themselves on their own side of the actor boundary.
    func sentPayloadData(at index: Int) -> Data? {
        guard index < sentPayloads.count else { return nil }
        return sentPayloads[index]
    }
}

extension Data {
    var jsonObject: [String: Any]? {
        try? JSONSerialization.jsonObject(with: self) as? [String: Any]
    }
}
