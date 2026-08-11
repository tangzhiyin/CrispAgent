import SwiftUI

struct ModelLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: ModelStore
    @State private var pendingDownload: LocalModelDescriptor?
    @State private var pendingDeletion: LocalModelDescriptor?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let storageError = store.storageErrorMessage {
                    Section {
                        Label(storageError, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach(LocalModelDescriptor.all) { model in
                        ModelRow(
                            model: model,
                            status: store.status(for: model),
                            isSelected: store.selectedModelID == model.id,
                            deviceMemoryGB: store.physicalMemoryGB,
                            onDownload: { pendingDownload = model },
                            onPause: { store.pauseDownload(model) },
                            onCancel: { store.cancelDownload(model) },
                            onSelect: { select(model) },
                            onDelete: { pendingDeletion = model }
                        )
                    }
                } header: {
                    Text("端侧模型")
                } footer: {
                    Text("Gemma 4 是 Google 的开放模型系列，不是 Gemini。模型只会保存到本 App 的沙盒中。")
                }

                Section("推理后端") {
                    Picker("后端", selection: $store.backendPreference) {
                        ForEach(InferenceBackendPreference.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    Text("自动模式优先使用 Metal GPU；初始化失败或内存不足时回退到 CPU。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("模型")
            .sheet(item: $pendingDownload) { model in
                ModelDownloadConsentView(model: model) {
                    do {
                        try store.startDownload(model)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .confirmationDialog(
                "删除模型文件？",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    guard let model = pendingDeletion else { return }
                    Task {
                        do {
                            try appState.deleteModel(model)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        pendingDeletion = nil
                    }
                }
                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("之后仍可重新下载。Skill 和聊天历史不会被删除。")
            }
            .alert(
                "模型操作失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func select(_ model: LocalModelDescriptor) {
        do {
            try store.select(model)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ModelRow: View {
    let model: LocalModelDescriptor
    let status: ModelInstallStatus
    let isSelected: Bool
    let deviceMemoryGB: Int
    let onDownload: () -> Void
    let onPause: () -> Void
    let onCancel: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.headline)
                        if model == .defaultModel {
                            Text("推荐")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text("\(model.formattedSize) · SHA-256 校验")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected && status.phase == .installed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("已选择")
                }
            }

            Text(model.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.isHighMemory && deviceMemoryGB < model.recommendedMemoryGB {
                Label(
                    "本机约 \(deviceMemoryGB) GB 内存，低于建议的 \(model.recommendedMemoryGB) GB",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            controls

            if let message = status.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(
                        status.phase == .failed ? .red : .secondary
                    )
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var controls: some View {
        switch status.phase {
        case .notInstalled:
            Button("下载模型", action: onDownload)
                .buttonStyle(.borderedProminent)

        case .downloading:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: status.progress)
                HStack {
                    Text(
                        "\(AppFormatting.byteCount(status.completedBytes)) / \(AppFormatting.byteCount(status.totalBytes))"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("暂停", action: onPause)
                    Button("取消", role: .destructive, action: onCancel)
                }
            }

        case .paused:
            HStack {
                ProgressView(value: status.progress)
                Button("继续", action: onDownload)
                    .buttonStyle(.borderedProminent)
                Button("取消", role: .destructive, action: onCancel)
            }

        case .verifying:
            HStack {
                ProgressView()
                Text("正在校验完整性…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .installed:
            HStack {
                if !isSelected {
                    Button("设为当前模型", action: onSelect)
                        .buttonStyle(.borderedProminent)
                } else {
                    Label("当前模型", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("删除", role: .destructive, action: onDelete)
            }

        case .failed:
            HStack {
                Button("重试", action: onDownload)
                    .buttonStyle(.borderedProminent)
                Button("清除", role: .destructive, action: onCancel)
            }
        }
    }
}

private struct ModelDownloadConsentView: View {
    @Environment(\.dismiss) private var dismiss
    let model: LocalModelDescriptor
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)

                    Text("下载 \(model.displayName)")
                        .font(.largeTitle.bold())

                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.formattedSize, systemImage: "internaldrive")
                        Label(
                            "建议至少 \(model.recommendedMemoryGB) GB 设备内存",
                            systemImage: "memorychip"
                        )
                        Label("下载后可完全离线推理", systemImage: "wifi.slash")
                        Label("完成后校验 SHA-256", systemImage: "checkmark.shield")
                    }

                    Text("这是一次大型资源下载。建议连接 Wi-Fi 和电源，并预留约 15% 的额外空间。下载可以暂停和继续；强制退出 App 后，iOS 不会自动唤醒它继续下载。")
                        .foregroundStyle(.secondary)

                    if model.isHighMemory {
                        Label(
                            "E4B 的 GPU 内存占用很高，部分设备可能被 iOS 终止。E2B 是更稳妥的默认选择。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }

                    Link("查看 Gemma 4 Apache 2.0 许可", destination: model.licenseURL)

                    Button {
                        onAccept()
                        dismiss()
                    } label: {
                        Text("同意并开始下载")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("下载确认")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
