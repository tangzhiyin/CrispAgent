import XCTest
@testable import CrispAgent

final class ModelIntegrityVerifierTests: XCTestCase {
    func testVerifiesStreamingSHA256() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)

        XCTAssertNoThrow(
            try ModelIntegrityVerifier.verify(
                fileURL: url,
                expectedBytes: 5,
                expectedSHA256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            )
        )
    }

    func testRejectsWrongHash() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)

        XCTAssertThrowsError(
            try ModelIntegrityVerifier.verify(
                fileURL: url,
                expectedBytes: 5,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        )
    }

    func testCatalogUsesPinnedArtifacts() {
        for model in LocalModelDescriptor.all {
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertTrue(
                model.downloadURLs[0].absoluteString.contains(
                    "/resolve/\(model.revision)/"
                )
            )
        }
    }
}

