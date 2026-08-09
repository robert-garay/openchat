import Foundation

enum GoogleAPIError: Error, Equatable {
    case missingAccessToken
    case invalidResponse
    case httpError(Int, String)
}

/// Shared helper for authenticated Google API requests.
enum GoogleAPIClient {
    /// Perform an authenticated GET request and decode the response.
    static func get<T: Decodable & Sendable>(
        _ url: URL,
        for accountID: UUID,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let request = try await authenticatedRequest(url: url, for: accountID)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(data: data, response: response)
        return try decoder.decode(T.self, from: data)
    }

    /// Perform an authenticated GET request and return raw data.
    static func getData(
        _ url: URL,
        for accountID: UUID
    ) async throws -> Data {
        let request = try await authenticatedRequest(url: url, for: accountID)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(data: data, response: response)
        return data
    }

    private static func authenticatedRequest(url: URL, for accountID: UUID) async throws -> URLRequest {
        let token = try await GoogleAuthService.shared.validAccessToken(for: accountID)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func checkResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAPIError.httpError(httpResponse.statusCode, message)
        }
    }
}
