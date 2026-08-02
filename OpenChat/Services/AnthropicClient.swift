import Foundation

/// Speaks Anthropic's native `/messages` streaming format for Claude models.
struct AnthropicClient: ChatCompletionClient {
    private struct RequestBody: Encodable {
        var model: String
        var maxTokens: Int
        var system: String?
        var messages: [RequestMessage]
        var stream = true

        enum CodingKeys: String, CodingKey {
            case model, system, messages, stream
            case maxTokens = "max_tokens"
        }
    }

    private struct RequestMessage: Encodable {
        var role: String
        var content: String
    }

    private struct StreamEvent: Decodable {
        struct Delta: Decodable {
            var type: String?
            var text: String?
        }
        var type: String
        var delta: Delta?
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
            components.path += components.path.hasSuffix("/") ? "messages" : "/messages"
            guard let url = components.url else {
                continuation.finish(throwing: ChatServiceError.invalidURL)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let apiKey, !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            }

            let systemPrompt = turns.first(where: { $0.role == .system })?.content
            let conversationTurns = turns.filter { $0.role != .system }

            let body = RequestBody(
                model: model,
                maxTokens: 8192,
                system: (systemPrompt?.isEmpty ?? true) ? nil : systemPrompt,
                messages: conversationTurns.map { RequestMessage(role: $0.role.rawValue, content: $0.content) }
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
                        guard let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }
                        if event.type == "content_block_delta",
                           event.delta?.type == "text_delta",
                           let text = event.delta?.text, !text.isEmpty {
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
