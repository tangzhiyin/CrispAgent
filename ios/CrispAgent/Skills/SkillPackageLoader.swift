import CryptoKit
import Foundation

enum SkillPackageLoader {
    static let maximumFileCount = 24
    static let maximumFileBytes = 64 * 1024
    static let maximumPackageBytes = 256 * 1024

    private static let allowedExtensions = Set(["md", "txt", "json"])

    static func loadFolder(at rootURL: URL) throws -> SkillPackageContents {
        let root = rootURL.standardizedFileURL
        let rootValues = try root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true else {
            throw SkillPackageError.missingSkillFile
        }
        if rootValues.isSymbolicLink == true {
            throw SkillPackageError.symbolicLink(path: root.lastPathComponent)
        }

        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw SkillPackageError.missingSkillFile
        }

        var files: [String: Data] = [:]
        var normalizedPaths = Set<String>()
        var totalBytes = 0

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            let relativePath = try safeRelativePath(fileURL, within: root)

            if values.isSymbolicLink == true {
                throw SkillPackageError.symbolicLink(path: relativePath)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw SkillPackageError.unsupportedFile(path: relativePath)
            }

            let pathKey = relativePath
                .precomposedStringWithCanonicalMapping
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
            guard normalizedPaths.insert(pathKey).inserted else {
                throw SkillPackageError.duplicatePath(path: relativePath)
            }

