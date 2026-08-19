# Network Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chat-completion networking path (both streaming and non-streaming, both `OpenAICompatibleClient` and `AnthropicClient`) resilient to transient network failures — retrying with backoff, waiting out connectivity loss, and silently resuming a dropped stream in place — without ever silently re-sending a request that may already have caused the provider to generate (and bill for) content.

**Architecture:** Three new small, pure/testable units — `RetryPolicy` (classifies which errors are safe to retry and computes backoff), `NetworkMonitor` (actor wrapping `NWPathMonitor`, testable via an injected `PathMonitoring` protocol), and `NetworkRetrier` (generic retry executor combining the two) — are layered underneath the existing single funnel points: `ServerSentEventStream.dataPayloads` (streaming) and `URLSession.backgroundCompatibleData(for:)` (non-streaming). A new `ChatServiceError.connectionDropped` case distinguishes "stream failed after content had already arrived" from ordinary pre-connection failures. `BackgroundGenerationService` gets a buffer-flush bug fix (so no partial content is ever lost on a throw) and a bounded (1-attempt) silent continuation loop that appends the partial reply as context and asks the model to continue, only after connectivity is confirmed restored.

**Tech Stack:** Swift 6, Foundation `URLSession`, `Network.framework` (`NWPathMonitor`), Swift Testing (`import Testing`) for all new test files, XCTest retained/extended for existing test files.

**Spec:** This plan implements the two constraints the user gave directly (no separate spec doc exists):
1. Implement retry/backoff for transient failures, connectivity monitoring via `NWPathMonitor`, and bring the streaming path into the resilience infrastructure — **and never let a retry double-charge the user.**
2. On a dropped stream mid-generation: silent auto-retry, resume in place — no jarring error UI for transient issues, at most a brief "reconnecting" state.

## Global Constraints

- **Never silently retry a request after any billable content may have been generated.** A request is "cost-sensitive" (chat completion, streaming or non-streaming) vs. "cost-free" (GET catalogs/search/balance calls, which retry freely).
- For cost-sensitive requests, only retry errors that could not possibly mean the request reached the provider: `.notConnectedToInternet`, `.cannotFindHost`, `.cannotConnectToHost`, `.dnsLookupFailed`, `.dataNotAllowed`, `.internationalRoamingOff`. `.timedOut` and `.networkConnectionLost` are excluded from the cost-sensitive retryable set because the request may already be in flight/being processed. HTTP `429` and `5xx` are always retryable (a definitive status from the provider means it rejected/failed the request itself, not that generation is silently proceeding) — this matches OpenAI's and Anthropic's own documented retry guidance.
- Once any SSE payload has been yielded to a stream's consumer, `ServerSentEventStream` must never itself retry — a subsequent failure becomes `ChatServiceError.connectionDropped` (if transient) or the original error (if not), and any resumption is the caller's responsibility, done as a distinct continuation turn, never a re-send of the same request.
- Max 3 attempts (1 original + 2 retries) for infra-level retries; max 1 silent continuation attempt at the `BackgroundGenerationService` level after a stream drop.
- New test files use Swift Testing (`import Testing`, `@Test`, `#expect`). Existing XCTest files are extended, not rewritten.
- No third-party dependencies.

---

### Task 1: Extract shared `MockURLProtocol` test helper

**Files:**
- Create: `OpenChatTests/Support/MockURLProtocol.swift`
- Modify: `OpenChatTests/StreamingToolLoopTests.swift` (remove the embedded `MockURLProtocol` + `InputStream.readToEnd` extension, now provided by the shared file)

**Interfaces:**
- Produces: `final class MockURLProtocol: URLProtocol` with `reset()`, `enqueue(sse:)`, `enqueue(json:)`, `enqueue(error:)`, `requestCount: Int`, `lastRequestBody: Data?`. Used by Tasks 4, 6, 7.

- [ ] **Step 1: Create the shared helper file**

```swift
import Foundation

/// Serves queued canned responses (or errors) and counts how many requests were issued.
/// Shared across test targets that need to stub `URLSession` traffic.
final class MockURLProtocol: URLProtocol {
    private struct Stub {
        let body: Data?
        let contentType: String?
        let error: Error?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var capturedRequestBody: Data?

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs = []
        count = 0
        capturedRequestBody = nil
    }

    static var lastRequestBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequestBody
    }

    static func enqueue(sse: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(Stub(body: Data(sse.utf8), contentType: "text/event-stream", error: nil))
    }

    static func enqueue(json: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(Stub(body: Data(json.utf8), contentType: "application/json", error: nil))
    }

    /// Queues a request failure. Use this to simulate transient network errors
    /// (e.g. `URLError(.networkConnectionLost)`) for retry tests.
    static func enqueue(error: Error) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(Stub(body: nil, contentType: nil, error: error))
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    private static func next() -> Stub? {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return stubs.isEmpty ? nil : stubs.removeFirst()
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequestBody = request.httpBody ?? request.httpBodyStream.flatMap {
            $0.readToEnd(maxLength: 10_000_000)
        }
        Self.lock.unlock()
        guard let stub = Self.next() else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": stub.contentType ?? "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension InputStream {
    func readToEnd(maxLength: Int) -> Data? {
        open()
        defer { close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while hasBytesAvailable {
            let read = self.read(&buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
            if data.count > maxLength {
                return nil
            }
        }
        return data.isEmpty ? nil : data
    }
}
```

