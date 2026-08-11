import Foundation

enum SkillSource: String {
    case bundled
    case imported

    var displayName: String {
        switch self {
        case .bundled: "App 内置"
        case .imported: "本机导入"
        }
    }
}

struct SkillDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let version: String
    let source: SkillSource
    let directoryURL: URL
    let fingerprint: String
    let fileCount: Int
    let totalBytes: Int
    let requestsUnsupportedTools: Bool
    var isEnabled: Bool
}

struct SkillFrontmatter: Equatable {
    let id: String
    let name: String
    let description: String
    let version: String
    let requestsTools: Bool
}

struct SkillPackageContents {
    let metadata: SkillFrontmatter
    var files: [String: Data]
    let fingerprint: String

    var totalBytes: Int {
        files.values.reduce(0) { $0 + $1.count }
    }
}

struct SkillPromptBundle {
    let systemPrompt: String
    let fingerprint: String
    let includedSkillIDs: [String]
    let wasTruncated: Bool
}

enum SkillPackageError: LocalizedError {
    case missingSkillFile
    case invalidUTF8(path: String)
    case invalidFrontmatter(String)
    case invalidIdentifier
    case unsupportedFile(path: String)
    case symbolicLink(path: String)
    case unsafePath(path: String)
    case duplicatePath(path: String)
    case tooManyFiles(limit: Int)
    case fileTooLarge(path: String, limit: Int)
    case packageTooLarge(limit: Int)
    case standaloneHasReferences
    case identifierChanged
    case bundledSkillCannotBeDeleted
    case skillNotFound

    var errorDescription: String? {
        switch self {
        case .missingSkillFile:
            "Skill 文件夹根目录必须包含且只能包含一个 SKILL.md。"
        case let .invalidUTF8(path):
            "\(path) 不是有效的 UTF-8 文本。"
        case let .invalidFrontmatter(reason):
            "SKILL.md frontmatter 无效：\(reason)"
        case .invalidIdentifier:
            "Skill name 必须匹配小写标识符格式，例如 crisp-voice。"
        case let .unsupportedFile(path):
            "Skill 包含不支持的文件类型：\(path)。只允许 .md、.txt 和 .json。"
        case let .symbolicLink(path):
            "Skill 包含符号链接，已拒绝导入：\(path)。"
        case let .unsafePath(path):
            "Skill 包含不安全路径：\(path)。"
        case let .duplicatePath(path):
            "Skill 包含大小写或 Unicode 归一化后重复的路径：\(path)。"
        case let .tooManyFiles(limit):
            "Skill 文件数量超过限制（最多 \(limit) 个）。"
        case let .fileTooLarge(path, limit):
            "\(path) 超过单文件限制（\(AppFormatting.byteCount(Int64(limit)))）。"
        case let .packageTooLarge(limit):
            "Skill 总大小超过限制（\(AppFormatting.byteCount(Int64(limit)))）。"
        case .standaloneHasReferences:
            "这个 SKILL.md 引用了同目录文件。请改为导入完整 Skill 文件夹。"
        case .identifierChanged:
            "编辑现有 Skill 时不能修改 frontmatter 中的 name。"
        case .bundledSkillCannotBeDeleted:
            "内置 Skill 不能删除；可以关闭它，或删除本机覆盖版本。"
        case .skillNotFound:
            "找不到这个 Skill。"
        }
    }
}

