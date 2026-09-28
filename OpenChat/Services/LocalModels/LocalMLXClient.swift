import Foundation

#if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
import MLXLLM
import MLXLMCommon
#endif

final class LocalMLXClient: ChatCompletionClient, @unchecked Sendable {
    static let shared = LocalMLXClient()

    private let installStore = LocalModelInstallStore()

    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?,
        tools: [ChatToolDefinition],
        executeTool: @escaping @Sendable (ChatToolCall) async throws -> String,
        supportsImageGen: Bool,
        effort: EffortLevel?,
        reasoningEnabled: Bool?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    #if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
                    guard tools.isEmpty else {
                        throw ChatServiceError.decoding("Tools are not supported for on-device models in v1.")
                    }
                    if turns.contains(where: { $0.hasImages || $0.hasDocuments }) {
                        throw LocalModelsError.unsupportedAttachment
                    }

                    let manifest = try LocalModelsManifestLoader.loadBundled()
                    guard let entry = LocalModelsManifestLoader.entry(mlxModelID: model, in: manifest) else {
                        throw ChatServiceError.providerOrModelNotFound
                    }

                    let records = installStore.load()
                    guard records[entry.id]?.state == .ready else {
                        throw LocalModelsError.modelNotReady
                    }

                    let directory = installStore.modelDirectory(for: entry.id)
                    let container = try await LocalMLXRuntime.shared.modelContainer(
                        modelID: entry.id,
                        directory: directory
                    )

                    let (instructions, prompt) = Self.promptParts(from: turns)
                    let session = ChatSession(
                        container,
                        instructions: instructions,
                        generateParameters: GenerateParameters(maxTokens: 512, temperature: 0.7)
                    )

                    var previous = ""
                    for try await chunk in session.streamResponse(to: prompt) {
                        let delta = Self.delta(previous: previous, new: chunk)
                        previous = chunk
                        if !delta.isEmpty {
                            continuation.yield(.text(delta))
                        }
                    }
                    continuation.finish()
                    #else
                    continuation.finish(throwing: ChatServiceError.localInferenceUnavailable)
                    #endif
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    #if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
    private static func promptParts(from turns: [ChatTurn]) -> (instructions: String?, prompt: String) {
        let systemTexts = turns.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let dialogue = turns.filter { $0.role != .system }
        guard let lastUserIndex = dialogue.lastIndex(where: { $0.role == .user }) else {
            return (systemTexts.isEmpty ? nil : systemTexts, "")
        }
        let history = dialogue.prefix(upTo: lastUserIndex)
        let lastUser = dialogue[lastUserIndex]
        var prompt = ""
        for turn in history {
            switch turn.role {
            case .user:
                prompt += "User: \(turn.content)\n"
            case .assistant:
                prompt += "Assistant: \(turn.content)\n"
            case .system, .tool:
                break
            }
        }
        prompt += "User: \(lastUser.content)\nAssistant:"
        let instructions = systemTexts.isEmpty ? nil : systemTexts
        return (instructions, prompt)
    }

    private static func delta(previous: String, new: String) -> String {
        if new.hasPrefix(previous) {
            return String(new.dropFirst(previous.count))
        }
        return new
    }
    #endif
}