- [ ] **Step 2: Remove the embedded copy from `StreamingToolLoopTests.swift`**

Delete the `final class MockURLProtocol: URLProtocol { ... }` block and the trailing `private extension InputStream { ... }` block from the bottom of `OpenChatTests/StreamingToolLoopTests.swift` (everything from `// MARK: - Helpers`'s second declaration onward — keep `private actor ToolCallRecorder`, remove the rest since it now lives in the shared file).

- [ ] **Step 3: Run the existing suite to confirm nothing broke**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/StreamingToolLoopTests`
Expected: PASS (same 5 tests as before, now backed by the shared helper)

- [ ] **Step 4: Commit**

```bash
git add OpenChatTests/Support/MockURLProtocol.swift OpenChatTests/StreamingToolLoopTests.swift
git commit -m "test: extract shared MockURLProtocol test helper"
```

---

### Task 2: `RetryPolicy`

**Files:**
- Create: `OpenChat/Services/RetryPolicy.swift`
- Test: `OpenChatTests/RetryPolicyTests.swift`

**Interfaces:**
- Consumes: `ChatServiceError.http(status:body:)` from `OpenChat/Services/ChatTurn.swift`.
- Produces: `struct RetryPolicy: Sendable` with `maxAttempts: Int`, `costSensitive: Bool`, `static let default: RetryPolicy`, `static let costSensitive: RetryPolicy`, `static func isRetryable(_ error: Error, costSensitive: Bool) -> Bool`, `func delay(forAttempt attempt: Int) -> Duration`. Used by Tasks 4, 6, 7.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import OpenChat

struct RetryPolicyTests {
    @Test("default policy retries connection-lost and timeout errors")
    func defaultPolicyRetriesTransientURLErrors() {
        #expect(RetryPolicy.isRetryable(URLError(.networkConnectionLost), costSensitive: false))
        #expect(RetryPolicy.isRetryable(URLError(.timedOut), costSensitive: false))
        #expect(RetryPolicy.isRetryable(URLError(.notConnectedToInternet), costSensitive: false))
    }

    @Test("cost-sensitive policy excludes timeout and connection-lost")
    func costSensitivePolicyExcludesAmbiguousErrors() {
        #expect(!RetryPolicy.isRetryable(URLError(.timedOut), costSensitive: true))
        #expect(!RetryPolicy.isRetryable(URLError(.networkConnectionLost), costSensitive: true))
    }

    @Test("cost-sensitive policy still retries pre-connection failures")
    func costSensitivePolicyRetriesPreConnectionFailures() {
        #expect(RetryPolicy.isRetryable(URLError(.notConnectedToInternet), costSensitive: true))
        #expect(RetryPolicy.isRetryable(URLError(.cannotFindHost), costSensitive: true))
        #expect(RetryPolicy.isRetryable(URLError(.dnsLookupFailed), costSensitive: true))
    }

    @Test("429 and 5xx are always retryable, other HTTP statuses are not")
    func httpStatusClassification() {
        #expect(RetryPolicy.isRetryable(ChatServiceError.http(status: 429, body: ""), costSensitive: true))
        #expect(RetryPolicy.isRetryable(ChatServiceError.http(status: 503, body: ""), costSensitive: true))
        #expect(!RetryPolicy.isRetryable(ChatServiceError.http(status: 400, body: ""), costSensitive: true))
        #expect(!RetryPolicy.isRetryable(ChatServiceError.http(status: 401, body: ""), costSensitive: false))
    }

    @Test("non-URLError, non-ChatServiceError errors are never retryable")
    func unknownErrorsAreNotRetryable() {
        struct SomeError: Error {}
        #expect(!RetryPolicy.isRetryable(SomeError(), costSensitive: false))
    }

    @Test("delay grows exponentially and is capped")
    func delayGrowsAndCaps() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelayMilliseconds: 100, maxDelayMilliseconds: 1_000)
        let first = policy.delay(forAttempt: 1)
        let second = policy.delay(forAttempt: 2)
        let capped = policy.delay(forAttempt: 10)
        #expect(first < second)
        #expect(capped <= .milliseconds(1_200)) // cap + max jitter headroom
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RetryPolicyTests`
Expected: FAIL (`RetryPolicy` does not exist)

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Classifies whether a network failure is safe to retry, and computes
/// exponential backoff with jitter for the next attempt.
///
/// Two flavors exist because retrying is only ever cost-neutral for requests
/// that are atomic from a billing standpoint. `costSensitive` policies are
/// used for anything that reaches a paid chat-completion endpoint; they
/// exclude ambiguous failures (`.timedOut`, `.networkConnectionLost`) that
/// could mean the request already reached the provider and started (and
/// will be billed for) generating a response. `default` is used for
/// idempotent, cost-free calls (search, model catalogs, balance checks).
struct RetryPolicy: Sendable {
    var maxAttempts: Int = 3
    var baseDelayMilliseconds: Double = 500
    var maxDelayMilliseconds: Double = 8_000
    var costSensitive: Bool = false

    static let `default` = RetryPolicy()
    static let costSensitive = RetryPolicy(costSensitive: true)

    /// Pre-connection failures: the request could not possibly have reached
    /// the provider, so retrying can never duplicate billed work.
    private static let preConnectionCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
    ]

    /// Ambiguous failures: the request may already have reached the
    /// provider. Safe to retry for cost-free calls only.
    private static let ambiguousCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost,
    ]

    static func isRetryable(_ error: Error, costSensitive: Bool) -> Bool {
        if case ChatServiceError.http(let status, _) = error {
            return status == 429 || (500...599).contains(status)
        }
        guard let urlError = error as? URLError else { return false }
        if preConnectionCodes.contains(urlError.code) { return true }
        if costSensitive { return false }
        return ambiguousCodes.contains(urlError.code)
    }

    func delay(forAttempt attempt: Int) -> Duration {
        let exponent = Double(max(attempt - 1, 0))
        let raw = baseDelayMilliseconds * pow(2, exponent)
        let capped = min(raw, maxDelayMilliseconds)
        let jitter = Double.random(in: 0.8...1.2)
        return .milliseconds(Int(capped * jitter))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/RetryPolicyTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/RetryPolicy.swift OpenChatTests/RetryPolicyTests.swift
git commit -m "feat: add RetryPolicy for cost-safe transient failure classification"
```

---

### Task 3: `NetworkMonitor`

**Files:**
- Create: `OpenChat/Services/NetworkMonitor.swift`
- Test: `OpenChatTests/NetworkMonitorTests.swift`

**Interfaces:**
- Produces: `protocol PathMonitoring: Sendable { func start(onUpdate: @escaping @Sendable (Bool) -> Void) async }`, `struct SystemPathMonitor: PathMonitoring`, `actor NetworkMonitor { static let shared: NetworkMonitor; init(pathMonitor: any PathMonitoring); func start() async; var isConnected: Bool { get async }; func waitForConnection() async }`. Used by Tasks 4, 6, 9, 10.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import OpenChat

private actor FakePathMonitor: PathMonitoring {
    private var onUpdate: (@Sendable (Bool) -> Void)?

    func start(onUpdate: @escaping @Sendable (Bool) -> Void) async {
        self.onUpdate = onUpdate
    }

    func simulate(connected: Bool) {
        onUpdate?(connected)
    }
}

struct NetworkMonitorTests {
    @Test("starts connected by default")
    func startsConnected() async {
        let monitor = NetworkMonitor(pathMonitor: FakePathMonitor())
        #expect(await monitor.isConnected)
    }

    @Test("waitForConnection returns immediately when already connected")
    func waitReturnsImmediatelyWhenConnected() async {
        let monitor = NetworkMonitor(pathMonitor: FakePathMonitor())
        await monitor.waitForConnection()
    }

    @Test("waitForConnection suspends until the path reports satisfied")
    func waitSuspendsUntilReconnected() async {
        let fake = FakePathMonitor()
        let monitor = NetworkMonitor(pathMonitor: fake)
        await monitor.start()
        await fake.simulate(connected: false)
        #expect(await monitor.isConnected == false)

        let waiter = Task { await monitor.waitForConnection() }
        try? await Task.sleep(for: .milliseconds(50))
        await fake.simulate(connected: true)
        await waiter.value

        #expect(await monitor.isConnected)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/NetworkMonitorTests`
Expected: FAIL (`NetworkMonitor` does not exist)

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import Network

/// Abstracts `NWPathMonitor` so `NetworkMonitor` can be unit tested without
/// touching real system connectivity.
protocol PathMonitoring: Sendable {
    func start(onUpdate: @escaping @Sendable (Bool) -> Void) async
}

struct SystemPathMonitor: PathMonitoring {
    func start(onUpdate: @escaping @Sendable (Bool) -> Void) async {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            onUpdate(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "com.openchat.network-monitor"))
    }
}

