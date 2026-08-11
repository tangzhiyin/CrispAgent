import Foundation
import LiteRTLM

enum LocalInferenceError: LocalizedError {
    case modelNotReady
    case generationAlreadyRunning
    case allBackendsFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            "模型尚未载入。"
        case .generationAlreadyRunning:
            "上一条回复仍在生成。"
        case let .allBackendsFailed(reason):
            "模型初始化失败：\(reason)"
        }
    }
}

@MainActor
final class LocalInferenceEngine: ObservableObject {
    @Published private(set) var loadedModelID: String?
    @Published private(set) var activeBackendName: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
    @Published private(set) var statusMessage = "尚未载入模型"
    @Published private(set) var contextWasReset = false

    private var engine: Engine?
    private var conversation: Conversation?
    private var engineKey: String?
    private var promptFingerprint: String?
    private var systemPrompt = ""
    private var sampler: SamplerConfig?
    private var needsContextReset = false
    private var conversationHistory: [ChatMessage] = []

    func prepare(
        model: LocalModelDescriptor,
        modelURL: URL,
        backendPreference: InferenceBackendPreference,
        prompt: SkillPromptBundle,
        history: [ChatMessage]
    ) async throws {
        conversationHistory = history
        let requestedEngineKey = [
            model.id,
            model.revision,
            modelURL.path,
            backendPreference.rawValue
        ].joined(separator: "|")

        if engineKey == requestedEngineKey, let engine {
            if promptFingerprint != prompt.fingerprint || conversation == nil {
                systemPrompt = prompt.systemPrompt
                promptFingerprint = prompt.fingerprint
                conversation = try await makeConversation(engine: engine)
                needsContextReset = false
            }
            return
        }

        unload()
        isLoading = true
        statusMessage = "正在载入 \(model.displayName)…"
        defer { isLoading = false }

        let cacheDirectory = try AppDirectories.liteRTCache()
            .appendingPathComponent(model.id, isDirectory: true)
        try AppDirectories.createDirectory(cacheDirectory)
        let sampler = try SamplerConfig(
            topK: 64,
            topP: 0.95,
            temperature: 0.8
        )
        self.sampler = sampler
        self.systemPrompt = prompt.systemPrompt

        var failures: [String] = []
        for candidate in backendCandidates(
            preference: backendPreference,
            model: model
        ) {
            do {
                let config = try EngineConfig(
                    modelPath: modelURL.path,
                    backend: candidate.backend,
                    maxNumTokens: 4096,
                    cacheDir: cacheDirectory.path
                )
                let candidateEngine = Engine(engineConfig: config)
                try await candidateEngine.initialize()
                let candidateConversation = try await makeConversation(
                    engine: candidateEngine
                )

                engine = candidateEngine
                conversation = candidateConversation
                engineKey = requestedEngineKey
                promptFingerprint = prompt.fingerprint
                loadedModelID = model.id
                activeBackendName = candidate.name
                statusMessage = "\(model.displayName) · \(candidate.name)"
                needsContextReset = false
                contextWasReset = false
                return
            } catch {
                failures.append("\(candidate.name): \(error.localizedDescription)")
                conversation = nil
                engine = nil
            }
        }

        statusMessage = "模型载入失败"
        throw LocalInferenceError.allBackendsFailed(
            failures.joined(separator: "；")
        )
    }

    func generate(
        prompt: String,
        onChunk: @MainActor (String) -> Void
    ) async throws {
        guard !isGenerating else {
            throw LocalInferenceError.generationAlreadyRunning
        }
        guard let engine else {
            throw LocalInferenceError.modelNotReady
        }

        if needsContextReset {
            conversation = try await makeConversation(engine: engine)
            needsContextReset = false
            contextWasReset = true
        } else {
            contextWasReset = false
        }
        guard let conversation else {
            throw LocalInferenceError.modelNotReady
        }

        isGenerating = true
        defer { isGenerating = false }

        for try await chunk in conversation.sendMessageStream(
            Message(prompt),
            maxOutputTokens: 512
        ) {
            try Task.checkCancellation()
            let text = chunk.toString
            if !text.isEmpty {
                onChunk(text)
            }
        }

        if (try? conversation.getTokenCount()) ?? 0 > 3_300 {
            needsContextReset = true
        }
    }

    func cancelGeneration() {
        try? conversation?.cancel()
    }

    func resetConversation(history: [ChatMessage] = []) async throws {
        guard let engine else { return }
        cancelGeneration()
        conversationHistory = history
        conversation = try await makeConversation(engine: engine)
        needsContextReset = false
        contextWasReset = false
    }

    func unload() {
        cancelGeneration()
        conversation = nil
        engine = nil
        engineKey = nil
        promptFingerprint = nil
        loadedModelID = nil
        activeBackendName = nil
        sampler = nil
        conversationHistory = []
        needsContextReset = false
        isGenerating = false
        statusMessage = "尚未载入模型"
    }

    private func makeConversation(engine: Engine) async throws -> Conversation {
        let initialMessages = conversationHistory.compactMap { message -> Message? in
            guard !message.text.isEmpty, !message.wasStopped else {
                return nil
            }
            let role: Role = message.role == .user ? .user : .model
            return Message(message.text, role: role)
        }
        try await engine.createConversation(
            with: ConversationConfig(
                systemMessage: Message(systemPrompt, role: .system),
                initialMessages: initialMessages,
                samplerConfig: sampler,
                automaticToolCalling: false
            )
        )
    }

    private func backendCandidates(
        preference: InferenceBackendPreference,
        model: LocalModelDescriptor
    ) -> [(name: String, backend: Backend)] {
        let cpuThreads = max(2, min(6, ProcessInfo.processInfo.processorCount - 1))
        switch preference {
        case .cpu:
            return [("CPU", .cpu(threadCount: cpuThreads))]
        case .gpu:
            return [("GPU", .gpu)]
        case .automatic:
            let memoryGB = Int(
                ProcessInfo.processInfo.physicalMemory / 1_073_741_824
            )
            if memoryGB < model.recommendedMemoryGB {
                return [("CPU", .cpu(threadCount: cpuThreads))]
            }
            return [
                ("GPU", .gpu),
                ("CPU 回退", .cpu(threadCount: cpuThreads))
            ]
        }
    }
}
