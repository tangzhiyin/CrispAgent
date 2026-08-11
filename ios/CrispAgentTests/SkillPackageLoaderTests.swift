import XCTest
@testable import CrispAgent

final class SkillPackageLoaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testLoadsValidSkillAndReferences() throws {
        let skill = """
        ---
        name: test-skill
        description: |
          Rewrites a short message.
        metadata:
          version: 2.1.0
        ---

        Use references/style.md.
        """
        try write(skill, to: "SKILL.md")
        try write("Keep it concise.", to: "references/style.md")

        let package = try SkillPackageLoader.loadFolder(at: temporaryDirectory)

        XCTAssertEqual(package.metadata.id, "test-skill")
        XCTAssertEqual(package.metadata.version, "2.1.0")
        XCTAssertEqual(package.files.count, 2)
        XCTAssertFalse(package.fingerprint.isEmpty)
    }

    func testRejectsUnsupportedFileTypes() throws {
        try write(
            """
            ---
            name: test-skill
            description: Test.
            ---
            """,
            to: "SKILL.md"
        )
        try Data([0x00]).write(
            to: temporaryDirectory.appendingPathComponent("payload.sh")
        )

        XCTAssertThrowsError(
            try SkillPackageLoader.loadFolder(at: temporaryDirectory)
        ) { error in
            guard case SkillPackageError.unsupportedFile = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStandaloneSkillRejectsLocalReferences() throws {
        let url = temporaryDirectory.appendingPathComponent("SKILL.md")
        try """
        ---
        name: test-skill
        description: Test.
        ---
        Read [style](references/style.md).
        """.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try SkillPackageLoader.loadStandalone(at: url)
        ) { error in
            guard case SkillPackageError.standaloneHasReferences = error else {
                return XCTFail("Unexpected error: \(error)")
            }

            func testDetectsMultilineToolRequests() throws {
                try write(
                    """
                    ---
                    name: test-skill
                    description: Test.
                    allowed-tools:
                      - shell
                    ---
                    """,
                    to: "SKILL.md"
                )

                let package = try SkillPackageLoader.loadFolder(at: temporaryDirectory)

                XCTAssertTrue(package.metadata.requestsTools)
            }

            func testRejectsNestedSecondSkillFile() throws {
                try write(
                    """
                    ---
                    name: test-skill
                    description: Test.
                    ---
                    """,
                    to: "SKILL.md"
                )
                try write(
                    """
                    ---
                    name: nested-skill
                    description: Nested.
                    ---
                    """,
                    to: "references/SKILL.md"
                )

                XCTAssertThrowsError(
                    try SkillPackageLoader.loadFolder(at: temporaryDirectory)
                )
            }
        }
    }

    func testPromptAssemblerEnforcesBudget() throws {
        try write(
            """
            ---
            name: test-skill
            description: Test.
            ---
            \(String(repeating: "a", count: 12_000))
            """,
            to: "SKILL.md"
        )
        let package = try SkillPackageLoader.loadFolder(at: temporaryDirectory)
        let definition = SkillDefinition(
            id: "test-skill",
            name: "test-skill",
            description: "Test.",
            version: "1.0.0",
            source: .imported,
            directoryURL: temporaryDirectory,
            fingerprint: package.fingerprint,
            fileCount: 1,
            totalBytes: package.totalBytes,
            requestsUnsupportedTools: false,
            isEnabled: true
        )

        let prompt = SkillPromptAssembler.assemble(
            packages: [(definition, package)]
        )

        XCTAssertTrue(prompt.wasTruncated)
        XCTAssertLessThanOrEqual(
            prompt.systemPrompt.count,
            SkillPromptAssembler.maximumSkillCharacters + 700
        )
    }

    private func write(_ text: String, to relativePath: String) throws {
        let url = temporaryDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
