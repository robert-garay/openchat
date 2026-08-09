import XCTest
@testable import OpenChat

final class ProviderBalanceClientTests: XCTestCase {
    func testSupportsBalanceForKnownProviders() {
        XCTAssertTrue(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "deepseek")!)))
        XCTAssertTrue(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "moonshot")!)))
    }

    func testSupportsBalanceFalseForOthers() {
        XCTAssertFalse(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "openai")!)))
        XCTAssertFalse(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "anthropic")!)))
        XCTAssertFalse(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "openrouter")!)))

        let custom = ConfiguredProvider.customEndpoint(
            name: "Local",
            baseURL: "http://localhost:11434/v1",
            models: [],
            requiresAPIKey: false
        )
        XCTAssertFalse(ProviderBalanceClient.supportsBalance(for: custom))
    }

    func testDecodeDeepSeekBalance() throws {
        let json = Data("""
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """.utf8)

        let balance = try ProviderBalanceClient.decodeDeepSeekBalance(from: json)
        XCTAssertEqual(balance.total, 110.0)
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertEqual(balance.isSufficient, true)
        XCTAssertEqual(balance.breakdown?.count, 1)
        XCTAssertEqual(balance.breakdown?[0].total, 110.0)
        XCTAssertEqual(balance.breakdown?[0].currency, "CNY")
    }

    func testDecodeDeepSeekBalancePreservesMultipleEntries() throws {
        let json = Data("""
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "100.00"
            },
            {
              "currency": "USD",
              "total_balance": "15.50"
            }
          ]
        }
        """.utf8)

        let balance = try ProviderBalanceClient.decodeDeepSeekBalance(from: json)
        XCTAssertEqual(balance.total, 100.0)
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertEqual(balance.breakdown?.count, 2)
        XCTAssertEqual(balance.breakdown?[0].currency, "CNY")
        XCTAssertEqual(balance.breakdown?[0].total, 100.0)
        XCTAssertEqual(balance.breakdown?[1].currency, "USD")
        XCTAssertEqual(balance.breakdown?[1].total, 15.5)
    }

    func testDecodeDeepSeekBalanceThrowsWhenBalanceInfosMissing() {
        let json = Data("""
        {
          "is_available": true,
          "balance_infos": []
        }
        """.utf8)

        XCTAssertThrowsError(try ProviderBalanceClient.decodeDeepSeekBalance(from: json)) { error in
            XCTAssertEqual(error as? ProviderBalanceClient.BalanceError, .invalidResponse)
        }
    }

    func testDecodeDeepSeekBalanceThrowsWhenTotalBalanceIsNonnumeric() {
        let json = Data("""
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "not-a-number"
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try ProviderBalanceClient.decodeDeepSeekBalance(from: json)) { error in
            XCTAssertEqual(error as? ProviderBalanceClient.BalanceError, .invalidResponse)
        }
    }

    func testDecodeDeepSeekBalanceThrowsWhenTotalBalanceMissing() {
        let json = Data("""
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY"
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try ProviderBalanceClient.decodeDeepSeekBalance(from: json)) { error in
            XCTAssertEqual(error as? ProviderBalanceClient.BalanceError, .invalidResponse)
        }
    }

    func testDecodeDeepSeekBalancePropagatesMalformedJSON() {
        let json = Data("""
        {
          "is_available": true,
          "balance_infos": [
        """.utf8)

        XCTAssertThrowsError(try ProviderBalanceClient.decodeDeepSeekBalance(from: json)) { error in
            XCTAssertFalse(error is ProviderBalanceClient.BalanceError)
        }
    }

    func testDecodeMoonshotBalance() throws {
        let json = Data("""
        {
          "code": 0,
          "data": {
            "available_balance": 49.58894,
            "voucher_balance": 46.58893,
            "cash_balance": 3.00001
          },
          "scode": "0x0",
          "status": true
        }
        """.utf8)

        let balance = try ProviderBalanceClient.decodeMoonshotBalance(from: json)
        XCTAssertEqual(balance.total, 49.58894, accuracy: 0.00001)
        XCTAssertEqual(balance.currency, "CNY")
        XCTAssertEqual(balance.isSufficient, true)
        XCTAssertNil(balance.breakdown)
    }
}
