import SwiftUI

struct SettingsView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = true
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var runtime: LocalInferenceEngine
    @EnvironmentObject private var chat: ChatViewModel
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("本机推理") {
                    LabeledContent(
                        "当前模型",
                        value: runtime.loadedModelID.flatMap {
                            LocalModelDescriptor.model(withID: $0)?.displayName
                        } ?? "未载入"
                    )
                    LabeledContent(
                        "当前后端",
                        value: runtime.activeBackendName ?? "—"
                    )
                    Picker("首选后端", selection: $models.backendPreference) {
                        ForEach(InferenceBackendPreference.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }

                    Button("从内存卸载模型") {
                        runtime.unload()
                    }
                    .disabled(runtime.loadedModelID == nil)
                }

                Section("隐私与安全") {
                    Label(
                        "模型推理和 Skill 处理都在此 iPhone 完成。",
                        systemImage: "iphone.gen3.radiowaves.left.and.right"
                    )
                    Label(
                        "导入的 Skill 是文本数据，不能下载或执行代码。",
                        systemImage: "lock.shield"
                    )
                    Label(
                        "此版本不提供 Shell、文件系统、MCP 或设备操作工具。",
                        systemImage: "hand.raised"
                    )
                }

                Section("数据") {
                    Button("清空聊天历史", role: .destructive) {
                        showClearConfirmation = true
                    }
                    Button("重新显示首次启动说明") {
                        onboardingCompleted = false
                    }
                }

                Section("开源许可") {
                    Link(
                        "LiteRT-LM · Apache 2.0",
                        destination: URL(
                            string: "https://github.com/google-ai-edge/LiteRT-LM/blob/v0.15.0/LICENSE"
                        )!
                    )
                    Link(
                        "Gemma 4 · Apache 2.0",
                        destination: LocalModelDescriptor.defaultModel.licenseURL
                    )
                    Text("LiteRT-LM 的 Swift API 当前仍属于 Early Preview。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("App 版本", value: appVersion)
                }
            }
            .navigationTitle("设置")
            .confirmationDialog(
                "清空全部聊天历史？",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空", role: .destructive) {
                    chat.clearHistory()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return "\(version) (\(build))"
    }
}
