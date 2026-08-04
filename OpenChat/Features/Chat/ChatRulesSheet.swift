import SwiftUI
import SwiftData

struct ChatRulesSheet: View {
    @Bindable var conversation: Conversation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $conversation.systemPrompt)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                Group {
                    if conversation.isTemporary {
                        Text("Rules apply to this session only and won\'t persist after you leave this chat.")
                    } else {
                        Text("These instructions apply only to this conversation and override global rules when they conflict.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Chat Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
