import XCTest
import CSQLCipher
@testable import ContextServiceCore

final class ContextServiceTests: XCTestCase {
    private func editEncryptedMetadata(directory: URL, key: Data, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("context.db").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(key.withUnsafeBytes { sqlite3_key(database, $0.baseAddress, Int32($0.count)) }, SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }

    func testEmbeddingModelBindingPersistsAndRejectsDifferentModelWithoutDeletingEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 51, count: 32)
        let now = ContextStore.now
        do {
            let store = try ContextStore(directory: directory, key: key)
            try store.put(Evidence(id: "retained", sourceId: "source", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "retained evidence"), now: now)
            try store.embed(id: "retained", revision: "1", vector: Array(repeating: 1, count: 768))
        }
        do {
            let reopened = try ContextStore(directory: directory, key: key)
            XCTAssertEqual(try reopened.retrieve(query: "retained", embedding: Array(repeating: 1, count: 768), now: now).evidence.first?.id, "retained")
        }
        try editEncryptedMetadata(directory: directory, key: key, sql: "UPDATE metadata SET value='google/gemini-embedding-2@google:768' WHERE key='embedding_model'")
        XCTAssertThrowsError(try ContextStore(directory: directory, key: key)) {
            XCTAssertEqual(($0 as? StoreError)?.rawValue, "embeddingModelMismatch")
        }
        // Repair the test fixture to prove rejection did not delete or rewrite its contents.
        try editEncryptedMetadata(directory: directory, key: key, sql: "UPDATE metadata SET value='google/text-multilingual-embedding-002@vertex:768' WHERE key='embedding_model'")
        let reopened = try ContextStore(directory: directory, key: key)
        XCTAssertEqual(try reopened.history(now: now).first?.text, "retained evidence")
        XCTAssertTrue(try reopened.pendingEmbeddings(now: now).isEmpty)
    }

    func testUnboundExistingVectorsAreNeverAdoptedAsCurrentModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 53, count: 32)
        let now = ContextStore.now
        do {
            let store = try ContextStore(directory: directory, key: key)
            try store.put(Evidence(id: "unknown", sourceId: "unknown", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "unknown model"), now: now)
            try store.embed(id: "unknown", revision: "1", vector: Array(repeating: 1, count: 768))
        }
        try editEncryptedMetadata(directory: directory, key: key, sql: "DROP TABLE metadata")
        XCTAssertThrowsError(try ContextStore(directory: directory, key: key)) {
            XCTAssertEqual(($0 as? StoreError)?.rawValue, "embeddingModelMismatch")
        }
    }

    func testEncryptionExpiryAndDependencyInvalidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 42, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let first = Evidence(id: "one", sourceId: "source", revision: "1", provenance: "observed", appId: "test", capturedAtMs: now, expiresAtMs: now + 1000, text: "private canary UNIQUE_CONTENT")
        try store.put(first, now: now)
        var duplicate = first; duplicate.expiresAtMs = now + 999999
        try store.put(duplicate, now: now)
        XCTAssertEqual(try store.history(now: now).first?.expiresAtMs, now + 1000)
        var derived = first; derived.id = "derived"; derived.sourceId = "derived-source"; derived.provenance = "derived"; derived.dependencies = [.init(sourceId: "source", revision: "1")]
        try store.put(derived, now: now)
        var second = first; second.revision = "2"
        try store.put(second, now: now)
        XCTAssertEqual(try store.history(now: now).count, 1)
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data("UNIQUE_CONTENT".utf8)))
            XCTAssertFalse(bytes.starts(with: Data("SQLite format 3".utf8)))
        }
        XCTAssertTrue(try store.history(now: now + 1001).isEmpty)
    }
    func testSavedReferencesAndVectorValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 7, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let item = Evidence(id: "one", sourceId: "source", revision: "1", provenance: "authored", appId: "test", capturedAtMs: now, expiresAtMs: now + 60000, text: "reference")
        try store.put(item, now: now)
        try store.save(id: "one", saved: true)
        XCTAssertEqual(try store.history(now: now + 100000).count, 1)
        XCTAssertThrowsError(try store.embed(id: "one", revision: "1", vector: [1]))
        try store.embed(id: "one", revision: "1", vector: Array(repeating: 1, count: 768))
        try store.purgeApp("test")
        XCTAssertTrue(try store.history(now: now).isEmpty)
    }
    func testHybridRetrievalBoundAndRevisionValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 17, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for index in 0..<45 {
            var item = Evidence(id: "i\(index)", sourceId: "s\(index)", revision: "1", provenance: "observed", appId: index % 2 == 0 ? "a" : "b", capturedAtMs: now, expiresAtMs: now + 60000, text: "searchable " + String(repeating: "x", count: 4000))
            item.documentId = "doc"
            try store.put(item, now: now)
            try store.embed(id: item.id, revision: item.revision, vector: Array(repeating: 1, count: 768))
        }
        let result = try store.retrieve(query: "searchable", embedding: Array(repeating: 1, count: 768), appId: "a", documentId: "doc", now: now)
        XCTAssertFalse(result.evidence.isEmpty)
        XCTAssertEqual(result.availability.text, "ready")
        XCTAssertEqual(result.availability.semantic, "included")
        XCTAssertEqual(try store.retrieve(query: "searchable", now: now).availability.semantic, "not_prepared")
        XCTAssertLessThanOrEqual(result.evidence.count, 12)
        XCTAssertLessThanOrEqual(result.evidence.reduce(0) { $0 + $1.text.utf8.count }, 8000)
        XCTAssertTrue(result.evidence.allSatisfy { $0.appId == "a" && $0.documentId == "doc" })
        XCTAssertTrue(try store.validate(result.dependencies, now: now))
        XCTAssertEqual(result.revision, try store.retrieve(query: "searchable", embedding: Array(repeating: 1, count: 768), appId: "a", documentId: "doc", now: now).revision)
        try store.deleteSource(result.evidence[0].sourceId)
        XCTAssertFalse(try store.validate(result.dependencies, now: now))
        let afterDeletion = try store.retrieve(query: "searchable", embedding: Array(repeating: 1, count: 768), now: now)
        XCTAssertFalse(afterDeletion.evidence.contains { $0.sourceId == result.evidence[0].sourceId })
        try store.clear()
        XCTAssertTrue(try store.retrieve(query: "searchable", embedding: Array(repeating: 1, count: 768), now: now).evidence.isEmpty)
    }
    func testWrongKeyFailsClosedAndRestartPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            let store = try ContextStore(directory: directory, key: Data(repeating: 1, count: 32))
            try store.put(Evidence(id: "persist", sourceId: "s", revision: "1", provenance: "authored", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "persistent encrypted data"), now: now)
        }
        XCTAssertThrowsError(try ContextStore(directory: directory, key: Data(repeating: 2, count: 32)))
        XCTAssertThrowsError(try ContextStore(directory: directory, key: Data()))
        let reopened = try ContextStore(directory: directory, key: Data(repeating: 1, count: 32))
        XCTAssertEqual(try reopened.history(now: now).first?.id, "persist")
    }

    func testHundredThousandVectorRetrievalBenchmark() throws {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_CONTEXT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in 100k corpus benchmark") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 3, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let vector = Array(repeating: 0.125, count: 768)
        let start = Date()
        for i in 0..<100000 {
            try store.put(Evidence(id: "benchmark-\(i)", sourceId: "source-\(i)", revision: "1", provenance: "observed", appId: "benchmark", capturedAtMs: now, expiresAtMs: now + 86400000, text: "Synthetic corpus fragment \(i)"), now: now)
            try store.embed(id: "benchmark-\(i)", revision: "1", vector: vector)
        }
        let loaded = Date()
        let result = try store.retrieve(query: "Synthetic", embedding: vector, now: now)
        let cold = Date().timeIntervalSince(loaded)
        var timings: [Double] = []
        for sample in 0..<20 {
            let start = Date()
            _ = try store.retrieve(query: sample % 2 == 0 ? "Synthetic" : "Synthetic corpus", embedding: vector, now: now)
            timings.append(Date().timeIntervalSince(start))
        }
        for mode in ["recent", "vector", "fts"] {
            let measured = Date()
            for _ in 0..<5 { _ = try store.retrieve(query: mode == "fts" ? "Synthetic" : "", embedding: mode == "vector" ? vector : nil, now: now) }
            print("100k channel \(mode): meanSeconds=\(Date().timeIntervalSince(measured) / 5)")
        }
        timings.sort()
        let elapsed = timings[18]
        print("100k SQLCipher vectors: insertSeconds=\(loaded.timeIntervalSince(start)) coldSeconds=\(cold) warmP95Seconds=\(elapsed)")
        XCTAssertEqual(result.evidence.count, 12)
        XCTAssertLessThan(elapsed, 0.1)
    }

    func testOldStrongExactPhraseSurvivesFrequentRecentMatches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 19, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try store.put(Evidence(id: "old", sourceId: "old", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now - 100000, expiresAtMs: now + 60000, text: "The project zephyr deadline is Friday."), now: now)
        for i in 0..<1000 {
            try store.put(Evidence(id: "recent-\(i)", sourceId: "recent-\(i)", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "The project meeting notes are updated."), now: now)
        }
        let result = try store.retrieve(query: "project zephyr", now: now)
        XCTAssertTrue(result.evidence.contains { $0.id == "old" })
    }

    func testAccountsHaveSeparateDatabases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let first = try ContextStore(directory: root.appendingPathComponent(AccountKey.directoryName("account-a")), key: Data(repeating: 1, count: 32))
        let second = try ContextStore(directory: root.appendingPathComponent(AccountKey.directoryName("account-b")), key: Data(repeating: 2, count: 32))
        try first.put(Evidence(id: "same-id", sourceId: "same-source", revision: "1", provenance: "authored", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "first account content"), now: now)
        XCTAssertTrue(try second.history(now: now).isEmpty)
        try second.put(Evidence(id: "same-id", sourceId: "same-source", revision: "1", provenance: "authored", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "second account content"), now: now)
        XCTAssertEqual(try first.history(now: now).first?.text, "first account content")
        try second.clear()
        XCTAssertEqual(try first.history(now: now).count, 1)
    }

    func testPinnedRevisionArchiveAndClearHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 29, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let original = Evidence(id: "original", sourceId: "source", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "incorrect original statement")
        try store.put(original, now: now)
        try store.save(id: original.id, saved: true)
        var latest = original; latest.id = "latest"; latest.revision = "2"; latest.text = "corrected statement"
        try store.put(latest, now: now)
        XCTAssertEqual(try store.revisions(source: "source", now: now).count, 2)
        XCTAssertEqual(try store.history(now: now).first?.id, "latest")
        XCTAssertTrue(try store.savedIds().contains("latest"))
        try store.save(id: "latest", saved: false)
        XCTAssertTrue(try store.savedIds().isEmpty)
        try store.save(id: "latest", saved: true)
        XCTAssertFalse(try store.retrieve(query: "incorrect original", now: now).evidence.contains { $0.revision == "1" })
        var unsaved = original; unsaved.id = "temporary"; unsaved.sourceId = "other"
        try store.put(unsaved, now: now)
        try store.clear()
        XCTAssertEqual(try store.history(now: now).map(\.id), ["latest"])
        XCTAssertEqual(try store.revisions(source: "source", now: now + 100000).count, 2)
        try store.deleteSource("source")
        XCTAssertTrue(try store.revisions(source: "source", now: now).isEmpty)
    }
    func testArchivesExpireAndPurgeWithDependentRevisions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 31, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var source = Evidence(id: "s1", sourceId: "source", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "source")
        try store.put(source, now: now)
        var dependent = source; dependent.id = "d1"; dependent.sourceId = "derived"; dependent.provenance = "derived"; dependent.appId = "b"; dependent.dependencies = [.init(sourceId: "source", revision: "1")]
        try store.put(dependent, now: now)
        source.id = "s2"; source.revision = "2"; source.expiresAtMs = now + 120000
        try store.put(source, now: now)
        XCTAssertEqual(try store.revisions(source: "derived", now: now).count, 1)
        XCTAssertFalse(try store.history(now: now).contains { $0.id == "d1" })
        try store.put(source, now: now + 1000)
        XCTAssertEqual(try store.revisions(source: "source", now: now + 60001).count, 1)
        try store.purgeApp("a")
        XCTAssertTrue(try store.revisions(source: "source", now: now).isEmpty)
        XCTAssertTrue(try store.revisions(source: "derived", now: now).isEmpty)
    }

    func testDeletionTombstonesSurviveRestartAndAllowNewRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 37, count: 32)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var source = Evidence(id: "source-1", sourceId: "source", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "original")
        do {
            let store = try ContextStore(directory: directory, key: key)
            XCTAssertTrue(try store.put(source, now: now))
            source.id = "source-2"; source.revision = "2"
            XCTAssertTrue(try store.put(source, now: now))
            try store.deleteSource("source")
        }
        let store = try ContextStore(directory: directory, key: key)
        XCTAssertFalse(try store.put(source, now: now))
        source.id = "source-1"; source.revision = "1"
        XCTAssertFalse(try store.put(source, now: now))
        source.id = "source-3"; source.revision = "3"
        XCTAssertTrue(try store.put(source, now: now))
        try store.clear(now: now)
        XCTAssertFalse(try store.put(source, now: now))
        XCTAssertTrue(try store.history(now: now).isEmpty)
    }

    func testSavedOnlyHistoryFindsOlderReferencesOutsideRecentPage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 41, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try store.put(Evidence(id: "old-pin", sourceId: "old-pin", revision: "1", provenance: "authored", appId: "a", capturedAtMs: now - 100000, expiresAtMs: now + 60000, text: "older explicit reference"), now: now)
        try store.save(id: "old-pin", saved: true)
        for i in 0..<110 {
            try store.put(Evidence(id: "recent-\(i)", sourceId: "recent-\(i)", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "recent"), now: now)
        }
        XCTAssertFalse(try store.history(now: now).contains { $0.id == "old-pin" })
        XCTAssertEqual(try store.history(savedOnly: true, now: now).map(\.id), ["old-pin"])
        XCTAssertFalse(try store.history(savedOnly: false, now: now).contains { $0.id == "old-pin" })
        XCTAssertTrue(try store.history(appId: "b", savedOnly: true, now: now).isEmpty)
    }

    func testPendingEmbeddingsOnlyCurrentRetainedMissingVectors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ContextStore(directory: directory, key: Data(repeating: 43, count: 32))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for i in 0..<40 {
            try store.put(Evidence(id: "item-\(i)", sourceId: "source-\(i)", revision: "1", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 60000, text: "pending"), now: now)
        }
        XCTAssertEqual(try store.pendingEmbeddings(limit: 100, now: now).count, 32)
        try store.embed(id: "item-0", revision: "1", vector: Array(repeating: 1, count: 768))
        XCTAssertFalse(try store.pendingEmbeddings(limit: 32, now: now).contains { $0.id == "item-0" })
        try store.save(id: "item-1", saved: true)
        XCTAssertEqual(try store.pendingEmbeddings(limit: 1, now: now).first?.id, "item-1")
        XCTAssertEqual(try store.pendingEmbeddings(limit: 32, now: now + 60001).map(\.id), ["item-1"])
        let newRevision = Evidence(id: "new", sourceId: "source-1", revision: "2", provenance: "observed", appId: "a", capturedAtMs: now, expiresAtMs: now + 120000, text: "latest")
        try store.put(newRevision, now: now)
        XCTAssertEqual(try store.pendingEmbeddings(now: now).map(\.id), ["new"])
    }

}
