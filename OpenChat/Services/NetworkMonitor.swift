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