            guard allowedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                throw SkillPackageError.unsupportedFile(path: relativePath)
            }
            guard files.count < maximumFileCount else {
                throw SkillPackageError.tooManyFiles(limit: maximumFileCount)
            }

            let fileSize = values.fileSize ?? 0
            guard fileSize <= maximumFileBytes else {
                throw SkillPackageError.fileTooLarge(
                    path: relativePath,
                    limit: maximumFileBytes
                )
            }

            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard data.count <= maximumFileBytes else {
                throw SkillPackageError.fileTooLarge(
                    path: relativePath,
                    limit: maximumFileBytes
                )
            }
            guard String(data: data, encoding: .utf8) != nil else {
                throw SkillPackageError.invalidUTF8(path: relativePath)
            }

            totalBytes += data.count
            guard totalBytes <= maximumPackageBytes else {
                throw SkillPackageError.packageTooLarge(limit: maximumPackageBytes)
            }
            files[relativePath] = data
        }

        let skillFiles = files.keys.filter {
            URL(fileURLWithPath: $0).lastPathComponent == "SKILL.md"
        }
        guard skillFiles.count == 1, let skillData = files["SKILL.md"] else {
            throw SkillPackageError.missingSkillFile
        }
        let metadata = try parseFrontmatter(data: skillData)
        return SkillPackageContents(
            metadata: metadata,
            files: files,
            fingerprint: fingerprint(files: files)
        )
    }

    static func loadStandalone(at fileURL: URL) throws -> SkillPackageContents {
        guard fileURL.lastPathComponent == "SKILL.md" else {
            throw SkillPackageError.missingSkillFile
        }

        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        if values.isSymbolicLink == true {
            throw SkillPackageError.symbolicLink(path: "SKILL.md")
        }
        guard values.isRegularFile == true else {
            throw SkillPackageError.missingSkillFile
        }
        guard (values.fileSize ?? 0) <= maximumFileBytes else {
            throw SkillPackageError.fileTooLarge(
                path: "SKILL.md",
                limit: maximumFileBytes
            )
        }

        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SkillPackageError.invalidUTF8(path: "SKILL.md")
        }
        if containsLocalMarkdownReference(text) {
            throw SkillPackageError.standaloneHasReferences
        }

        let metadata = try parseFrontmatter(data: data)
        let files = ["SKILL.md": data]
        return SkillPackageContents(
            metadata: metadata,
            files: files,
            fingerprint: fingerprint(files: files)
        )
    }

    static func parseFrontmatter(data: Data) throws -> SkillFrontmatter {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SkillPackageError.invalidUTF8(path: "SKILL.md")
        }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let endIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              })
        else {
            throw SkillPackageError.invalidFrontmatter(
                "需要以 --- 包围 YAML frontmatter"
            )
        }

        let header = Array(lines[1..<endIndex])
        var name: String?
        var description: String?
        var version: String?
        var requestsTools = false
        var index = 0
        var section: String?
        var seenTopLevelKeys = Set<String>()

        while index < header.count {
            let line = header[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
            if indentation > 0,
               (section == "allowed-tools" || section == "tools"),
               trimmed.hasPrefix("-") {
                requestsTools = true
                index += 1
                continue
            }
            guard let separator = trimmed.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = String(trimmed[..<separator]).lowercased()
            let rawValue = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)

            if indentation == 0 {
                section = key
                if ["name", "description", "version"].contains(key),
                   !seenTopLevelKeys.insert(key).inserted {
                    throw SkillPackageError.invalidFrontmatter(
                        "重复字段 \(key)"
                    )
                }
                switch key {
                case "name":
                    name = unquote(rawValue)
                case "description":
                    if rawValue.hasPrefix("|") || rawValue.hasPrefix(">") {
                        var block: [String] = []
                        var next = index + 1
                        while next < header.count {
                            let candidate = header[next]
                            let candidateIndent = candidate.prefix {
                                $0 == " " || $0 == "\t"
                            }.count
                            if !candidate.trimmingCharacters(in: .whitespaces).isEmpty,
                               candidateIndent == 0 {
                                break
                            }
                            block.append(candidate.trimmingCharacters(in: .whitespaces))
                            next += 1
                        }
                        description = block.joined(separator: " ")
                        index = next
                        continue
                    } else {
                        description = unquote(rawValue)
                    }
                case "version":
                    version = unquote(rawValue)
                case "allowed-tools", "tools":
                    requestsTools = !rawValue.isEmpty && rawValue != "[]"
                default:
                    break
                }
            } else if section == "metadata", key == "version" {
                version = unquote(rawValue)
            } else if section == "allowed-tools" || section == "tools" {
                if trimmed.hasPrefix("-") || !rawValue.isEmpty {
                    requestsTools = true
                }
            }
            index += 1
        }

        guard let id = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else {
            throw SkillPackageError.invalidFrontmatter("缺少 name")
        }
        guard id.range(
            of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#,
            options: .regularExpression
        ) != nil else {
            throw SkillPackageError.invalidIdentifier
        }

        let cleanDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanDescription.isEmpty else {
            throw SkillPackageError.invalidFrontmatter("缺少 description")
        }

        let cleanVersion = version.flatMap { value in
            value.isEmpty ? nil : value
        } ?? "1.0.0"

        return SkillFrontmatter(
            id: id,
            name: id,
            description: cleanDescription,
            version: cleanVersion,
            requestsTools: requestsTools
        )
    }

    private static func safeRelativePath(_ fileURL: URL, within root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw SkillPackageError.unsafePath(path: filePath)
        }

        let relative = String(filePath.dropFirst(prefix.count))
            .replacingOccurrences(of: "\\", with: "/")
        let components = relative.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        let forbiddenPathCharacters = CharacterSet(
            charactersIn: "\"<>|?*"
        )
        guard !components.isEmpty,
              components.count <= 8,
              relative.count <= 240,
              components.allSatisfy({ component in
                  !component.isEmpty && component != "." && component != ".."
                      && !component.contains(":")
                      && !component.unicodeScalars.contains { $0.value < 32 }
                      && !component.unicodeScalars.contains {
                          forbiddenPathCharacters.contains($0)
                      }
              })
        else {
            throw SkillPackageError.unsafePath(path: relative)
        }
        return relative.precomposedStringWithCanonicalMapping
    }

    private static func fingerprint(files: [String: Data]) -> String {
        var hasher = SHA256()
        for path in files.keys.sorted() {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            if let data = files[path] {
                hasher.update(data: data)
            }
            hasher.update(data: Data([0]))
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func containsLocalMarkdownReference(_ text: String) -> Bool {
        if text.contains("references/") || text.contains("../") {
            return true
        }
        let pattern = #"\]\((?!https?://|#|mailto:)([^)]+)\)"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, options: [], range: range) != nil
    }
}
