import CryptoKit
import Foundation

enum ModelIntegrityVerifier {
    static func verify(
        fileURL: URL,
        expectedBytes: Int64,
        expectedSHA256: String
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualBytes == expectedBytes else {
            throw ModelStoreError.wrongFileSize(
                expected: expectedBytes,
                actual: actualBytes
            )
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024),
              !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        let actualSHA256 = hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()

        guard actualSHA256 == expectedSHA256.lowercased() else {
            throw ModelStoreError.wrongSHA256
        }
    }
}

