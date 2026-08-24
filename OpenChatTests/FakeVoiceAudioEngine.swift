import Foundation
@testable import OpenChat

/// In-memory `VoiceAudioEngineProtocol` double — no real `AVAudioEngine`/mic
/// access, so `VoiceConversationController` can be exercised in a unit test.
final class FakeVoiceAudioEngine: VoiceAudioEngineProtocol, @unchecked Sendable {
    nonisolated let capturedAudio: AsyncStream<Data>
    nonisolated let levels: AsyncStream<VoiceAudioLevels>

    private let lock = NSLock()
    private var _startCallCount = 0
    private var _stopCallCount = 0
    private var _playedChunks: [Data] = []
    private var _mutedStates: [Bool] = []

    var startCallCount: Int { lock.withLock { _startCallCount } }
    var stopCallCount: Int { lock.withLock { _stopCallCount } }
    var playedChunks: [Data] { lock.withLock { _playedChunks } }
    var mutedStates: [Bool] { lock.withLock { _mutedStates } }

    init() {
        let (audioStream, _) = AsyncStream<Data>.makeStream()
        capturedAudio = audioStream
        let (levelStream, _) = AsyncStream<VoiceAudioLevels>.makeStream()
        levels = levelStream
    }

    func start() async throws {
        lock.withLock { _startCallCount += 1 }
    }

    func stop() async {
        lock.withLock { _stopCallCount += 1 }
    }

    func enqueuePlayback(_ pcm16: Data) async {
        lock.withLock { _playedChunks.append(pcm16) }
    }

    func stopPlayback() async {}

    func setMuted(_ muted: Bool) async {
        lock.withLock { _mutedStates.append(muted) }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
