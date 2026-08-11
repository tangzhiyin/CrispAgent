import Foundation

struct LocalModelDescriptor: Identifiable, Hashable {
    let id: String
    let displayName: String
    let summary: String
    let revision: String
    let fileName: String
    let expectedBytes: Int64
    let sha256: String
    let downloadURLs: [URL]
    let recommendedMemoryGB: Int
    let isHighMemory: Bool

    let licenseURL = URL(string: "https://ai.google.dev/gemma/apache_2")!

    var formattedSize: String {
        AppFormatting.byteCount(expectedBytes)
    }

    static let gemma4E2B = LocalModelDescriptor(
        id: "gemma-4-e2b-it",
        displayName: "Gemma 4 E2B",
        summary: "默认推荐。速度快、内存占用较低，适合聊天与 Crisp 语气改写。",
        revision: "6b78abd019e61a1ca4cbe3b212d2c9ce8ff38a94",
        fileName: "gemma-4-E2B-it.litertlm",
        expectedBytes: 2_588_147_712,
        sha256: "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c",
        downloadURLs: [
            URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/6b78abd019e61a1ca4cbe3b212d2c9ce8ff38a94/gemma-4-E2B-it.litertlm")!,
            URL(string: "https://modelscope.cn/models/litert-community/gemma-4-E2B-it-litert-lm/resolve/master/gemma-4-E2B-it.litertlm")!
        ],
        recommendedMemoryGB: 6,
        isHighMemory: false
    )

    static let gemma4E4B = LocalModelDescriptor(
        id: "gemma-4-e4b-it",
        displayName: "Gemma 4 E4B",
        summary: "能力更强，但下载和内存占用更高；仅建议高内存 Pro 机型使用。",
        revision: "2eee7ac325f20eb8c9ac1d0e972f7c84663062da",
        fileName: "gemma-4-E4B-it.litertlm",
        expectedBytes: 3_659_530_240,
        sha256: "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0",
        downloadURLs: [
            URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/2eee7ac325f20eb8c9ac1d0e972f7c84663062da/gemma-4-E4B-it.litertlm")!,
            URL(string: "https://modelscope.cn/models/litert-community/gemma-4-E4B-it-litert-lm/resolve/master/gemma-4-E4B-it.litertlm")!
        ],
        recommendedMemoryGB: 8,
        isHighMemory: true
    )

    static let all: [LocalModelDescriptor] = [.gemma4E2B, .gemma4E4B]
    static let defaultModel = gemma4E2B

    static func model(withID id: String) -> LocalModelDescriptor? {
        all.first { $0.id == id }
    }
}

enum InferenceBackendPreference: String, CaseIterable, Identifiable {
    case automatic
    case gpu
    case cpu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "自动（推荐）"
        case .gpu: "GPU"
        case .cpu: "CPU"
        }
    }
}

enum ModelInstallPhase: Equatable {
    case notInstalled
    case downloading
    case paused
    case verifying
    case installed
    case failed
}

struct ModelInstallStatus: Equatable {
    var phase: ModelInstallPhase
    var progress: Double
    var completedBytes: Int64
    var totalBytes: Int64
    var message: String?

    static let notInstalled = ModelInstallStatus(
        phase: .notInstalled,
        progress: 0,
        completedBytes: 0,
        totalBytes: 0
    )

    static func installed(bytes: Int64) -> ModelInstallStatus {
        ModelInstallStatus(
            phase: .installed,
            progress: 1,
            completedBytes: bytes,
            totalBytes: bytes
        )
    }
}

enum ModelStoreError: LocalizedError {
    case unknownModel
    case alreadyInstalled
    case notInstalled
    case insufficientStorage(required: Int64, available: Int64)
    case invalidDownloadMetadata
    case wrongFileSize(expected: Int64, actual: Int64)
    case wrongSHA256
    case modelInUse
    case anotherDownloadInProgress

    var errorDescription: String? {
        switch self {
        case .unknownModel:
            "未知模型。"
        case .alreadyInstalled:
            "模型已经安装。"
        case .notInstalled:
            "模型尚未安装。"
        case let .insufficientStorage(required, available):
            "存储空间不足。至少需要 \(AppFormatting.byteCount(required))，当前约有 \(AppFormatting.byteCount(available))。"
        case .invalidDownloadMetadata:
            "下载任务缺少模型元数据。"
        case let .wrongFileSize(expected, actual):
            "模型文件大小不正确：预期 \(AppFormatting.byteCount(expected))，实际 \(AppFormatting.byteCount(actual))。"
        case .wrongSHA256:
            "模型 SHA-256 校验失败，文件已被丢弃。"
        case .modelInUse:
            "模型仍在推理引擎中使用。请先停止生成，再删除模型。"
        case .anotherDownloadInProgress:
            "一次只能下载或校验一个大型模型。请等待当前任务完成，或先暂停它。"
        }
    }
}
