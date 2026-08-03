import Foundation

/// Fetches OpenRouter's public model catalog (`GET /api/v1/models`).
struct OpenRouterModelsClient: Sendable {
    var session: URLSession = .shared
    var endpoint: URL = URL(string: "https://openrouter.ai/api/v1/models")!

    func fetchModels() async throws -> [OpenRouterCatalogModel] {
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenRouterModelsError.httpStatus(http.statusCode)
        }

        return try Self.decodeModels(from: data)
    }

    static func decodeModels(from data: Data) throws -> [OpenRouterCatalogModel] {
        let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return decoded.data.map(\.asCatalogModel)
    }
}

enum OpenRouterModelsError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "OpenRouter models request failed (\(code))."
        }
    }
}

private struct OpenRouterModelsResponse: Decodable {
    var data: [RemoteModel]
}

private struct RemoteModel: Decodable {
    var id: String
    var name: String
    var created: Int?
    var context_length: Int?
    var hugging_face_id: String?
    var pricing: Pricing?
    var architecture: Architecture?
    var supported_parameters: [String]?
    var alias_target: AliasTarget?

    struct Pricing: Decodable {
        var prompt: String?
        var completion: String?
    }

    struct Architecture: Decodable {
        var modality: String?
        var input_modalities: [String]?
        var output_modalities: [String]?
    }

    struct AliasTarget: Decodable {}

    var asCatalogModel: OpenRouterCatalogModel {
        OpenRouterCatalogModel(
            id: id,
            name: name,
            created: created,
            contextLength: context_length,
            huggingFaceID: hugging_face_id,
            promptPrice: Double(pricing?.prompt ?? "0") ?? 0,
            completionPrice: Double(pricing?.completion ?? "0") ?? 0,
            modality: architecture?.modality,
            inputModalities: architecture?.input_modalities ?? [],
            outputModalities: architecture?.output_modalities ?? [],
            supportedParameters: supported_parameters ?? [],
            isAlias: alias_target != nil || id.hasPrefix("~")
        )
    }
}
