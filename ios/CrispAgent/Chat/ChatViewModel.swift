import Foundation

enum ChatViewModelError: LocalizedError {
    case modelNotInstalled
    case emptyResponse
    case messageTooLong(limit: Int)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "请先在“模型”中下载并选择一个 Gemma 4 模型。"
        case .emptyResponse:
            "模型没有返回内容，请重试。"
        case let .messageTooLong(limit):
            "单条消息最多 \(limit) 个字符。请缩短内容或分成多条发送。"
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    static let maximumMessageCharacters = 2_000

    @Published private(set) var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var skillContextWasTruncated = false
    @Published var errorMessage: String?

    private let models: ModelStore
    private let skills: SkillStore
    private let runtime: LocalInferenceEngine
    private var generationTask: Task<Void, Never>?
    private var cancellationRequested = false

    init(
        models: ModelStore,
        skills: SkillStore,
        runtime: LocalInferenceEngine
    ) {
        self.models = models
        self.skills = skills
        self.runtime = runtime
        loadHistory()
    }

    func send() {
        let userText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, !isSending else { return }
        guard userText.count <= Self.maximumMessageCharacters else {
            errorMessage = ChatViewModelError.messageTooLong(
                limit: Self.maximumMessageCharacters
            ).localizedDescription
            return
        }

        let model = models.selectedModel
        guard let modelURL = models.installedURL(for: model) else {
            errorMessage = ChatViewModelError.modelNotInstalled.localizedDescription
            return
        }

        draft = ""
        errorMessage = nil
        cancellationRequested = false
        isSending = true

        let assistantID = UUID()
        messages.append(ChatMessage(role: .user, text: userText))
        messages.append(
            ChatMessage(id: assistantID, role: .assistant, text: "")
        )
        persistHistory()

        generationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSending = false
                self.generationTask = nil
                self.persistHistory()
            }

            do {
                let promptBundle = try self.skills.makePromptBundle(
                    for: userText
                )
                self.skillContextWasTruncated = promptBundle.wasTruncated
                try await self.runtime.prepare(
                    model: model,
                    modelURL: modelURL,
                    backendPreference: self.models.backendPreference,
                    prompt: promptBundle,
                    history: self.recentInferenceHistory(
                        forInputLength: userText.count
                    )
                )
                try await self.runtime.generate(prompt: userText) {
                    [weak self] chunk in
                    self?.append(chunk, to: assistantID)
                }

                guard let response = self.message(withID: assistantID),
                      !response.text.isEmpty else {
                    throw ChatViewModelError.emptyResponse
                }
            } catch {
                if self.cancellationRequested || Task.isCancelled {
                    self.markStopped(messageID: assistantID)
                } else {
                    self.removeEmptyAssistant(messageID: assistantID)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        guard isSending else { return }
        cancellationRequested = true
        runtime.cancelGeneration()
        generationTask?.cancel()
    }

    func newConversation() {
        stop()
        messages = []
        skillContextWasTruncated = false
        persistHistory()
        Task {
            do {
                try await runtime.resetConversation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearHistory() {
        newConversation()
    }

    private func append(_ text: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        messages[index].text += text
    }

    private func markStopped(messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        messages[index].wasStopped = true
        if messages[index].text.isEmpty {
            messages[index].text = "已停止生成。"
        }
    }

    private func removeEmptyAssistant(messageID: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageID }),
           messages[index].text.isEmpty {
            messages.remove(at: index)
        }
    }

    private func message(withID id: UUID) -> ChatMessage? {
        messages.first { $0.id == id }
    }

    private func recentInferenceHistory(
        forInputLength inputLength: Int
    ) -> [ChatMessage] {
        let priorMessages = messages.dropLast(min(2, messages.count))
        var selected: [ChatMessage] = []
        var characterCount = 0
        let budget = max(0, 800 - inputLength / 2)

        for message in priorMessages.reversed() {
            guard !message.text.isEmpty, !message.wasStopped else {
                continue
            }
            let nextCount = characterCount + message.text.count
            if nextCount > budget {
                break
            }
            selected.append(message)
            characterCount = nextCount
        }
        return Array(selected.reversed())
    }

    private func loadHistory() {
        do {
            let url = try AppDirectories.chatHistory()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            let data = try Data(contentsOf: url)
            messages = Array(
                try JSONDecoder().decode([ChatMessage].self, from: data).suffix(80)
            )
        } catch {
            errorMessage = "无法读取聊天历史：\(error.localizedDescription)"
        }
    }

    private func persistHistory() {
        do {
            let data = try JSONEncoder().encode(Array(messages.suffix(80)))
            try data.write(to: AppDirectories.chatHistory(), options: .atomic)
        } catch {
            errorMessage = "无法保存聊天历史：\(error.localizedDescription)"
        }
    }
}
