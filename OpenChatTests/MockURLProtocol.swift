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
