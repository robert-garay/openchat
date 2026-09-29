import Foundation

#if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

actor LocalMLXRuntime {
    static let shared = LocalMLXRuntime()

    private var loadedModelID: String?
    #if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
    private var container: ModelContainer?
    #endif

    func unload() {
        loadedModelID = nil
        #if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
        container = nil
        #endif
    }

    func unloadIfLoaded(modelID: String) {
        if loadedModelID == modelID {
            unload()
        }
    }

    #if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
    func modelContainer(modelID: String, directory: URL) async throws -> ModelContainer {
        if loadedModelID == modelID, let container {
            return container
        }
        let loaded = try await loadModelContainer(
            from: directory,
            using: #huggingFaceTokenizerLoader()
        )
        container = loaded
        loadedModelID = modelID
        return loaded
    }
    #endif
}
