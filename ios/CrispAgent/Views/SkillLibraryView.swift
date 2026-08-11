import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    @EnvironmentObject private var store: SkillStore
    @State private var showFolderImporter = false
    @State private var showFileImporter = false
    @State private var showNewSkill = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let loadError = store.lastErrorMessage {
                    Section {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    ForEach(store.skills) { skill in
                        HStack(spacing: 12) {
                            NavigationLink {
                                SkillDetailView(skillID: skill.id)
                            } label: {
                                SkillRow(skill: skill)
                            }

                            Toggle(
                                "启用 \(skill.name)",
                                isOn: Binding(
                                    get: {
                                        store.skill(withID: skill.id)?.isEnabled
                                            ?? false
                                    },
                                    set: {
                                        store.setEnabled($0, for: skill.id)
                                    }
                                )
                            )
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("已安装")
                } footer: {
                    Text("启用的 Skill 会作为受限文本上下文发送给本机模型。它们不能执行脚本、添加原生工具或自行获得系统权限。")
                }
            }
            .navigationTitle("Skills")
            .overlay {
                if store.skills.isEmpty {
                    ContentUnavailableView(
                        "还没有 Skill",
                        systemImage: "wand.and.stars",
                        description: Text("导入一个包含 SKILL.md 的文件夹，或直接在 App 中新建。")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showFolderImporter = true
                        } label: {
                            Label("导入 Skill 文件夹", systemImage: "folder")
                        }

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("导入单个 SKILL.md", systemImage: "doc")
                        }

                        Divider()

                        Button {
                            showNewSkill = true
                        } label: {
                            Label("新建 Skill", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "md") ?? .plainText
                ],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showNewSkill) {
                NewSkillView()
            }
            .alert(
                "Skill 操作失败",
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

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try store.importPackage(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SkillRow: View {
    let skill: SkillDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(.headline)
                Text(skill.source.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(skill.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if skill.requestsUnsupportedTools {
                Label("声明的工具不会在此版本中运行", systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SkillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SkillStore
    let skillID: String

    @State private var skillText = ""
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if let skill = store.skill(withID: skillID) {
                Form {
                    Section("状态") {
                        Toggle(
                            "启用",
                            isOn: Binding(
                                get: {
                                    store.skill(withID: skillID)?.isEnabled
                                        ?? false
                                },
                                set: { store.setEnabled($0, for: skillID) }
                            )
                        )
                        LabeledContent("来源", value: skill.source.displayName)
                        LabeledContent("版本", value: skill.version)
                        LabeledContent("文件", value: "\(skill.fileCount)")
                    }

                    Section {
                        TextEditor(text: $skillText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 360)
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("SKILL.md")
                    } footer: {
                        Text(
                            skill.source == .bundled
                                ? "保存后会创建本机覆盖版本，App Bundle 中的原件保持不变。"
                                : "只能编辑 SKILL.md；引用文件仍保留在当前 Skill 文件夹中。"
                        )
                    }

                    Section {
                        Label(
                            "Prompt-only：不会执行 Skill 中声明的命令、脚本或设备工具。",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                    }

                    if skill.source == .imported {
                        Section {
                            Button("删除本机 Skill", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }
                .navigationTitle(skill.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            save()
                        }
                        .disabled(skillText.isEmpty)
                    }
                }
                .confirmationDialog(
                    "删除这个本机 Skill？",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("删除", role: .destructive) {
                        do {
                            try store.deleteUserSkill(id: skillID)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("如果它覆盖了内置 Skill，删除后会恢复内置版本。")
                }
            } else {
                ContentUnavailableView(
                    "Skill 不存在",
                    systemImage: "questionmark.folder"
                )
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            do {
                skillText = try store.rawSkillText(for: skillID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "无法保存 Skill",
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

    private func save() {
        do {
            try store.updateSkill(id: skillID, skillText: skillText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewSkillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SkillStore
    @State private var id = ""
    @State private var description = ""
    @State private var instructions = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("name，例如 my-writing-style", text: $id)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("这个 Skill 何时使用", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("指令") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 260)
                }

                Section {
                    Label(
                        "新 Skill 只会影响模型提示词，不会获得设备工具或执行权限。",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                }
            }
            .navigationTitle("新建 Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        create()
                    }
                    .disabled(
                        id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || description.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                            || instructions.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }
            }
            .alert(
                "无法创建 Skill",
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

    private func create() {
        do {
            try store.createSkill(
                id: id,
                description: description,
                instructions: instructions
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

