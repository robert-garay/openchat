import SwiftUI

/// Collapsible block that shows a model's chain-of-thought above the answer.
struct ThinkingDisclosureView: View {
    let reasoning: String
    let isStreaming: Bool
    let answerStarted: Bool

    @State private var isExpanded: Bool

    init(reasoning: String, isStreaming: Bool, answerStarted: Bool) {
        self.reasoning = reasoning
        self.isStreaming = isStreaming
        self.answerStarted = answerStarted
        // Expand while the model is still thinking (no answer yet); collapse once the answer lands.
        _isExpanded = State(initialValue: isStreaming && !answerStarted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Theme.springFast) {
                    isExpanded.toggle()
                }
                Haptics.light()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption.weight(.semibold))
                    Text(headerTitle)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    if isStreaming && !answerStarted {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.leading, 2)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headerTitle)
            .accessibilityHint(isExpanded ? "Collapse thinking" : "Expand thinking")

            if isExpanded {
                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: answerStarted) { _, started in
            if started, isStreaming {
                withAnimation(Theme.springFast) {
                    isExpanded = false
                }
            }
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming, answerStarted {
                withAnimation(Theme.springFast) {
                    isExpanded = false
                }
            }
        }
    }

    private var headerTitle: String {
        if isStreaming && !answerStarted {
            return "Thinking"
        }
        return "Thought process"
    }
}
