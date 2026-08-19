import Testing
@testable import OpenChat

private actor FakePathMonitor: PathMonitoring {
    private var onUpdate: (@Sendable (Bool) async -> Void)?

    func start(onUpdate: @escaping @Sendable (Bool) async -> Void) async {
        self.onUpdate = onUpdate
    }

    func simulate(connected: Bool) async {
        await onUpdate?(connected)
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
