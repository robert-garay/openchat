import AVFoundation

/// Live amplitude readings (0...1) for driving the voice UI's waveform.
struct VoiceAudioLevels: Equatable, Sendable {
    var input: Float
    var output: Float
}

/// Thread-safe mute flag read from the real-time audio tap thread, written
/// from the actor. A plain `NSLock` box rather than actor isolation because
/// the tap callback must stay fully synchronous — it cannot `await`.
private final class MutedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

/// Abstracts mic capture / playback so `VoiceConversationController` can be
/// unit tested without touching `AVAudioEngine`. The concrete implementation
/// is exercised manually on-device — see the voice mode design spec.
protocol VoiceAudioEngineProtocol: AnyObject, Sendable {
    /// 24kHz mono PCM16 chunks captured from the mic, ready to send to the Realtime API.
    nonisolated var capturedAudio: AsyncStream<Data> { get }
    nonisolated var levels: AsyncStream<VoiceAudioLevels> { get }

    func start() async throws
    func stop() async
    /// Schedules a 24kHz mono PCM16 chunk received from the Realtime API for playback.
    func enqueuePlayback(_ pcm16: Data) async
    /// Stops any in-flight playback immediately, e.g. on user barge-in.
    func stopPlayback() async
    func setMuted(_ muted: Bool) async
}

/// `AVAudioEngine`-backed mic capture and playback at the Realtime API's
/// wire format (24kHz mono PCM16).
actor VoiceAudioEngine: VoiceAudioEngineProtocol {
    static let realtimeFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    /// Immutable after `init`, so safe to read without actor isolation —
    /// callers await once to obtain the stream, then iterate it freely.
    nonisolated let capturedAudio: AsyncStream<Data>
    nonisolated let levels: AsyncStream<VoiceAudioLevels>

    private let audioContinuation: AsyncStream<Data>.Continuation
    private let levelContinuation: AsyncStream<VoiceAudioLevels>.Continuation

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mutedFlag = MutedFlag()
    private var isRunning = false
    private var playbackConverter: AVAudioConverter?

    init() {
        let (audioStream, audioCont) = AsyncStream<Data>.makeStream()
        let (levelStream, levelCont) = AsyncStream<VoiceAudioLevels>.makeStream()
        capturedAudio = audioStream
        levels = levelStream
        audioContinuation = audioCont
        levelContinuation = levelCont
    }

    func start() async throws {
        guard !isRunning else { return }

        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
        #endif

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.realtimeFormat) else {
            throw RealtimeVoiceError.audioEngineUnavailable
        }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)

        // Runs on a real-time audio thread: stays fully synchronous (no actor
        // hop, no `Task {}`) and only touches thread-safe captures — the
        // converter, the mute flag, and the two stream continuations, all of
        // which are safe to use from any thread.
        let mutedFlag = mutedFlag
        let audioContinuation = audioContinuation
        let levelContinuation = levelContinuation
        let ratio = Self.realtimeFormat.sampleRate / inputFormat.sampleRate
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { buffer, _ in
            guard !mutedFlag.get(),
                  let outputBuffer = Self.convert(buffer, using: converter, ratio: ratio, to: Self.realtimeFormat),
                  let data = Self.data(from: outputBuffer) else { return }
            audioContinuation.yield(data)
            levelContinuation.yield(VoiceAudioLevels(input: Self.rmsLevel(of: outputBuffer), output: 0))
        }

        engine.prepare()
        try engine.start()
        playerNode.play()
        isRunning = true
    }

    func stop() async {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        isRunning = false
        playbackConverter = nil
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    func enqueuePlayback(_ pcm16: Data) async {
        guard isRunning, !pcm16.isEmpty else { return }
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        if playbackConverter == nil {
            playbackConverter = AVAudioConverter(from: Self.realtimeFormat, to: outputFormat)
        }
        guard let converter = playbackConverter,
              let sourceBuffer = Self.pcmBuffer(from: pcm16, format: Self.realtimeFormat) else { return }

        let ratio = outputFormat.sampleRate / Self.realtimeFormat.sampleRate
        guard let outputBuffer = Self.convert(sourceBuffer, using: converter, ratio: ratio, to: outputFormat) else { return }

        playerNode.scheduleBuffer(outputBuffer, completionHandler: nil)
        emitOutputLevel(for: outputBuffer)
    }

    func stopPlayback() async {
        playerNode.stop()
        playerNode.play()
    }

    func setMuted(_ muted: Bool) async {
        mutedFlag.set(muted)
    }

    private func emitOutputLevel(for buffer: AVAudioPCMBuffer) {
        levelContinuation.yield(VoiceAudioLevels(input: 0, output: Self.rmsLevel(of: buffer)))
    }

    /// Converts `buffer` to `format` via `converter`. Static and side-effect
    /// free so it can run directly on the audio-tap thread without hopping
    /// onto the actor.
    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        ratio: Double,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, outputBuffer.frameLength > 0 else { return nil }
        return outputBuffer
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            let sample = channelData[frame]
            sum += sample * sample
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(rms * 4, 1)
    }

    private static func pcmBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: Int16.self).baseAddress,
                  let destination = buffer.int16ChannelData?[0] else { return }
            destination.update(from: source, count: Int(frameCount))
        }
        return buffer
    }

    private static func data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData?[0] else { return nil }
        return Data(bytes: channelData, count: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
    }
}
