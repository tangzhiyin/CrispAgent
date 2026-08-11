import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var skills: SkillStore
    @EnvironmentObject private var runtime: LocalInferenceEngine
    @Binding var selectedTab: RootTab

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                Divider()

                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                composer
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Crisp Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("新对话")
                }
            }
            .alert(
                "Crisp Agent",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { presented in
                        if !presented {
                            viewModel.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Button {
                selectedTab = .models
            } label: {
                Label(
                    models.installedURL(for: models.selectedModel) == nil
                        ? "选择模型"
                        : models.selectedModel.displayName,
                    systemImage: "cpu"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Button {
                selectedTab = .skills
            } label: {
                Label(
                    "\(skills.skills.filter(\.isEnabled).count) Skills",
                    systemImage: "wand.and.stars"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Spacer()

            if runtime.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(runtime.loadedModelID == nil ? .secondary : .green)
                    .frame(width: 8, height: 8)
            }

            if viewModel.skillContextWasTruncated {
                Image(systemName: "text.badge.minus")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Skill 上下文已按 4K 限制压缩")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.accentColor)

            Text("你的端侧 Crisp Agent")
                .font(.title2.bold())

            Text(emptyStateDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if models.installedURL(for: models.selectedModel) == nil {
                Button("下载 Gemma 4 模型") {
                    selectedTab = .models
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("所有推理都在这台 iPhone 上完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateDescription: String {
        if models.installedURL(for: models.selectedModel) == nil {
            return "先下载一个 Gemma 4 模型。模型安装完成后，不联网也可以聊天和调用已启用的 Skill。"
        }
        return "可以让我按 Crisp 的语气改写、回复、解释或给建议。你也可以在 Skills 页面导入自己的 SKILL.md。"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                guard let id = viewModel.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if runtime.isLoading || viewModel.isSending {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(runtime.isLoading ? runtime.statusMessage : "正在本机生成…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "发消息给 Crisp Agent",
                    text: $viewModel.draft,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .submitLabel(.send)
                .onSubmit {
                    viewModel.send()
                }

                if viewModel.isSending {
                    Button {
                        viewModel.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("停止生成")
                } else {
                    Button {
                        viewModel.send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .fontWeight(.bold)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(
                        viewModel.draft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || viewModel.draft.count
                                > ChatViewModel.maximumMessageCharacters
                    )
                    .accessibilityLabel("发送")
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .topTrailing) {
            if viewModel.draft.count > 1_600 {
                Text(
                    "\(viewModel.draft.count)/\(ChatViewModel.maximumMessageCharacters)"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(
                    viewModel.draft.count > ChatViewModel.maximumMessageCharacters
                        ? .red
                        : .secondary
                )
                .padding(.trailing, 64)
                .offset(y: -14)
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 50)
            }

            VStack(alignment: .leading, spacing: 6) {
                if message.text.isEmpty {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.small)
                        Text("思考中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                }

                if message.wasStopped {
                    Label("已停止", systemImage: "stop.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(message.role == .user ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        message.role == .user
                            ? Color.accentColor
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
            )

            if message.role == .assistant {
                Spacer(minLength: 50)
            }
        }
    }
}
