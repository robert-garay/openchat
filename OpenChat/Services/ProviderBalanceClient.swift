import Foundation

/// Fetches account credit / balance information for providers that expose it.
struct ProviderBalanceClient: Sendable {
    var session: URLSession = .shared

    /// Describes a provider account balance in a currency-agnostic way.
    struct Balance: Sendable {
        var total: Double
        var currency: String
        /// Whether the provider reports the balance as sufficient for API calls.
        var isSufficient: Bool?
        /// Per-currency breakdown when the provider reports more than one balance.
        var breakdown: [BalanceEntry]?
    }

    /// A single per-currency balance entry.
    struct BalanceEntry: Sendable {
        var currency: String
        var total: Double
    }

    enum BalanceError: Error {
        case unsupportedProvider
        case missingAPIKey
        case invalidResponse
    }

    /// Returns whether the given provider exposes a balance endpoint.
    static func supportsBalance(for provider: ConfiguredProvider) -> Bool {
        switch provider.id {
        case "deepseek", "moonshot":
            return true
        default:
            return false
        }
    }

    /// Fetches the current balance for the provider, if supported.
    func fetchBalance(for provider: ConfiguredProvider, apiKey: String?) async throws -> Balance {
        guard Self.supportsBalance(for: provider) else {
            throw BalanceError.unsupportedProvider
        }
        guard let apiKey, !apiKey.isEmpty else {
            throw BalanceError.missingAPIKey
        }

        switch provider.id {
        case "deepseek":
            return try await fetchDeepSeek(apiKey: apiKey)
        case "moonshot":
            return try await fetchMoonshot(apiKey: apiKey)
        default:
            throw BalanceError.unsupportedProvider
        }
    }

    // MARK: - DeepSeek

    private func fetchDeepSeek(apiKey: String) async throws -> Balance {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request)
        return try Self.decodeDeepSeekBalance(from: data)
    }

    static func decodeDeepSeekBalance(from data: Data) throws -> Balance {
        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)

        guard !decoded.balance_infos.isEmpty else {
            throw BalanceError.invalidResponse
        }

        let entries = try decoded.balance_infos.map { info -> BalanceEntry in
            guard let totalBalance = info.total_balance, let total = Double(totalBalance) else {
                throw BalanceError.invalidResponse
            }
            return BalanceEntry(currency: info.currency, total: total)
        }

        let first = entries[0]
        return Balance(
            total: first.total,
            currency: first.currency,
            isSufficient: decoded.is_available,
            breakdown: entries
        )
    }

    struct DeepSeekBalanceResponse: Decodable {
        var is_available: Bool
        var balance_infos: [DeepSeekBalanceInfo]
    }

    struct DeepSeekBalanceInfo: Decodable {
        var currency: String
        var total_balance: String?
    }

    // MARK: - Moonshot

    private func fetchMoonshot(apiKey: String) async throws -> Balance {
        var request = URLRequest(url: URL(string: "https://api.moonshot.cn/v1/users/me/balance")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request)
        return try Self.decodeMoonshotBalance(from: data)
    }

    static func decodeMoonshotBalance(from data: Data) throws -> Balance {
        let decoded = try JSONDecoder().decode(MoonshotBalanceResponse.self, from: data)

        return Balance(
            total: decoded.data.available_balance,
            currency: "CNY",
            isSufficient: decoded.data.available_balance > 0
        )
    }

    struct MoonshotBalanceResponse: Decodable {
        var data: MoonshotBalanceData
    }

    struct MoonshotBalanceData: Decodable {
        var available_balance: Double
    }

    // MARK: - Shared

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BalanceError.invalidResponse
        }
        return data
    }
}

extension ProviderBalanceClient.BalanceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "This provider does not expose a balance API."
        case .missingAPIKey:
            return "No API key is configured for this provider."
        case .invalidResponse:
            return "The balance response was invalid or the request failed."
        }
    }
}
