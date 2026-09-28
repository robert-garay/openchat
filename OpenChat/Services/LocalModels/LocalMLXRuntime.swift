import Foundation

#if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
import MLXLLM
import MLXLMCommon
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

    func unloadIfLoaded(modelID: String) async {
        if loadedModelID == modelID {
            await unload()
        }
    }

    #if canImport(MLXLMCommon) && canImport(MLXLLM) && !targetEnvironment(simulator)
    func modelContainer(modelID: String, directory: URL) async throws -> ModelContainer {
        if loadedModelID == modelID, let container {
            return container
        }
        let configuration = ModelConfiguration(directory: directory)
        let loaded = try await loadModelContainer(configuration: configuration)
        container = loaded
        loadedModelID = modelID
        return loaded
    }
    #endif
}
