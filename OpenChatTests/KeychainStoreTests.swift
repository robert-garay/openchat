import XCTest
@testable import OpenChat

final class KeychainStoreTests: XCTestCase {
    private let testKey = "com.openchat.tests.keychain-round-trip"

    override func setUp() {
        super.setUp()
        KeychainStore.service = "com.openchat.apikeys.tests.\(UUID().uuidString)"
        KeychainStore.removeAll()
    }

    override func tearDown() {
        KeychainStore.remove(testKey)
        KeychainStore.removeAll()
        super.tearDown()
    }

    func testSetAndGetRoundTrips() {
        KeychainStore.set("sk-test-12345", forKey: testKey)
        XCTAssertEqual(KeychainStore.get(testKey), "sk-test-12345")
    }

    func testUpdateOverwritesExistingValue() {
        KeychainStore.set("first-value", forKey: testKey)
        KeychainStore.set("second-value", forKey: testKey)
        XCTAssertEqual(KeychainStore.get(testKey), "second-value")
    }

    func testRemoveDeletesValue() {
        KeychainStore.set("to-be-removed", forKey: testKey)
        KeychainStore.remove(testKey)
        XCTAssertNil(KeychainStore.get(testKey))
    }

    func testGetReturnsNilForMissingKey() {
        XCTAssertNil(KeychainStore.get("com.openchat.tests.does-not-exist"))
    }
}
