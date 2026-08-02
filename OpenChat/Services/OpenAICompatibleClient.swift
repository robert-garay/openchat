import Foundation

/// Speaks the OpenAI `/chat/completions` wire format, which is what the
/// overwhelming majority of hosted and self-hosted models use today:
/// OpenAI, DeepSeek, Qwen (DashScope compatible mode), Kimi/Moonshot,
/// Zhipu GLM, 01.AI Yi, OpenRouter, Google Gemini's OpenAI shim, and any
/// local Ollama / LM Studio / vLLM server.
struct OpenAICompatibleClient: ChatCompletionClient {
    private struct RequestBody: Encodable {
        var model: String
        var messages: [RequestMessage]
        var stream = true
    }

    private struct RequestMessage: Encodable {
        var role: String
        var content: String
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: String?
            }
            var delta: Delta?
        }
        var choices: [Choice]?
    }

    func streamReply(
        turns: [ChatTurn],
        model: String,
        baseURL: String,
        apiKey: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard var components = URLComponents(string: baseURL) else {
                continuation.finish(throwing: ChatServiceError.invalidURL)
                return
            }
            components.path += components.path.hasSuffix("/") ? "chat/completions" : "/chat/completions"
            guard let url = components.url else {
                continuation.finish(throwing: ChatServiceError.invalidURL)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let body = RequestBody(
                model: model,
                messages: turns.map { RequestMessage(role: $0.role.rawValue, content: $0.content) }
            )
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let upstream = ServerSentEventStream.dataPayloads(for: request, session: .shared)
            let task = Task {
                do {
                    for try await payload in upstream {
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { continue }
                        if let text = chunk.choices?.first?.delta?.content, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
