import Foundation

/// Fetches a provider's live model catalog via `GET {baseURL}/models`.
struct ProviderModelsClient: Sendable {
    var session: URLSession = .shared

    func fetchModels(
        for provider: ConfiguredProvider,
        apiKey: String?
    ) async throws -> [AIModel] {
        switch provider.apiFormat {
        case .openAI:
            return try await fetchOpenAICompatible(baseURL: provider.baseURL, apiKey: apiKey)
        case .anthropic:
            return try await fetchAnthropic(baseURL: provider.baseURL, apiKey: apiKey)
        }
    }

    // MARK: - OpenAI-compatible

    func fetchOpenAICompatible(baseURL: String, apiKey: String?) async throws -> [AIModel] {
        let request = try Self.makeRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            format: .openAI
        )
        let data = try await perform(request)
        return try Self.decodeOpenAIModels(from: data)
    }

    static func decodeOpenAIModels(from data: Data) throws -> [AIModel] {
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data
            .filter { isLikelyChatModelID($0.id) }
            .map { remote in
                // Empty modalities/parameters mean "unknown" so identity heuristics can fill gaps.
                // Providers that include architecture metadata (e.g. some OpenRouter-compatible
                // proxies) are trusted over name matching.
                AIModel(
                    id: remote.id,
                    displayName: remote.id,
                    capabilities: ModelCapability.inferred(
                        inputModalities: remote.architecture?.input_modalities ?? [],
                        outputModalities: remote.architecture?.output_modalities ?? [],
                        supportedParameters: remote.supported_parameters ?? [],
                        modelID: remote.id,
                        modelName: remote.id
                    )
                )
            }
    }

    // MARK: - Anthropic

    func fetchAnthropic(baseURL: String, apiKey: String?) async throws -> [AIModel] {
        var models: [AIModel] = []
        var afterID: String?

        repeat {
            var request = try Self.makeRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                format: .anthropic
            )
            if var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
                var items = components.queryItems ?? []
                items.append(URLQueryItem(name: "limit", value: "1000"))
                if let afterID {
                    items.append(URLQueryItem(name: "after_id", value: afterID))
                }
                components.queryItems = items
                request.url = components.url
            }

            let data = try await perform(request)
            let page = try Self.decodeAnthropicModels(from: data)
            models.append(contentsOf: page.models)
            afterID = page.hasMore ? page.lastID : nil
        } while afterID != nil

        return models
    }

    static func decodeAnthropicModels(from data: Data) throws -> AnthropicModelsPage {
        let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        let models = decoded.data.map { remote -> AIModel in
            var caps = Set<ModelCapability>()
            if remote.capabilities?.image_input?.supported == true {
                caps.insert(.vision)
            }
            if remote.capabilities?.pdf_input?.supported == true {
                caps.insert(.files)
            }
            if remote.capabilities?.thinking?.supported == true {
                caps.insert(.reasoning)
            }
            // Anthropic Messages API models support tools.
            caps.insert(.tools)

            // Fill gaps when the API omits the capabilities object (older responses).
            let inferred = ModelCapability.inferred(
                inputModalities: [],
                outputModalities: [],
                modelID: remote.id,
                modelName: remote.display_name ?? remote.id
            )
            caps.formUnion(inferred)

            var subtitle: String?
            if let tokens = remote.max_input_tokens, tokens > 0 {
                subtitle = Self.formatContext(tokens)
            }

            return AIModel(
                id: remote.id,
                displayName: remote.display_name ?? remote.id,
                subtitle: subtitle,
                capabilities: ModelCapability.sorted(caps)
            )
        }
        return AnthropicModelsPage(
            models: models,
            hasMore: decoded.has_more ?? false,
            lastID: decoded.last_id
        )
    }

    /// Prefer template display names/subtitles; union capabilities from live + defaults.
    static func enrich(_ models: [AIModel], using defaults: [AIModel]) -> [AIModel] {
        let known = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        return models.map { model in
            guard let match = known[model.id] else { return model }
            return AIModel(
                id: model.id,
                displayName: match.displayName,
                subtitle: match.subtitle ?? model.subtitle,
                capabilities: ModelCapability.sorted(Set(model.capabilities).union(match.capabilities))
            )
        }
    }

    // MARK: - Shared helpers

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderModelsError.http(status: http.statusCode, body: body)
        }
        return data
    }

    private static func makeRequest(
        baseURL: String,
        apiKey: String?,
        format: APIFormat
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw ProviderModelsError.invalidURL
        }
        components.path += components.path.hasSuffix("/") ? "models" : "/models"
        guard let url = components.url else {
            throw ProviderModelsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch format {
        case .openAI:
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let apiKey, !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
        }

        return request
    }

    /// Drops obvious non-chat OpenAI catalog entries (embeddings, audio, images, etc.).
    static func isLikelyChatModelID(_ id: String) -> Bool {
        let lowered = id.lowercased()
        let blocked = [
            "whisper", "tts", "dall-e", "dalle", "embedding", "moderation",
            "realtime", "transcribe", "sora", "text-embedding", "text-moderation",
            "babbage", "davinci", "curie", "ada-00", "gpt-image", "codex-mini-latest"
        ]
        return !blocked.contains { lowered.contains($0) }
    }

    private static func formatContext(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            return String(format: millions.rounded() == millions ? "%.0fM context" : "%.1fM context", millions)
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K context"
        }
        return "\(tokens) context"
    }
}

enum ProviderModelsError: LocalizedError {
    case invalidURL
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The provider's base URL is invalid."
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Models request failed (\(status))."
            }
            return "Models request failed (\(status)): \(trimmed)"
        }
    }
}

struct AnthropicModelsPage: Sendable {
    var models: [AIModel]
    var hasMore: Bool
    var lastID: String?
}

// MARK: - Wire formats

private struct OpenAIModelsResponse: Decodable {
    var data: [OpenAIRemoteModel]
}

private struct OpenAIRemoteModel: Decodable {
    var id: String
    var architecture: OpenAIRemoteArchitecture?
    var supported_parameters: [String]?
}

private struct OpenAIRemoteArchitecture: Decodable {
    var input_modalities: [String]?
    var output_modalities: [String]?
}

private struct AnthropicModelsResponse: Decodable {
    var data: [AnthropicRemoteModel]
    var has_more: Bool?
    var last_id: String?
}

private struct AnthropicRemoteModel: Decodable {
    var id: String
    var display_name: String?
    var max_input_tokens: Int?
    var capabilities: AnthropicRemoteCapabilities?
}

private struct AnthropicRemoteCapabilities: Decodable {
    var image_input: AnthropicCapabilityFlag?
    var pdf_input: AnthropicCapabilityFlag?
    var thinking: AnthropicCapabilityFlag?
}

private struct AnthropicCapabilityFlag: Decodable {
    var supported: Bool?
}
