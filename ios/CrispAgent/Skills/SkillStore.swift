import Foundation

@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var skills: [SkillDefinition] = []
    @Published var lastErrorMessage: String?

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    init() {
        reload()
    }

    func skill(withID id: String) -> SkillDefinition? {
        skills.first { $0.id == id }
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        defaults.set(enabled, forKey: enabledKey(id))
        if let index = skills.firstIndex(where: { $0.id == id }) {
            skills[index].isEnabled = enabled
        }
    }

    func importPackage(from externalURL: URL) throws {
        let accessed = externalURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }

        var package: SkillPackageContents?
        var readError: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(
            readingItemAt: externalURL,
            options: [.withoutChanges],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let values = try coordinatedURL.resourceValues(
                    forKeys: [.isDirectoryKey]
                )
                if values.isDirectory == true {
                    package = try SkillPackageLoader.loadFolder(at: coordinatedURL)
                } else {
                    package = try SkillPackageLoader.loadStandalone(at: coordinatedURL)
                }
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let readError {
            throw readError
        }
        guard let package else {
            throw SkillPackageError.missingSkillFile
        }

        try installUserPackage(package)
        defaults.set(true, forKey: enabledKey(package.metadata.id))
        reload()
    }

    func createSkill(
        id: String,
        description: String,
        instructions: String
    ) throws {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanInstructions = instructions.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let indentedDescription = cleanDescription
            .components(separatedBy: .newlines)
            .map { "  \($0)" }
            .joined(separator: "\n")
        let text = """
        ---
        name: \(cleanID)
        description: |
        \(indentedDescription)
        metadata:
          version: 1.0.0
        ---

        # \(cleanID)

        \(cleanInstructions)
        """
        guard let data = text.data(using: .utf8) else {
            throw SkillPackageError.invalidUTF8(path: "SKILL.md")
        }
        let metadata = try SkillPackageLoader.parseFrontmatter(data: data)
        let package = SkillPackageContents(
            metadata: metadata,
            files: ["SKILL.md": data],
            fingerprint: ""
        )
        try installUserPackage(package)
        defaults.set(true, forKey: enabledKey(metadata.id))
        reload()
    }

    func rawSkillText(for id: String) throws -> String {
        guard let skill = skill(withID: id) else {
            throw SkillPackageError.skillNotFound
        }
        let url = skill.directoryURL.appendingPathComponent("SKILL.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func updateSkill(id: String, skillText: String) throws {
        guard let definition = skill(withID: id),
              let data = skillText.data(using: .utf8) else {
            throw SkillPackageError.skillNotFound
        }
        let metadata = try SkillPackageLoader.parseFrontmatter(data: data)
        guard metadata.id == id else {
            throw SkillPackageError.identifierChanged
        }

        var package = try SkillPackageLoader.loadFolder(
            at: definition.directoryURL
        )
        package.files["SKILL.md"] = data
        package = SkillPackageContents(
            metadata: metadata,
            files: package.files,
            fingerprint: ""
        )
        try installUserPackage(package)
        reload()
    }

    func deleteUserSkill(id: String) throws {
        guard let definition = skill(withID: id) else {
            throw SkillPackageError.skillNotFound
        }
        guard definition.source == .imported else {
            throw SkillPackageError.bundledSkillCannotBeDeleted
        }
        try fileManager.removeItem(at: definition.directoryURL)
        reload()
    }

    func makePromptBundle(for userMessage: String) throws -> SkillPromptBundle {
        let enabled = skills.filter(\.isEnabled)
        let packages = try enabled.map { definition in
            (
                definition,
                try SkillPackageLoader.loadFolder(at: definition.directoryURL)
            )
        }
        return SkillPromptAssembler.assemble(
            packages: packages,
            userMessage: userMessage
        )
    }

    func reload() {
        var loaded: [String: SkillDefinition] = [:]
        var errors: [String] = []

        if let bundledRoot = bundledSkillsRoot() {
            loadSkillDirectories(
                under: bundledRoot,
                source: .bundled,
                into: &loaded,
                errors: &errors
            )
        } else {
            errors.append("App Bundle 中找不到内置 skills 目录。")
        }

        do {
            let userRoot = try AppDirectories.skills()
            loadSkillDirectories(
                under: userRoot,
                source: .imported,
                into: &loaded,
                errors: &errors
            )
        } catch {
            errors.append(error.localizedDescription)
        }

        skills = loaded.values.sorted {
            if $0.id == "crisp-voice" { return true }
            if $1.id == "crisp-voice" { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lastErrorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func loadSkillDirectories(
        under root: URL,
        source: SkillSource,
        into loaded: inout [String: SkillDefinition],
        errors: inout [String]
    ) {
        do {
            let children = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
            for child in children {
                let values = try child.resourceValues(
                    forKeys: [.isDirectoryKey, .isHiddenKey]
                )
                guard values.isDirectory == true, values.isHidden != true else {
                    continue
                }
                do {
                    let package = try SkillPackageLoader.loadFolder(at: child)
                    let id = package.metadata.id
                    loaded[id] = SkillDefinition(
                        id: id,
                        name: package.metadata.name,
                        description: package.metadata.description,
                        version: package.metadata.version,
                        source: source,
                        directoryURL: child,
                        fingerprint: package.fingerprint,
                        fileCount: package.files.count,
                        totalBytes: package.totalBytes,
                        requestsUnsupportedTools: package.metadata.requestsTools,
                        isEnabled: enabledValue(for: id)
                    )
                } catch {
                    errors.append("\(child.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func installUserPackage(_ package: SkillPackageContents) throws {
        let stagingParent = try AppDirectories.skillStaging()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagingPackage = stagingParent.appendingPathComponent(
            package.metadata.id,
            isDirectory: true
        )
        try AppDirectories.createDirectory(stagingPackage)
        defer { try? fileManager.removeItem(at: stagingParent) }

        for (relativePath, data) in package.files {
            let destination = stagingPackage.appendingPathComponent(relativePath)
            let parent = destination.deletingLastPathComponent()
            try AppDirectories.createDirectory(parent)
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        }

        let validated = try SkillPackageLoader.loadFolder(at: stagingPackage)
        guard validated.metadata.id == package.metadata.id else {
            throw SkillPackageError.identifierChanged
        }

        let userRoot = try AppDirectories.skills()
        let destination = userRoot.appendingPathComponent(
            package.metadata.id,
            isDirectory: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: stagingPackage,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: stagingPackage, to: destination)
        }
    }

    private func bundledSkillsRoot() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidates = [
            resources.appendingPathComponent("skills", isDirectory: true),
            resources.appendingPathComponent("Skills", isDirectory: true)
        ]
        if let root = candidates.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) {
            return root
        }

        if let crispVoice = Bundle.main.url(
            forResource: "crisp-voice",
            withExtension: nil
        ) {
            return crispVoice.deletingLastPathComponent()
        }
        return nil
    }

    private func enabledKey(_ id: String) -> String {
        "skills.enabled.\(id)"
    }

    private func enabledValue(for id: String) -> Bool {
        if defaults.object(forKey: enabledKey(id)) == nil {
            return true
        }
        return defaults.bool(forKey: enabledKey(id))
    }
}
