import SwiftUI

struct RulesSettingsView: View {
    @Environment(RulesStore.self) private var rulesStore

    var body: some View {
        @Bindable var rulesStore = rulesStore

        VStack(spacing: 0) {
            TextEditor(text: $rulesStore.globalRules)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Text("These instructions steer how the assistant behaves in every chat. Per-chat rules and skills can override them when set.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.contentPadding)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
    }
}
