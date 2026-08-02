import SwiftUI

struct MessageComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($isFocused)
                .onSubmit(submitIfPossible)

            Button(action: primaryAction) {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, primaryButtonColor)
            }
            .disabled(!isStreaming && !canSend)
            .animation(Theme.springFast, value: canSend)
            .animation(Theme.springFast, value: isStreaming)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var primaryButtonColor: Color {
        if isStreaming { return .red }
        return canSend ? .accentColor : Color(.tertiaryLabel)
    }

    private func primaryAction() {
        if isStreaming {
            Haptics.medium()
            onStop()
        } else {
            submitIfPossible()
        }
    }

    private func submitIfPossible() {
        guard canSend else { return }
        Haptics.light()
        onSend()
    }
}
