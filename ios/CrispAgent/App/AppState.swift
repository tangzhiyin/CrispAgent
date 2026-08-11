import Foundation

@MainActor
final class AppState: ObservableObject {
    let models: ModelStore
    let skills: SkillStore
    let runtime: LocalInferenceEngine
    let chat: ChatViewModel

    init() {
        let models = ModelStore()
        let skills = SkillStore()
        let runtime = LocalInferenceEngine()

        self.models = models
        self.skills = skills
        self.runtime = runtime
        self.chat = ChatViewModel(models: models, skills: skills, runtime: runtime)

        models.isModelInUse = { [weak runtime] modelID in
            runtime?.loadedModelID == modelID
        }
    }

    func deleteModel(_ model: LocalModelDescriptor) throws {
        if runtime.loadedModelID == model.id {
            if runtime.isGenerating {
                throw ModelStoreError.modelInUse
            }
            runtime.unload()
        }
        try models.deleteInstalledModel(model)
    }
}
