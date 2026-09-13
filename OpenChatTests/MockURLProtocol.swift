import Foundation

/// Serves queued canned responses (or errors) and counts how many requests were issued.
/// Stub queues are isolated per subclass so XCTest catalog helpers can run
/// beside Swift Testing suites that also stub `URLSession`.
// Instances are only ever touched by URLSession's loading machinery for a
// single request/response cycle; the `dropAfterBody` delayed-error path below
// hands `self` to a background timer that outlives that synchronous cycle.
class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub {
        let body: Data?
        let contentType: String?
        let error: Error?
        var dropAfterBody: Bool = false
    }

    private struct Store {
        var stubs: [Stub] = []
        var count = 0
        var capturedRequestBody: Data?
        var capturedRequest: URLRequest?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stores: [ObjectIdentifier: Store] = [:]

    private class var storeKey: ObjectIdentifier { ObjectIdentifier(self) }

    private class func mutate(_ body: (inout Store) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var store = stores[storeKey] ?? Store()
        body(&store)
        stores[storeKey] = store
    }

    class func reset() {
        lock.lock()
        defer { lock.unlock() }
        stores[storeKey] = Store()
    }

    class var lastRequestBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return stores[storeKey]?.capturedRequestBody
    }

    class var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return stores[storeKey]?.capturedRequest
    }

    class func enqueue(sse: String) {
        mutate { store in
            store.stubs.append(Stub(body: Data(sse.utf8), contentType: "text/event-stream", error: nil))
        }
    }

    class func enqueue(json: String) {
        mutate { store in
            store.stubs.append(Stub(body: Data(json.utf8), contentType: "application/json", error: nil))
        }
    }

    /// Queues a request failure. Use this to simulate transient network errors
    /// (e.g. `URLError(.networkConnectionLost)`) for retry tests.
    class func enqueue(error: Error) {
        mutate { store in
            store.stubs.append(Stub(body: nil, contentType: nil, error: error))
        }
    }

    /// Queues a response that starts successfully (delivers `sse` as SSE
    /// body bytes) and then fails mid-body with `error` — simulating a
    /// connection that drops partway through an in-progress stream, as
    /// opposed to `enqueue(error:)` which fails before any bytes arrive.
    class func enqueue(sseBeforeDrop sse: String, thenFailWith error: Error) {
        mutate { store in
            store.stubs.append(
                Stub(body: Data(sse.utf8), contentType: "text/event-stream", error: error, dropAfterBody: true)
            )
        }
    }

    class var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stores[storeKey]?.count ?? 0
    }

    private class func next() -> Stub? {
        var stub: Stub?
        mutate { store in
            store.count += 1
            if !store.stubs.isEmpty {
                stub = store.stubs.removeFirst()
            }
        }
        return stub
    }

    private class func capture(_ request: URLRequest) {
        let body = request.httpBody ?? request.httpBodyStream.flatMap {
            $0.readToEnd(maxLength: 10_000_000)
        }
        mutate { store in
            store.capturedRequest = request
            store.capturedRequestBody = body
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let protocolType = type(of: self)
        protocolType.capture(request)
        guard let stub = protocolType.next() else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        if let error = stub.error {
            if stub.dropAfterBody, let body = stub.body {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": stub.contentType ?? "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                // `bytes.lines` consumes loaded data asynchronously; failing on the
                // same run-loop turn as the load can lose the race and drop the
                // buffered line before the consumer reads it. A short delay lets
                // the stream actually deliver "hello" before the drop.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self else { return }
                    self.client?.urlProtocol(self, didFailWithError: error)
                }
                return
            }
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

/// Isolated stub queue for ProviderStore catalog fetches so they cannot
/// consume `MockURLProtocol` stubs used by Swift Testing network suites.
final class CatalogMockURLProtocol: MockURLProtocol {}

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
