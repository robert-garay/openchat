import Foundation
import Observation

/// Observable mirror of `NetworkMonitor.shared.isConnected` for SwiftUI.
@MainActor
@Observable
final class NetworkConnectivityStore {
    var isConnected = true

    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .networkConnectivityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let isConnected = notification.userInfo?["isConnected"] as? Bool else { return }
            Task { @MainActor in
                self?.isConnected = isConnected
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() async {
        isConnected = await NetworkMonitor.shared.isConnected
    }
}