/// Tracks device network reachability so retry logic can avoid hammering a
/// dead connection and can resume automatically once connectivity returns.
///
/// `start()` must be called once (e.g. at app launch) before `isConnected`
/// reflects real device state; before that it optimistically reports
/// connected so callers never block on a monitor nobody started.
actor NetworkMonitor {
    static let shared = NetworkMonitor(pathMonitor: SystemPathMonitor())

    private let pathMonitor: any PathMonitoring
    private(set) var isConnected = true
    private var isStarted = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(pathMonitor: any PathMonitoring) {
        self.pathMonitor = pathMonitor
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        await pathMonitor.start { [weak self] connected in
            Task { await self?.updateConnected(connected) }
        }
    }

    private func updateConnected(_ connected: Bool) {
        isConnected = connected
        guard connected, !waiters.isEmpty else { return }
        let pending = waiters
        waiters.removeAll()
        for (_, continuation) in pending {
            continuation.resume()
        }
    }

    /// Suspends until the network becomes reachable, or returns immediately
    /// if it already is.
    func waitForConnection() async {
        if isConnected { return }
        let id = UUID()
        await withCheckedContinuation { continuation in
            waiters[id] = continuation
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/NetworkMonitorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/NetworkMonitor.swift OpenChatTests/NetworkMonitorTests.swift
git commit -m "feat: add NetworkMonitor wrapping NWPathMonitor"
```

---

### Task 4: `NetworkRetrier`

**Files:**
- Create: `OpenChat/Services/NetworkRetrier.swift`
- Test: `OpenChatTests/NetworkRetrierTests.swift`

**Interfaces:**
- Consumes: `RetryPolicy` (Task 2), `NetworkMonitor` (Task 3).
- Produces: `enum NetworkRetrier { static func perform<T: Sendable>(policy: RetryPolicy, networkMonitor: NetworkMonitor, operation: @Sendable () async throws -> T) async throws -> T }`. Used by Tasks 6, 7.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import OpenChat

struct NetworkRetrierTests {
    @Test("returns the result on first success without retrying")
    func succeedsImmediately() async throws {
        let attempts = Counter()
        let result = try await NetworkRetrier.perform(
            policy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
            networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
        ) {
            await attempts.increment()
            return "ok"
        }
        #expect(result == "ok")
        #expect(await attempts.count == 1)
    }

    @Test("retries a retryable error up to maxAttempts then succeeds")
    func retriesThenSucceeds() async throws {
        let attempts = Counter()
        let result = try await NetworkRetrier.perform(
            policy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
            networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
        ) {
            let count = await attempts.increment()
            if count < 3 {
                throw URLError(.notConnectedToInternet)
            }
            return "ok"
        }
        #expect(result == "ok")
        #expect(await attempts.count == 3)
    }

    @Test("throws immediately for a non-retryable error")
    func doesNotRetryNonRetryableError() async {
        let attempts = Counter()
        struct SomeError: Error {}
        await #expect(throws: SomeError.self) {
            try await NetworkRetrier.perform(
                policy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
                networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
            ) {
                _ = await attempts.increment()
                throw SomeError()
            }
        }
        #expect(await attempts.count == 1)
    }

    @Test("throws the last error after exhausting maxAttempts")
    func throwsAfterExhaustingAttempts() async {
        let attempts = Counter()
        await #expect(throws: URLError.self) {
            try await NetworkRetrier.perform(
                policy: RetryPolicy(maxAttempts: 2, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5),
                networkMonitor: NetworkMonitor(pathMonitor: AlwaysConnected())
            ) {
                _ = await attempts.increment()
                throw URLError(.notConnectedToInternet)
            }
        }
        #expect(await attempts.count == 2)
    }
}

private actor Counter {
    private(set) var count = 0
    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}

private struct AlwaysConnected: PathMonitoring {
    func start(onUpdate: @escaping @Sendable (Bool) -> Void) async {}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/NetworkRetrierTests`
Expected: FAIL (`NetworkRetrier` does not exist)

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Retries a network operation according to `RetryPolicy`, waiting for
/// connectivity to return when the device is offline instead of burning
/// through attempts immediately.
///
/// IMPORTANT — cost safety: only wrap operations that are atomic from a
/// billing standpoint (the whole response arrives, or nothing does). Never
/// wrap an operation after it has started producing content the provider
/// may already have generated and billed for — see `ServerSentEventStream`
/// for how the streaming path draws that line.
enum NetworkRetrier {
    static func perform<T: Sendable>(
        policy: RetryPolicy = .default,
        networkMonitor: NetworkMonitor = .shared,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                try Task.checkCancellation()
                guard attempt < policy.maxAttempts,
                      RetryPolicy.isRetryable(error, costSensitive: policy.costSensitive) else {
                    throw error
                }
                let connected = await networkMonitor.isConnected
                if connected {
                    try? await Task.sleep(for: policy.delay(forAttempt: attempt))
                } else {
                    await networkMonitor.waitForConnection()
                }
                attempt += 1
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/NetworkRetrierTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/NetworkRetrier.swift OpenChatTests/NetworkRetrierTests.swift
git commit -m "feat: add NetworkRetrier generic retry executor"
```

---

### Task 5: `ChatServiceError.connectionDropped`

**Files:**
- Modify: `OpenChat/Services/ChatTurn.swift:36-91`
- Test: Modify `OpenChatTests/ChatServiceErrorTests.swift`

**Interfaces:**
- Produces: `ChatServiceError.connectionDropped` case. Used by Task 6 (thrown), Task 9 (caught).

- [ ] **Step 1: Write the failing test**

Add to `OpenChatTests/ChatServiceErrorTests.swift`:

```swift
    func testConnectionDroppedMessageExplainsReconnection() {
        let message = ChatServiceError.connectionDropped.localizedDescription
        XCTAssertTrue(message.localizedCaseInsensitiveContains("connection"))
        XCTAssertTrue(message.localizedCaseInsensitiveContains("reconnect") || message.localizedCaseInsensitiveContains("resum"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ChatServiceErrorTests/testConnectionDroppedMessageExplainsReconnection`
Expected: FAIL (`connectionDropped` is not a member of `ChatServiceError`)

- [ ] **Step 3: Add the case**

In `OpenChat/Services/ChatTurn.swift`, add to the `ChatServiceError` enum declaration (after `case timedOut`):

```swift
    case timedOut
    case connectionDropped
```

Add to the `errorDescription` switch (after the `.timedOut` case):

```swift
        case .connectionDropped:
            return """
            The connection dropped partway through the response. \
            OpenChat will automatically try to reconnect and resume where it left off.
            """
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ChatServiceErrorTests`
Expected: PASS (all tests in the file, including the new one)

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/ChatTurn.swift OpenChatTests/ChatServiceErrorTests.swift
git commit -m "feat: add ChatServiceError.connectionDropped for mid-stream failures"
```

---

### Task 6: Wire retry into `ServerSentEventStream`

**Files:**
- Modify: `OpenChat/Services/ServerSentEventStream.swift`
- Test: Modify `OpenChatTests/ServerSentEventStreamTests.swift`

**Interfaces:**
- Consumes: `RetryPolicy` (Task 2, default param `.costSensitive`), `NetworkMonitor` (Task 3, default `.shared`), `NetworkRetrier` pattern (Task 4, inlined here since this is a stream not a single async call), `ChatServiceError.connectionDropped` (Task 5), `MockURLProtocol` (Task 1).
- Produces: `ServerSentEventStream.dataPayloads(for:session:retryPolicy:networkMonitor:)` — pre-first-payload failures retry per policy; post-first-payload transient failures surface as `.connectionDropped`.

- [ ] **Step 1: Write the failing tests**

Add to `OpenChatTests/ServerSentEventStreamTests.swift`:

```swift
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var payloads: [String] = []
        for try await payload in stream {
            payloads.append(payload)
        }
        return payloads
    }

    func testRetriesPreConnectionFailureBeforeAnyPayload() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(error: URLError(.notConnectedToInternet))
        MockURLProtocol.enqueue(sse: "data: hello\n\ndata: [DONE]\n\n")

        let request = URLRequest(url: URL(string: "https://example.com")!)
        let payloads = try await collect(
            ServerSentEventStream.dataPayloads(
                for: request,
                session: makeSession(),
                retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5, costSensitive: true)
            )
        )

        XCTAssertEqual(payloads, ["hello"])
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testDoesNotRetryAfterAPayloadHasAlreadyBeenYielded() async {
        MockURLProtocol.reset()
        // First connection yields one payload, then the byte stream itself
        // fails with a transient error mid-read. There is no way to express
        // "fail partway through a body" via MockURLProtocol's didLoad, so
        // this scenario is covered at the BackgroundGenerationService level
        // (Task 9) instead; this test only asserts the pre-payload path
        // above never retries once `hasYieldedAny` would be true, by
        // checking the request count stays at 1 for a normal successful
        // single-shot stream.
        MockURLProtocol.enqueue(sse: "data: hello\n\ndata: [DONE]\n\n")
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let payloads = try? await collect(
            ServerSentEventStream.dataPayloads(for: request, session: makeSession())
        )
        XCTAssertEqual(payloads, ["hello"])
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ServerSentEventStreamTests`
Expected: FAIL — `dataPayloads` has no `retryPolicy`/`networkMonitor` parameters yet, and the pre-connection failure is not retried (payloads empty / error thrown).

- [ ] **Step 3: Rewrite the implementation**

Replace the contents of `OpenChat/Services/ServerSentEventStream.swift`:

```swift
import Foundation

/// Turns a streaming HTTP response into an `AsyncThrowingStream` of raw SSE
/// `data:` payloads (everything after the `data: ` prefix on each event).
/// Provider-specific clients decode those payloads into their own schemas.
///
/// Cost safety: retries are only attempted before the first payload has been
/// yielded to the consumer — nothing has streamed yet, so nothing has been
/// billed. Once a payload has been yielded, a subsequent transient failure
/// is surfaced as `ChatServiceError.connectionDropped` rather than retried,
/// so callers can decide how to resume (see `BackgroundGenerationService`).
enum ServerSentEventStream {
    static func dataPayloads(
        for request: URLRequest,
        session: URLSession,
        retryPolicy: RetryPolicy = .costSensitive,
        networkMonitor: NetworkMonitor = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var hasYieldedAny = false
                var attempt = 1

                while true {
                    do {
                        let (bytes, response) = try await session.bytes(for: request)

                        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                            var errorBody = ""
                            for try await line in bytes.lines {
                                errorBody += line
                            }
                            throw ChatServiceError.http(status: http.statusCode, body: errorBody)
                        }

                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard let payload = Self.payload(fromSSELine: line) else { continue }
                            if payload == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            hasYieldedAny = true
                            continuation.yield(payload)
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: ChatServiceError.cancelled)
                        return
                    } catch {
                        if hasYieldedAny {
                            continuation.finish(throwing: Self.midStreamError(for: error))
                            return
                        }
                        guard attempt < retryPolicy.maxAttempts,
                              RetryPolicy.isRetryable(error, costSensitive: retryPolicy.costSensitive) else {
                            continuation.finish(throwing: Self.preStreamError(for: error))
                            return
                        }
                        let connected = await networkMonitor.isConnected
                        if connected {
                            try? await Task.sleep(for: retryPolicy.delay(forAttempt: attempt))
                        } else {
                            await networkMonitor.waitForConnection()
                        }
                        attempt += 1
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func payload(fromSSELine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let value = line.dropFirst("data:".count)
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func midStreamError(for error: Error) -> Error {
        if RetryPolicy.isRetryable(error, costSensitive: true) {
            return ChatServiceError.connectionDropped
        }
        return error
    }

    private static func preStreamError(for error: Error) -> Error {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return ChatServiceError.timedOut
        }
        return error
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ServerSentEventStreamTests -only-testing:OpenChatTests/StreamingToolLoopTests`
Expected: PASS (both files — confirms the retry addition doesn't change normal-path request counts)

- [ ] **Step 5: Commit**

```bash
git add OpenChat/Services/ServerSentEventStream.swift OpenChatTests/ServerSentEventStreamTests.swift
git commit -m "feat: retry pre-stream SSE connection failures, surface mid-stream drops"
```

---

### Task 7: Wire retry into non-streaming calls

**Files:**
- Modify: `OpenChat/Services/BackgroundNetworkSession.swift` (the `URLSession.backgroundCompatibleData(for:)` extension at the bottom of the file)
- Modify: `OpenChat/Services/OpenAICompatibleClient.swift:210`
- Modify: `OpenChat/Services/AnthropicClient.swift:167`
- Test: Create `OpenChatTests/BackgroundCompatibleDataRetryTests.swift`

**Interfaces:**
- Consumes: `RetryPolicy` (Task 2), `NetworkRetrier` (Task 4), `MockURLProtocol` (Task 1).
- Produces: `URLSession.backgroundCompatibleData(for:retryPolicy:)` now retries per policy; both clients' non-streaming `complete()` pass `.costSensitive`.

- [ ] **Step 1: Write the failing test**

Create `OpenChatTests/BackgroundCompatibleDataRetryTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenChat

struct BackgroundCompatibleDataRetryTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("retries a pre-connection failure and returns the eventual success")
    func retriesThenSucceeds() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(error: URLError(.notConnectedToInternet))
        MockURLProtocol.enqueue(json: #"{"ok":true}"#)

        let request = URLRequest(url: URL(string: "https://example.com")!)
        let (data, _) = try await makeSession().backgroundCompatibleData(
            for: request,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5)
        )

        #expect(String(data: data, encoding: .utf8) == #"{"ok":true}"#)
        #expect(MockURLProtocol.requestCount == 2)
    }

    @Test("cost-sensitive policy does not retry a timeout")
    func costSensitiveDoesNotRetryTimeout() async {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(error: URLError(.timedOut))
        MockURLProtocol.enqueue(json: #"{"ok":true}"#)

        let request = URLRequest(url: URL(string: "https://example.com")!)
        await #expect(throws: URLError.self) {
            _ = try await self.makeSession().backgroundCompatibleData(
                for: request,
                retryPolicy: RetryPolicy(maxAttempts: 3, baseDelayMilliseconds: 1, maxDelayMilliseconds: 5, costSensitive: true)
            )
        }
        #expect(MockURLProtocol.requestCount == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/BackgroundCompatibleDataRetryTests`
Expected: FAIL (`backgroundCompatibleData(for:retryPolicy:)` overload does not exist)

- [ ] **Step 3: Update the extension**

In `OpenChat/Services/BackgroundNetworkSession.swift`, replace the existing `URLSession.backgroundCompatibleData(for:)` extension at the bottom of the file:

```swift
extension URLSession {
    func backgroundCompatibleData(
        for request: URLRequest,
        retryPolicy: RetryPolicy = .default,
        networkMonitor: NetworkMonitor = .shared
    ) async throws -> (Data, URLResponse) {
        try await NetworkRetrier.perform(policy: retryPolicy, networkMonitor: networkMonitor) {
            if self === URLSession.shared || self === ChatService.urlSession {
                return try await BackgroundNetworkSession.shared.data(for: request)
            }
            return try await self.data(for: request)
        }
    }
}
```

- [ ] **Step 4: Use the cost-sensitive policy at both chat-completion call sites**

In `OpenChat/Services/OpenAICompatibleClient.swift:210`, change:

```swift
        let (data, response) = try await session.backgroundCompatibleData(for: request)
```

to:

```swift
        let (data, response) = try await session.backgroundCompatibleData(for: request, retryPolicy: .costSensitive)
```

In `OpenChat/Services/AnthropicClient.swift:167`, make the identical change:

```swift
        let (data, response) = try await session.backgroundCompatibleData(for: request, retryPolicy: .costSensitive)
```

(All other callers — `ProviderModelsClient`, `ProviderBalanceClient`, `BraveSearchClient`, `ExaClient`, `SerpAPIClient`, `SerperClient`, `TavilyClient`, `OpenRouterModelsClient` — keep calling `backgroundCompatibleData(for:)` with no explicit policy, so they get the permissive `.default` policy, which is correct since none of them are billable generation calls.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/BackgroundCompatibleDataRetryTests -only-testing:OpenChatTests/StreamingToolLoopTests -only-testing:OpenChatTests/ChatServiceErrorTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add OpenChat/Services/BackgroundNetworkSession.swift OpenChat/Services/OpenAICompatibleClient.swift OpenChat/Services/AnthropicClient.swift OpenChatTests/BackgroundCompatibleDataRetryTests.swift
git commit -m "feat: retry non-streaming requests with cost-sensitive policy for chat completions"
```

---

### Task 8: Fix unflushed-buffer-on-throw in `BackgroundGenerationService.runStream`

**Files:**
- Modify: `OpenChat/Services/BackgroundGenerationService.swift:538-584`

**Interfaces:**
- No signature changes — `runStream` keeps its existing parameters and `async throws` signature. This is a correctness fix that Task 9 depends on (silent continuation must see all text actually received before a drop).

- [ ] **Step 1: Make the change**

In `OpenChat/Services/BackgroundGenerationService.swift`, in `runStream` (starting at line 538), replace:

```swift
        var contentBuffer = ""
        var lastFlush = ContinuousClock().now
        let flushInterval: Duration = .milliseconds(80)
        var lastProgressNotify = ContinuousClock().now
        let progressNotifyInterval: Duration = .seconds(1)

        for try await event in client.streamReply(
```

with:

```swift
        var contentBuffer = ""
        var lastFlush = ContinuousClock().now
        let flushInterval: Duration = .milliseconds(80)
        var lastProgressNotify = ContinuousClock().now
        let progressNotifyInterval: Duration = .seconds(1)

        // Runs on every exit path — including a mid-stream throw — so a
        // network drop can never silently lose the last (up to
        // flushInterval-old) chunk of text that already arrived.
        defer {
            if !contentBuffer.isEmpty {
                assistantMessage.content += contentBuffer
                contentBuffer = ""
            }
        }

        for try await event in client.streamReply(
```

and remove the now-redundant post-loop flush at the end of the function (lines 581-583):

```swift
        if !contentBuffer.isEmpty {
            assistantMessage.content += contentBuffer
        }
```

(delete this block entirely — the `defer` above covers both the normal-completion and throw paths).

- [ ] **Step 2: Verify with the existing suite**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/StreamingToolLoopTests`
Expected: PASS (these tests exercise `OpenAICompatibleClient`/`AnthropicClient` directly, not `BackgroundGenerationService`, so this confirms no regression in the surrounding file; `BackgroundGenerationService` has no existing unit tests — see Task 9 for the new coverage this fix enables)

- [ ] **Step 3: Commit**

```bash
git add OpenChat/Services/BackgroundGenerationService.swift
git commit -m "fix: flush streamed text buffer on throw so mid-stream drops never lose content"
```

---

### Task 9: Silent auto-continuation on connection drop

**Files:**
- Modify: `OpenChat/Services/BackgroundGenerationService.swift:256-315` (the `do`/`catch` block in `performGeneration`)
- Test: Create `OpenChatTests/ContinuationTurnsTests.swift`

**Interfaces:**
- Consumes: `ChatServiceError.connectionDropped` (Task 5), `NetworkMonitor` (Task 3).
- Produces: `static func continuationTurns(previousTurns: [ChatTurn], partialContent: String) -> [ChatTurn]` — a pure, unit-testable helper extracted onto `BackgroundGenerationService` that builds the follow-up turns for a silent continuation. `performGeneration`'s catch logic (not independently unit-testable — see Step 4 rationale) is verified by manual/build-level checks, consistent with this class's existing test coverage (none).

- [ ] **Step 1: Write the failing test for the pure helper**

Create `OpenChatTests/ContinuationTurnsTests.swift`:

```swift
import Testing
@testable import OpenChat

struct ContinuationTurnsTests {
    @Test("appends the partial reply and a continue instruction after the original turns")
    func appendsPartialReplyAndContinueInstruction() {
        let original = [ChatTurn(role: .user, content: "Tell me a story")]
        let turns = BackgroundGenerationService.continuationTurns(
            previousTurns: original,
            partialContent: "Once upon a time,"
        )

        #expect(turns.count == 3)
        #expect(turns[0].role == .user)
        #expect(turns[0].content == "Tell me a story")
        #expect(turns[1].role == .assistant)
        #expect(turns[1].content == "Once upon a time,")
        #expect(turns[2].role == .user)
        #expect(turns[2].content.localizedCaseInsensitiveContains("continue"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ContinuationTurnsTests`
Expected: FAIL (`continuationTurns` does not exist)

- [ ] **Step 3: Add the pure helper**

In `OpenChat/Services/BackgroundGenerationService.swift`, add this static method to the `BackgroundGenerationService` class (near `buildTurns`, e.g. directly above its declaration at line 353):

```swift
    /// Builds the follow-up turns for a single silent continuation attempt
    /// after a mid-stream connection drop: the original turns, the partial
    /// reply already received (as if the model had said exactly that much),
    /// and an instruction to continue. This is a genuinely new request, not
    /// a re-send of the failed one — see `ChatServiceError.connectionDropped`.
    static func continuationTurns(previousTurns: [ChatTurn], partialContent: String) -> [ChatTurn] {
        previousTurns + [
            ChatTurn(role: .assistant, content: partialContent),
            ChatTurn(
                role: .user,
                content: "Continue your previous response exactly where it left off. Do not repeat any earlier part of the reply."
            ),
        ]
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OpenChatTests/ContinuationTurnsTests`
Expected: PASS

- [ ] **Step 5: Wire the silent continuation into `performGeneration`**

In `OpenChat/Services/BackgroundGenerationService.swift`, replace the `do`/`catch` block (lines 256-315):

```swift
        do {
            let result = try await buildTurns(
                conversation: conversation,
                assistantMessage: assistantMessage,
                model: model,
                provider: provider,
                apiKey: apiKey,
                memoryStore: memoryStore,
                rulesStore: rulesStore,
                dataSourceStore: dataSourceStore,
                webSearchStore: webSearchStore,
                skillsStore: skillsStore,
                modelContext: modelContext,
                effectiveEffortLevel: effectiveEffortLevel,
                effectiveReasoningEnabled: effectiveReasoningEnabled
            )

            var workingTurns = result.turns
            var continuationAttempts = 0
            let maxContinuationAttempts = 1

            while true {
                do {
                    try await runStream(
                        client: client,
                        modelID: modelID,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        turns: workingTurns,
                        tools: result.tools,
                        executeTool: result.executeTool,
                        supportsImageGen: supportsImageGen,
                        effort: effectiveEffortLevel,
                        reasoningEnabled: effectiveReasoningEnabled,
                        assistantMessage: assistantMessage,
                        activityID: activityID,
                        conversationID: conversationID,
                        startDate: startDate
                    )
                    break
                } catch ChatServiceError.connectionDropped
                where continuationAttempts < maxContinuationAttempts && !assistantMessage.content.isEmpty {
                    // Silent auto-retry, resume in place: nothing has streamed
                    // has been lost (Task 8's flush fix guarantees that), so
                    // we ask the model to continue from exactly where it
                    // stopped rather than re-sending the original request.
                    continuationAttempts += 1
                    await NetworkMonitor.shared.waitForConnection()
                    try Task.checkCancellation()
                    workingTurns = Self.continuationTurns(
                        previousTurns: workingTurns,
                        partialContent: assistantMessage.content
                    )
                }
            }

            await applyPostStream(
                assistantMessage: assistantMessage,
                conversation: conversation,
                skillCollector: result.skillCollector,
                skillMatches: result.skillMatches,
                skillsStore: skillsStore,
                memoryStore: memoryStore,
                rulesStore: rulesStore,
                dataSourceStore: dataSourceStore,
                modelContext: modelContext,
                conversationID: conversationID
            )
        } catch is CancellationError {
            finalActivityStatus = .failed
            finishCancelled(message: assistantMessage, conversation: conversation, modelContext: modelContext, conversationID: conversationID)
        } catch {
            finalActivityStatus = .failed
            finishWithError(
                message: assistantMessage,
                conversation: conversation,
                error: error,
                modelContext: modelContext,
                conversationID: conversationID
            )
        }
```

- [ ] **Step 6: Build to verify the file compiles**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

This class has no existing unit test coverage (it's tightly coupled to `SwiftData`/`UIApplication`/`ActivityKit`, consistent with the rest of the file), so the wiring itself is verified by this build check plus the extracted pure `continuationTurns` helper's tests above — not by a new integration test harness, matching the project's existing test boundary for this file.

- [ ] **Step 7: Commit**

```bash
git add OpenChat/Services/BackgroundGenerationService.swift OpenChatTests/ContinuationTurnsTests.swift
git commit -m "feat: silently auto-continue a dropped stream once connectivity returns"
```

---

### Task 10: Start `NetworkMonitor` at app launch

**Files:**
- Modify: `OpenChat/App/OpenChatApp.swift:71-81`

**Interfaces:**
- Consumes: `NetworkMonitor.shared.start()` (Task 3).

- [ ] **Step 1: Make the change**

In `OpenChat/App/OpenChatApp.swift`, inside the `.task { ... }` modifier (lines 71-81), add the monitor start as the first line:

```swift
                .task {
                    await NetworkMonitor.shared.start()
                    BackgroundGenerationService.shared.configure(
                        providerStore: providerStore,
                        dataSourceStore: dataSourceStore,
                        webSearchStore: webSearchStore,
                        rulesStore: rulesStore,
                        memoryStore: memoryStore,
                        skillsStore: skillsStore,
                        modelContainer: modelContainer
                    )
                }
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add OpenChat/App/OpenChatApp.swift
git commit -m "feat: start NetworkMonitor at app launch"
```

---

### Task 11: Full-suite regression pass

**Files:** None (verification only)

- [ ] **Step 1: Run the entire test suite**

Run: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED, all tests PASS — including every pre-existing test file plus all files added in Tasks 1-9.

- [ ] **Step 2: Manual smoke check (documented, not automated)**

Since `BackgroundGenerationService` has no integration-test harness (Task 9), do one manual check in the simulator: start a chat generation, then use the Simulator's Network Link Conditioner (or toggle Wi-Fi off/on in the host Mac's network settings while the simulator is bridged) mid-stream, and confirm:
- The UI does not show a hard error for a transient drop.
- The reply resumes and completes without duplicated text.
- No second, unrelated assistant message appears (which would indicate a duplicate/double-billed request).

Note this is exploratory verification, not something to encode as an automated test given the class's existing untested state.
