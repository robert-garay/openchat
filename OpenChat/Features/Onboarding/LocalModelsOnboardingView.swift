import SwiftUI

enum LocalModelsOnboardingSettings {
    static let interestKey = "com.openchat.localModelsInterest"
    static let manifestDocsURL = URL(string: "https://github.com/robert-garay/openchat/blob/main/docs/local-models-plan.md")!
}

/// First-launch sheet explaining on-device open models (download + MLX) before runtime ships.
struct LocalModelsOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LocalModelsOnboardingSettings.interestKey) private var isInterested = false

    private let bullets: [(icon: String, text: String)] = [
        ("iphone.gen3", "Runs entirely on your iPhone after download — no API key and no chat traffic to OpenChat."),
        ("arrow.down.circle", "Models come from a curated, checksum-verified catalog (starting with small quantized Llama, Qwen, and Phi checkpoints)."),
        ("externaldrive", "Each model uses roughly 1–2 GB of storage; Apple Silicon with 6–8 GB RAM or more is recommended."),
        ("wifi", "Downloads use your network connection; Wi‑Fi is recommended for large files."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Coming soon")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("OpenChat is adding optional on-device inference with MLX. You will pick a model, download it once, and chat offline like any other provider.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("What to expect") {
                    ForEach(bullets, id: \.text) { item in
                        Label {
                            Text(item.text)
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: item.icon)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                Section {
                    Toggle("Remind me when downloads are available", isOn: $isInterested)
                    Link(destination: LocalModelsOnboardingSettings.manifestDocsURL) {
                        Label("Trusted model catalog plan", systemImage: "doc.text")
                    }
                } footer: {
                    Text("Already running Ollama or LM Studio on your network? Use Connect a Provider → Custom Endpoint.")
                        .font(.footnote)
                }
            }
            .navigationTitle("On-Device Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
