import Foundation

/// A background URLSession that can finish download and upload tasks while the app is suspended.
///
/// iOS terminates ordinary foreground `URLSession` data tasks when the app moves to the
/// background. This singleton uses a background-configured session so that web search and
/// other non-streaming network requests can continue (and finish) after the user leaves the app.
final class BackgroundNetworkSession: NSObject, @unchecked Sendable {
    static let shared = BackgroundNetworkSession()

    /// Completion handler passed to the app delegate when the system relaunches the app to
    /// deliver background URLSession events. The delegate must store the handler here so the
    /// session can call it after `urlSessionDidFinishEvents(forBackgroundURLSession:)` fires.
    nonisolated(unsafe) static var backgroundSessionCompletionHandler: (() -> Void)?

    private let continuations = ContinuationStore()
    private let queue = OperationQueue()

    private var session: URLSession!

    private override init() {
        super.init()
        queue.name = "com.openchat.background-network"
        queue.qualityOfService = .utility
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "com.openchat.background-network"
        )
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3_600
        session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: queue
        )
    }

    /// Performs a request that may continue while the app is backgrounded.
    /// GET/HEAD requests use a download task; POST/PUT/PATCH use an upload task from a
    /// temporary file so they can continue in the background.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let method = request.httpMethod?.uppercased() ?? "GET"
        if method == "GET" || method == "HEAD" {
            return try await download(for: request)
        } else {
            return try await upload(for: request)
        }
    }

    // MARK: - Private

    private func download(for request: URLRequest) async throws -> (Data, URLResponse) {
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request)
                continuations.set(
                    id: requestID,
                    continuation: continuation,
                    task: task
                )
                task.resume()
            }
        } onCancel: {
            continuations.cancel(id: requestID)
        }
    }

    private func upload(for request: URLRequest) async throws -> (Data, URLResponse) {
        let requestID = UUID()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tmp")
        // Always write a file (even an empty one) so uploadTask(with:fromFile:) has a
        // valid body file for bodyless requests such as DELETE.
        let body = request.httpBody ?? Data()
        try body.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // The upload task uses the file as the request body, so clear any in-memory body
        // to avoid duplicating it in the request.
        var uploadRequest = request
        uploadRequest.httpBody = nil
        uploadRequest.httpBodyStream = nil

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: uploadRequest, fromFile: tempURL)
                continuations.set(
                    id: requestID,
                    continuation: continuation,
                    task: task
                )
                task.resume()
            }
        } onCancel: {
            continuations.cancel(id: requestID)
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundNetworkSession: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let data = try Data(contentsOf: location)
            continuations.resume(
                task: downloadTask,
                with: data,
                response: downloadTask.response
            )
        } catch {
            continuations.resume(
                task: downloadTask,
                with: nil,
                response: downloadTask.response,
                error: error
            )
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundNetworkSession: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuations.resume(
                task: task,
                with: nil,
                response: task.response,
                error: error
            )
        } else {
            // For upload tasks, this is the completion signal; accumulated response data is
            // returned from the store. For downloads, the store is already empty.
            continuations.resume(
                task: task,
                with: nil,
                response: task.response
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // UIKit requires the background session completion handler to be called on the
        // main thread. Read and clear it atomically on the main queue.
        DispatchQueue.main.async {
            let handler = BackgroundNetworkSession.backgroundSessionCompletionHandler
            BackgroundNetworkSession.backgroundSessionCompletionHandler = nil
            handler?()
        }
    }
}

// MARK: - URLSessionDataDelegate

extension BackgroundNetworkSession: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        continuations.append(data: data, for: dataTask)
    }
}

// MARK: - ContinuationStore

/// Thread-safe storage for outstanding request continuations, keyed by URLSession task identifier.
///
/// The delegate queue and the calling tasks may access this store concurrently, so all reads
/// and writes are guarded by a lock. Each entry is removed when resumed, so a task can never
/// be resumed twice.
private final class ContinuationStore: @unchecked Sendable {
    private struct Entry {
        let id: UUID
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
        let task: URLSessionTask
        var data: Data = Data()
    }

    private var entries: [Int: Entry] = [:]
    private var idToTaskID: [UUID: Int] = [:]
    /// Request IDs that were cancelled before their continuation was registered.
    /// A later `set` for that ID immediately resumes with `CancellationError`.
    private var cancelledIDs: Set<UUID> = []
    private let lock = NSLock()

    func set(
        id: UUID,
        continuation: CheckedContinuation<(Data, URLResponse), Error>,
        task: URLSessionTask
    ) {
        lock.lock()
        if cancelledIDs.remove(id) != nil {
            lock.unlock()
            task.cancel()
            continuation.resume(throwing: CancellationError())
            return
        }
        entries[task.taskIdentifier] = Entry(
            id: id,
            continuation: continuation,
            task: task
        )
        idToTaskID[id] = task.taskIdentifier
        lock.unlock()
    }

    func append(data: Data, for task: URLSessionTask) {
        lock.lock()
        entries[task.taskIdentifier]?.data.append(data)
        lock.unlock()
    }

    func cancel(id: UUID) {
        lock.lock()
        let taskID = idToTaskID.removeValue(forKey: id)
        let entry = taskID.flatMap { entries.removeValue(forKey: $0) }
        if entry == nil {
            cancelledIDs.insert(id)
        }
        lock.unlock()
        guard let entry else { return }
        entry.task.cancel()
        entry.continuation.resume(throwing: CancellationError())
    }

    func resume(
        task: URLSessionTask,
        with data: Data?,
        response: URLResponse?,
        error: Error? = nil
    ) {
        lock.lock()
        let entry = entries.removeValue(forKey: task.taskIdentifier)
        if let entry {
            idToTaskID.removeValue(forKey: entry.id)
        }
        lock.unlock()
        guard let entry else { return }
        if let error {
            entry.continuation.resume(throwing: error)
        } else if let response {
            entry.continuation.resume(returning: (data ?? entry.data, response))
        } else {
            entry.continuation.resume(throwing: URLError(.unknown))
        }
    }
}

// MARK: - URLSession extension

extension URLSession {
    /// Returns data using the shared background-capable session for the app's production
    /// sessions (`URLSession.shared` and `ChatService.urlSession`), while preserving the
    /// ability to inject mock sessions in tests.
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
