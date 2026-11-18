import Foundation
import CryptoKit
import CSQLCipher

public struct Dependency: Codable, Equatable { public var sourceId: String; public var revision: String; public init(sourceId: String, revision: String) { self.sourceId = sourceId; self.revision = revision } }
public struct Evidence: Codable, Equatable {
    public var id: String; public var sourceId: String; public var revision: String
    public var provenance: String; public var appId: String
    public var accountId: String?; public var workspaceId: String?; public var resourceId: String?
    public var documentId: String?; public var conversationId: String?; public var url: String?
    public var capturedAtMs: Int64; public var expiresAtMs: Int64; public var text: String
    public var dependencies: [Dependency] = []
}
public enum StoreError: String, Error { case invalidInput, encryptionUnavailable, embeddingModelMismatch, databaseFailure, staleRevision, missingEvidence, keychainUnavailable, notOpen, ocrUnavailable }
public struct ContextAvailability: Codable { public var text: String; public var semantic: String }
public struct PreparedContext: Codable { public var evidence: [Evidence]; public var dependencies: [Dependency]; public var revision: String; public var availability: ContextAvailability }

public final class ContextStore {
    private var db: OpaquePointer?
    private var vectorIndex: VectorIndex?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let embeddingModel = "google/text-multilingual-embedding-002@vertex:768"
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    public init(directory: URL, key: Data) throws {
        encoder.outputFormatting = [.sortedKeys]
        guard key.count == 32 else { throw StoreError.encryptionUnavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("context.db").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw StoreError.databaseFailure }
        do {
            let status = key.withUnsafeBytes { sqlite3_key(db, $0.baseAddress, Int32($0.count)) }
            guard status == SQLITE_OK else { throw StoreError.encryptionUnavailable }
            guard !(try rows("PRAGMA cipher_version")).isEmpty else { throw StoreError.encryptionUnavailable }
            try execute("PRAGMA temp_store=MEMORY")
            // Use SQLCipher's default allocator: cryptographic memory remains locked/wiped,
            // while general SQLite allocations follow the same RAM lifecycle as Swift evidence/vectors.
            try execute("PRAGMA secure_delete=ON")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA foreign_keys=ON")
            sqlite3_busy_timeout(db, 3000)
            // Equal dimensions do not make vectors from different models comparable.
            // Bind the encrypted database once; never adopt an existing unbound index.
            try transaction {
                let hasMetadata = !(try rows("SELECT name FROM sqlite_master WHERE type='table' AND name='metadata'")).isEmpty
                if hasMetadata {
                    guard try rows("SELECT value FROM metadata WHERE key='embedding_model'").first?.first == Self.embeddingModel else { throw StoreError.embeddingModelMismatch }
                } else {
                    guard try rows("SELECT name FROM sqlite_master WHERE type='table' AND name='evidence'").isEmpty else { throw StoreError.embeddingModelMismatch }
                    try execute("CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                    try execute("INSERT INTO metadata(key,value) VALUES('embedding_model',?)", [Self.embeddingModel])
                }
            }
            try execute("CREATE TABLE IF NOT EXISTS evidence(id TEXT PRIMARY KEY, source TEXT NOT NULL UNIQUE, revision TEXT NOT NULL, app TEXT NOT NULL, document TEXT, conversation TEXT, url TEXT, captured INTEGER NOT NULL, expires INTEGER NOT NULL, saved INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL, vector BLOB)")
            try execute("CREATE TABLE IF NOT EXISTS revisions(source TEXT NOT NULL, revision TEXT NOT NULL, id TEXT NOT NULL, app TEXT NOT NULL, captured INTEGER NOT NULL, expires INTEGER NOT NULL, saved INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(source,revision))")
            try execute("CREATE TABLE IF NOT EXISTS revision_dependencies(source TEXT NOT NULL, revision TEXT NOT NULL, dependency_source TEXT NOT NULL, dependency_revision TEXT NOT NULL, PRIMARY KEY(source,revision,dependency_source), FOREIGN KEY(source,revision) REFERENCES revisions(source,revision) ON DELETE CASCADE)")
            try execute("CREATE INDEX IF NOT EXISTS revision_dependency_source ON revision_dependencies(dependency_source)")
            try execute("CREATE INDEX IF NOT EXISTS revision_app ON revisions(app)")
            try execute("CREATE INDEX IF NOT EXISTS revision_expiry ON revisions(saved,expires)")
            try execute("CREATE TABLE IF NOT EXISTS tombstones(source TEXT NOT NULL, revision TEXT NOT NULL, expires INTEGER NOT NULL, PRIMARY KEY(source,revision))")
            try execute("CREATE INDEX IF NOT EXISTS tombstone_expiry ON tombstones(expires)")
            try execute("CREATE TABLE IF NOT EXISTS dependencies(id TEXT NOT NULL REFERENCES evidence(id) ON DELETE CASCADE, source TEXT NOT NULL, revision TEXT NOT NULL)")
            try execute("CREATE INDEX IF NOT EXISTS dep_source ON dependencies(source)")
            try execute("CREATE INDEX IF NOT EXISTS evidence_expiry ON evidence(saved,expires)")
            try execute("CREATE INDEX IF NOT EXISTS evidence_unembedded ON evidence(saved DESC,captured DESC) WHERE vector IS NULL")
            try execute("CREATE INDEX IF NOT EXISTS evidence_recency ON evidence(captured DESC)")
            try execute("CREATE INDEX IF NOT EXISTS evidence_app ON evidence(app,captured DESC)")
            try execute("CREATE INDEX IF NOT EXISTS evidence_document ON evidence(document,captured DESC)")
            try execute("CREATE INDEX IF NOT EXISTS evidence_conversation ON evidence(conversation,captured DESC)")
            try execute("CREATE INDEX IF NOT EXISTS evidence_url ON evidence(url)")
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(id UNINDEXED,text, tokenize='unicode61')")
            try execute("INSERT INTO search(search,rank) VALUES('secure-delete',1)")
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func statement(_ sql: String, _ bindings: [String] = []) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else { throw StoreError.databaseFailure }
        for (i, value) in bindings.enumerated() { sqlite3_bind_text(pointer, Int32(i + 1), value, -1, Self.transient) }
        return pointer
    }
    private func execute(_ sql: String, _ bindings: [String] = []) throws {
        let s = try statement(sql, bindings); defer { sqlite3_finalize(s) }
        var result = sqlite3_step(s)
        while result == SQLITE_ROW { result = sqlite3_step(s) }
        guard result == SQLITE_DONE else { throw StoreError.databaseFailure }
    }
    private func rows(_ sql: String, _ bindings: [String] = []) throws -> [[String]] {
        let s = try statement(sql, bindings); defer { sqlite3_finalize(s) }
        var output: [[String]] = []
        var status = sqlite3_step(s)
        while status == SQLITE_ROW {
            output.append((0..<sqlite3_column_count(s)).map { i in sqlite3_column_text(s,i).map { String(cString:$0) } ?? "" })
            status = sqlite3_step(s)
        }
        guard status == SQLITE_DONE else { throw StoreError.databaseFailure }
        return output
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result } catch { vectorIndex = nil; try? execute("ROLLBACK"); throw error }
    }
    private func tombstone(source: String, revision: String, now: Int64) throws {
        try execute("INSERT INTO tombstones(source,revision,expires) VALUES(?,?,?) ON CONFLICT(source,revision) DO UPDATE SET expires=MAX(tombstones.expires,excluded.expires)",[source,revision,String(now + 30 * 86400000)])
    }
    private func removeCurrent(id: String) throws {
        try execute("DELETE FROM search WHERE id=?",[id]); try execute("DELETE FROM evidence WHERE id=?",[id]); vectorIndex?.remove(id)
    }
    private func removeSource(_ source: String, archive: Bool = false, now: Int64 = ContextStore.now) throws {
        // Source changes retain audit revisions, while explicit deletion removes the full live/archive dependency closure.
        let archiveEdges = archive ? "" : " UNION SELECT d.source FROM revision_dependencies d JOIN affected a ON d.dependency_source=a.source"
        let sources = try rows("WITH RECURSIVE affected(source) AS (SELECT ? UNION SELECT e.source FROM evidence e JOIN dependencies d ON d.id=e.id JOIN affected a ON d.source=a.source" + archiveEdges + ") SELECT source FROM affected",[source]).map { $0[0] }
        for source in sources {
            if archive {
                try execute("INSERT OR IGNORE INTO revisions(source,revision,id,app,captured,expires,saved,payload) SELECT source,revision,id,app,captured,expires,saved,payload FROM evidence WHERE source=?",[source])
                try execute("INSERT OR IGNORE INTO revision_dependencies SELECT e.source,e.revision,d.source,d.revision FROM evidence e JOIN dependencies d ON d.id=e.id WHERE e.source=?",[source])
            } else {
                for row in try rows("SELECT revision FROM evidence WHERE source=? UNION SELECT revision FROM revisions WHERE source=?",[source,source]) { try tombstone(source:source,revision:row[0],now:now) }
                try execute("DELETE FROM revisions WHERE source=?",[source])
            }
            for row in try rows("SELECT id FROM evidence WHERE source=?",[source]) { try removeCurrent(id:row[0]) }
        }
    }
    public func expire(now: Int64 = ContextStore.now) throws {
        try transaction {
            try execute("DELETE FROM tombstones WHERE expires<=?",[String(now)])
            for row in try rows("SELECT source FROM evidence WHERE saved=0 AND expires<=?",[String(now)]) {
                // Expiration retracts live dependents but preserves saved archived audit references.
                try removeSource(row[0],archive:true,now:now)
            }
            for row in try rows("SELECT source,revision FROM revisions WHERE saved=0 AND expires<=?",[String(now)]) {
                try tombstone(source:row[0],revision:row[1],now:now)
                try execute("DELETE FROM revisions WHERE source=? AND revision=?",[row[0],row[1]])
            }
        }
    }
    @discardableResult
    public func put(_ evidence: Evidence, now: Int64 = ContextStore.now) throws -> Bool {
        guard !evidence.id.isEmpty, !evidence.sourceId.isEmpty, !evidence.revision.isEmpty, !evidence.appId.isEmpty,
              ["authored","observed","derived"].contains(evidence.provenance), !evidence.text.isEmpty, evidence.text.utf16.count <= 16000,
              evidence.capturedAtMs >= 0, evidence.capturedAtMs <= now + 60000,
              evidence.expiresAtMs > evidence.capturedAtMs, evidence.dependencies.count <= 24,
              evidence.provenance != "derived" || !evidence.dependencies.isEmpty,
              Set(evidence.dependencies.map(\.sourceId)).count == evidence.dependencies.count,
              !evidence.dependencies.contains(where: { $0.sourceId == evidence.sourceId }) else { throw StoreError.invalidInput }
        let identities = [evidence.id,evidence.sourceId,evidence.revision,evidence.appId] + [evidence.accountId,evidence.workspaceId,evidence.resourceId,evidence.documentId,evidence.conversationId].compactMap { $0 } + evidence.dependencies.flatMap { [$0.sourceId,$0.revision] }
        guard identities.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 512 }), evidence.url == nil || (evidence.url!.utf16.count <= 2048 && URL(string:evidence.url!)?.scheme != nil) else { throw StoreError.invalidInput }
        var evidence = evidence
        evidence.expiresAtMs = min(evidence.expiresAtMs, evidence.capturedAtMs + 30 * 86400000)
        return try transaction {
            if !(try rows("SELECT 1 FROM tombstones WHERE source=? AND revision=? AND expires>? UNION SELECT 1 FROM revisions WHERE source=? AND revision=?",[evidence.sourceId,evidence.revision,String(now),evidence.sourceId,evidence.revision])).isEmpty { return false }
            var saved = "0"
            if let existing = try rows("SELECT revision,payload,saved FROM evidence WHERE source=?", [evidence.sourceId]).first {
                if existing[0] == evidence.revision { return false } // Same revision never renews retention or replaces content.
                let old = try decoder.decode(Evidence.self, from: Data(existing[1].utf8))
                guard evidence.capturedAtMs >= old.capturedAtMs else { throw StoreError.staleRevision }
                saved = existing[2]
                try removeSource(evidence.sourceId,archive:true,now:now)
            }
            for dependency in evidence.dependencies {
                guard let row = try rows("SELECT revision FROM evidence WHERE source=? AND (saved=1 OR expires>?)", [dependency.sourceId,String(now)]).first, row[0] == dependency.revision else { throw StoreError.staleRevision }
            }
            let payload = String(decoding: try encoder.encode(evidence), as: UTF8.self)
            try execute("INSERT INTO evidence(id,source,revision,app,document,conversation,url,captured,expires,payload,saved) VALUES(?,?,?,?,?,?,?,?,?,?,?)", [evidence.id,evidence.sourceId,evidence.revision,evidence.appId,evidence.documentId ?? "",evidence.conversationId ?? "",evidence.url ?? "",String(evidence.capturedAtMs),String(evidence.expiresAtMs),payload,saved])
            try execute("INSERT INTO search(id,text) VALUES(?,?)", [evidence.id,evidence.text])
            for dependency in evidence.dependencies { try execute("INSERT INTO dependencies VALUES(?,?,?)", [evidence.id,dependency.sourceId,dependency.revision]) }
            return true
        }
    }
    public func validate(_ dependencies: [Dependency], now: Int64 = ContextStore.now) throws -> Bool {
        try expire(now: now)
        guard dependencies.count <= 64 else { throw StoreError.invalidInput }
        for dependency in dependencies {
            guard let row = try rows("SELECT revision FROM evidence WHERE source=?",[dependency.sourceId]).first, row[0] == dependency.revision else { return false }
        }
        return true
    }
    public func save(id: String, saved: Bool) throws {
        try expire()
        try transaction {
            let sources = try rows("SELECT source FROM evidence WHERE id=? UNION SELECT source FROM revisions WHERE id=?",[id,id])
            guard !sources.isEmpty else { throw StoreError.missingEvidence }
            for row in sources {
                try execute("UPDATE evidence SET saved=? WHERE source=?",[saved ? "1":"0",row[0]])
                try execute("UPDATE revisions SET saved=? WHERE source=?",[saved ? "1":"0",row[0]])
            }
        }
    }

    private func decoded(_ row: [String]) throws -> Evidence {
        var evidence = try decoder.decode(Evidence.self,from:Data(row[0].utf8))
        // Pinning changes transport validity only; the original retention timestamp stays on disk.
        if row.count > 1 && row[1] == "1" { evidence.expiresAtMs = 9_007_199_254_740_991 }
        return evidence
    }
    public func savedIds() throws -> [String] { try rows("SELECT id FROM evidence WHERE saved=1 UNION SELECT id FROM revisions WHERE saved=1").map { $0[0] } }
    public func delete(id: String) throws { try transaction { for row in try rows("SELECT source FROM evidence WHERE id=? UNION SELECT source FROM revisions WHERE id=?",[id,id]) { try removeSource(row[0]) } } }
    public func deleteSource(_ source: String) throws { try transaction { try removeSource(source) } }
    public func purgeApp(_ app: String) throws { try transaction { for row in try rows("SELECT source FROM evidence WHERE app=? UNION SELECT source FROM revisions WHERE app=?",[app,app]) { try removeSource(row[0]) } } }
    public func clear(now: Int64 = ContextStore.now) throws {
        try transaction {
            let removable = try rows("WITH RECURSIVE keep(source) AS (SELECT source FROM evidence WHERE saved=1 UNION SELECT d.source FROM dependencies d JOIN evidence e ON e.id=d.id JOIN keep k ON e.source=k.source) SELECT id,source,revision FROM evidence WHERE source NOT IN (SELECT source FROM keep)")
            for row in removable { try tombstone(source:row[1],revision:row[2],now:now); try removeCurrent(id:row[0]) }
            for row in try rows("SELECT source,revision FROM revisions WHERE saved=0") {
                try tombstone(source:row[0],revision:row[1],now:now)
                try execute("DELETE FROM revisions WHERE source=? AND revision=?",[row[0],row[1]])
            }
        }
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
    public func revisions(source: String, limit: Int = 100, offset: Int = 0, now: Int64 = ContextStore.now) throws -> [Evidence] {
        try expire(now:now)
        return try rows("SELECT payload,saved FROM (SELECT payload,saved,captured,revision FROM evidence WHERE source=? UNION ALL SELECT payload,saved,captured,revision FROM revisions WHERE source=?) ORDER BY captured DESC,revision DESC LIMIT ? OFFSET ?",[source,source,String(max(1,min(limit,200))),String(max(0,offset))]).map { try decoded($0) }
    }
    public func history(appId: String? = nil, savedOnly: Bool? = nil, limit: Int = 100, offset: Int = 0, now: Int64 = ContextStore.now) throws -> [Evidence] {
        try expire(now: now)
        var clauses: [String] = []; var bindings: [String] = []
        if let appId { clauses.append("app=?"); bindings.append(appId) }
        if let savedOnly { clauses.append("saved=?"); bindings.append(savedOnly ? "1":"0") }
        let filter = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator:" AND ")
        return try rows("SELECT payload,saved FROM evidence" + filter + " ORDER BY captured DESC,id LIMIT ? OFFSET ?", bindings + [String(max(1,min(limit,200))),String(max(0,offset))]).map { try decoded($0) }
    }
    public func pendingEmbeddings(limit: Int = 32, now: Int64 = ContextStore.now) throws -> [Evidence] {
        try expire(now:now)
        return try rows("SELECT payload,saved FROM evidence WHERE vector IS NULL ORDER BY saved DESC,captured DESC,id LIMIT ?",[String(max(1,min(limit,32)))]).map { try decoded($0) }
    }
    public func embed(id: String, revision: String, vector: [Double]) throws {
        guard vector.count == 768, vector.allSatisfy(\.isFinite) else { throw StoreError.invalidInput }
        let floats = vector.map(Float.init)
        guard floats.allSatisfy(\.isFinite) else { throw StoreError.invalidInput }
        let s = try statement("UPDATE evidence SET vector=? WHERE id=? AND revision=?"); defer { sqlite3_finalize(s) }
        _ = floats.withUnsafeBytes { sqlite3_bind_blob(s,1,$0.baseAddress,Int32($0.count),Self.transient) }
        sqlite3_bind_text(s,2,id,-1,Self.transient); sqlite3_bind_text(s,3,revision,-1,Self.transient)
        guard sqlite3_step(s) == SQLITE_DONE else { throw StoreError.databaseFailure }
        guard sqlite3_changes(db) > 0 else { throw StoreError.staleRevision }
        if let vectorIndex, let row = try rows("SELECT payload FROM evidence WHERE id=?",[id]).first {
            let evidence = try decoded(row)
            vectorIndex.upsert(.init(id:id,appId:evidence.appId,documentId:evidence.documentId,conversationId:evidence.conversationId),vector:floats)
        }
    }
    private func loadedVectorIndex() throws -> VectorIndex {
        if let vectorIndex { return vectorIndex }
        let index = VectorIndex()
        let s = try statement("SELECT id,app,document,conversation,vector FROM evidence WHERE vector IS NOT NULL")
        defer { sqlite3_finalize(s) }
        var status = sqlite3_step(s)
        while status == SQLITE_ROW {
            defer { status = sqlite3_step(s) }
            guard sqlite3_column_bytes(s,4) == 768 * 4, let blob = sqlite3_column_blob(s,4) else { throw StoreError.databaseFailure }
            let bytes = UnsafeRawBufferPointer(start:blob,count:768*4)
            let vector = (0..<768).map { bytes.loadUnaligned(fromByteOffset:$0*4,as:Float.self) }
            let id = String(cString:sqlite3_column_text(s,0)); let app = String(cString:sqlite3_column_text(s,1))
            let document = sqlite3_column_text(s,2).map { String(cString:$0) }
            let conversation = sqlite3_column_text(s,3).map { String(cString:$0) }
            index.upsert(.init(id:id,appId:app,documentId:document,conversationId:conversation),vector:vector)
        }
        guard status == SQLITE_DONE else { throw StoreError.databaseFailure }
        vectorIndex = index
        return index
    }
    public func retrieve(query: String, embedding: [Double]? = nil, appId: String? = nil, documentId: String? = nil, conversationId: String? = nil, now: Int64 = ContextStore.now) throws -> PreparedContext {
        try expire(now: now)
        guard query.utf8.count <= 32000 else { throw StoreError.invalidInput }
        if let embedding { guard embedding.count == 768, embedding.allSatisfy(\.isFinite) else { throw StoreError.invalidInput } }
        var filter = "1=1"; var args: [String] = []
        if let appId { filter += " AND e.app=?"; args.append(appId) }
        if let documentId { filter += " AND e.document=?"; args.append(documentId) }
        if let conversationId { filter += " AND e.conversation=?"; args.append(conversationId) }
        var lists: [[String]] = []
        lists.append(try rows("SELECT e.id FROM evidence e WHERE " + filter + " ORDER BY e.captured DESC LIMIT 40",args).map { $0[0] })
        if !query.isEmpty {
            lists.append(try rows("SELECT e.id FROM evidence e WHERE " + filter + " AND (e.source=? OR e.id=? OR e.url=?) ORDER BY e.captured DESC LIMIT 40",args + [query,query,query]).map { $0[0] })
            let tokens = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(32)
            if !tokens.isEmpty {
                let match = tokens.map { "\"" + $0 + "\"" }.joined(separator:" OR ")
                let membership = args.isEmpty ? "" : " AND id IN (SELECT e.id FROM evidence e WHERE " + filter + ")"
                lists.append(try rows("SELECT id FROM search WHERE search MATCH ?" + membership + " ORDER BY rank LIMIT 40",[match] + args).map { $0[0] })
                if tokens.count > 1 {
                    let phrase = "\"" + tokens.joined(separator:" ") + "\""
                    lists.append(try rows("SELECT id FROM search WHERE search MATCH ?" + membership + " ORDER BY rank LIMIT 40",[phrase] + args).map { $0[0] })
                }
            }
        }
        if let embedding {
            lists.append(try loadedVectorIndex().nearest(embedding,appId:appId,documentId:documentId,conversationId:conversationId))
        }
        var scores: [String:Double] = [:]
        for list in lists { for (rank,id) in list.enumerated() { scores[id,default:0] += 1.0 / Double(60+rank+1) } }
        let ids = scores.keys.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0]! > scores[$1]! }.prefix(40)
        var output: [Evidence] = []; var bytes = 0; var dependencies: [String:String] = [:]
        for id in ids {
            guard output.count < 12, let row = try rows("SELECT payload,saved FROM evidence WHERE id=?",[id]).first else { continue }
            var evidence = try decoded(row)
            let remaining = 8000 - bytes
            if evidence.text.utf8.count > remaining {
                guard remaining > 0 else { continue }
                var prefix = Data(evidence.text.utf8.prefix(remaining))
                while String(data:prefix,encoding:.utf8) == nil { prefix.removeLast() }
                evidence.text = String(decoding:prefix,as:UTF8.self)
            }
            let refs = [Dependency(sourceId:evidence.sourceId,revision:evidence.revision)] + evidence.dependencies
            guard refs.allSatisfy({ dependencies[$0.sourceId] == nil || dependencies[$0.sourceId] == $0.revision }), Set(Array(dependencies.keys) + refs.map(\.sourceId)).count <= 64, bytes + evidence.text.utf8.count <= 8000 else { continue }
            bytes += evidence.text.utf8.count; output.append(evidence)
            for ref in refs { dependencies[ref.sourceId] = ref.revision }
        }
        let refs = dependencies.keys.sorted().map { Dependency(sourceId:$0,revision:dependencies[$0]!) }
        let revision = SHA256.hash(data:try encoder.encode(output)).map { String(format:"%02x",$0) }.joined()
        return PreparedContext(evidence:output,dependencies:refs,revision:revision,availability:ContextAvailability(text:"ready",semantic:embedding == nil ? "not_prepared" : "included"))
    }
}
