import Foundation
import ContextServiceCore

struct Request: Decodable {
    let id: String
    let op: String
    var accountId: String?
    var evidence: Evidence?
    var evidenceId: String?
    var sourceId: String?
    var revision: String?
    var appId: String?
    var documentId: String?
    var conversationId: String?
    var query: String?
    var imageBase64: String?
    var embedding: [Double]?
    var dependencies: [Dependency]?
    var savedOnly: Bool?
    var saved: Bool?
    var limit: Int?
    var offset: Int?
}
let arguments = CommandLine.arguments
let root: URL = {
    if let i = arguments.firstIndex(of:"--root"), arguments.count > i + 1 { return URL(fileURLWithPath:arguments[i+1],isDirectory:true) }
    return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AutocompleteEverywhere/Context",isDirectory:true)
}()
var store: ContextStore?
var account: String?
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
func object<T:Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with:encoder.encode(value)) }
func required<T>(_ value: T?) throws -> T { guard let value else { throw StoreError.invalidInput }; return value }
@MainActor func handle(_ request: Request) throws -> Any {
    if request.op == "open" {
        store = nil; account = nil
        let id = try required(request.accountId)
        let key = try AccountKey.load(id)
        let opened = try ContextStore(directory:root.appendingPathComponent(AccountKey.directoryName(id)),key:key)
        try opened.expire()
        store = opened; account = id
        return ["accountId":id,"encrypted":true]
    }
    if request.op == "close" { store = nil; account = nil; return [:] as [String:String] }
    guard let store else { throw StoreError.notOpen }
    if let requested = request.accountId, requested != account { throw StoreError.invalidInput }
    switch request.op {
    case "ocr": return ["text":try ContextOCR.recognize(imageBase64:required(request.imageBase64))]
    case "put":
        let evidence = try required(request.evidence)
        return ["changed":try store.put(evidence)]
    case "pendingEmbeddings": return ["evidence":try object(store.pendingEmbeddings(limit:request.limit ?? 32))]
    case "revisions":
        return ["evidence":try object(store.revisions(source:required(request.sourceId),limit:request.limit ?? 100,offset:request.offset ?? 0)),"savedIds":try store.savedIds()]
    case "history":
        return ["evidence":try object(store.history(appId:request.appId,savedOnly:request.savedOnly,limit:request.limit ?? 100,offset:request.offset ?? 0)),"savedIds":try store.savedIds()]
    case "search":
        let context = try store.retrieve(query:request.query ?? "",appId:request.appId,documentId:request.documentId,conversationId:request.conversationId)
        return ["evidence":try object(context.evidence),"savedIds":try store.savedIds()]
    case "retrieve":
        return try object(store.retrieve(query:request.query ?? "",embedding:request.embedding,appId:request.appId,documentId:request.documentId,conversationId:request.conversationId))
    case "validate": return try store.validate(required(request.dependencies))
    case "save": try store.save(id:required(request.evidenceId),saved:required(request.saved))
    case "delete": try store.delete(id:required(request.evidenceId))
    case "deleteSource": try store.deleteSource(required(request.sourceId))
    case "purgeApp": try store.purgeApp(required(request.appId))
    case "clear": try store.clear()
    case "expire": try store.expire()
    case "embed": try store.embed(id:required(request.evidenceId),revision:required(request.revision),vector:required(request.embedding))
    default: throw StoreError.invalidInput
    }
    return [:] as [String:String]
}
// stdout is protocol only. Never print errors, keys, request bodies or contents.
while let line = readLine(strippingNewline:true) {
    var id = ""
    let response: [String:Any]
    do {
        guard line.utf8.count <= 4_000_000 else { throw StoreError.invalidInput }
        let request = try JSONDecoder().decode(Request.self,from:Data(line.utf8)); id = request.id
        guard !id.isEmpty, id.utf8.count <= 256 else { throw StoreError.invalidInput }
        response = ["id":id,"ok":true,"result":try handle(request)]
    } catch {
        response = ["id":id,"ok":false,"error":(error as? StoreError)?.rawValue ?? "invalidInput"]
    }
    if let data = try? JSONSerialization.data(withJSONObject:response,options:[.sortedKeys]) { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10])) }
}
