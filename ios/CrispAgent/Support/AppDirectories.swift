import Foundation

enum AppDirectories {
    private static let rootComponent = "CrispAgent"

    static func applicationSupport() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try createDirectory(base.appendingPathComponent(rootComponent, isDirectory: true))
    }

    static func models() throws -> URL {
        let url = try createDirectory(
            applicationSupport().appendingPathComponent("Models", isDirectory: true)
        )
        try excludeFromBackup(url)
        return url
    }

    static func modelDownloads() throws -> URL {
        let url = try createDirectory(
            applicationSupport().appendingPathComponent(".ModelDownloads", isDirectory: true)
        )
        try excludeFromBackup(url)
        return url
    }

    static func skills() throws -> URL {
        try createDirectory(
            applicationSupport().appendingPathComponent("Skills", isDirectory: true)
        )
    }

    static func skillStaging() throws -> URL {
        try createDirectory(
            applicationSupport().appendingPathComponent(".SkillStaging", isDirectory: true)
        )
    }

    static func liteRTCache() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try createDirectory(
            base
                .appendingPathComponent(rootComponent, isDirectory: true)
                .appendingPathComponent("LiteRTLM", isDirectory: true)
        )
    }

    static func chatHistory() throws -> URL {
        try applicationSupport().appendingPathComponent("chat-history.json")
    }

    @discardableResult
    static func createDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}

