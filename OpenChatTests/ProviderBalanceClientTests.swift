import XCTest
@testable import OpenChat

final class ProviderBalanceClientTests: XCTestCase {
    func testSupportsBalanceForKnownProviders() {
        XCTAssertTrue(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "deepseek")!)))
        XCTAssertTrue(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "moonshot")!)))
        XCTAssertTrue(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "openrouter")!)))
    }

    func testSupportsBalanceFalseForOthers() {
        XCTAssertFalse(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "openai")!)))
        XCTAssertFalse(ProviderBalanceClient.supportsBalance(for: .fromTemplate(.template(for: "anthropic")!)))

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
    }

    func testDecodeOpenRouterBalance() throws {
        let json = Data("""
        {
          "data": {
            "total_credits": 100.5,
            "total_usage": 25.75
          }
        }
        """.utf8)

        let balance = try ProviderBalanceClient.decodeOpenRouterBalance(from: json)
        XCTAssertEqual(balance.total, 74.75, accuracy: 0.001)
        XCTAssertEqual(balance.currency, "USD")
        XCTAssertEqual(balance.isSufficient, true)
    }

    func testDecodeOpenRouterBalanceZeroWhenUsageExceedsCredits() throws {
        let json = Data("""
        {
          "data": {
            "total_credits": 10.0,
            "total_usage": 25.0
          }
        }
        """.utf8)

        let balance = try ProviderBalanceClient.decodeOpenRouterBalance(from: json)
        XCTAssertEqual(balance.total, 0)
        XCTAssertEqual(balance.isSufficient, false)
    }
}
