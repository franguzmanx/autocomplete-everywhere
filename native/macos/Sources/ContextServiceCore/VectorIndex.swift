import Foundation
import Accelerate

/// Decrypted vectors live only in process memory. Persistence is exclusively SQLCipher.
final class VectorIndex {
    struct Item {
        var id: String
        var appId: String
        var documentId: String?
        var conversationId: String?
    }
    private var items: [Item?] = []
    private var freeSlots: [Int] = []
    private var positions: [String:Int] = [:]
    private var vectors: [Float] = []
    private let dimensions = 768
    func upsert(_ item: Item, vector: [Float]) {
        var normalized = vector
        var squared: Float = 0
        vDSP_svesq(vector, 1, &squared, vDSP_Length(dimensions))
        if squared > 0 { var scale = 1 / sqrt(squared); vDSP_vsmul(vector, 1, &scale, &normalized, 1, vDSP_Length(dimensions)) }
        if let offset = positions[item.id] {
            items[offset] = item
            vectors.replaceSubrange(offset * dimensions..<(offset + 1) * dimensions, with: normalized)
        } else if let offset = freeSlots.popLast() {
            positions[item.id] = offset; items[offset] = item
            vectors.replaceSubrange(offset * dimensions..<(offset + 1) * dimensions, with: normalized)
        } else {
            positions[item.id] = items.count; items.append(item); vectors.append(contentsOf: normalized)
        }
    }
    func remove(_ id: String) {
        guard let offset = positions.removeValue(forKey: id) else { return }
        items[offset] = nil; freeSlots.append(offset)
        vectors.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.advanced(by: offset * dimensions).update(repeating: 0, count: dimensions)
        }
    }
    func nearest(_ query: [Double], appId: String?, documentId: String?, conversationId: String?) -> [String] {
        guard !items.isEmpty else { return [] }
        let floats = query.map(Float.init)
        guard floats.allSatisfy(\.isFinite) else { return [] }
        var scores = [Float](repeating: 0, count: items.count)
        // All normalized vectors are contiguous: one optimized BLAS matrix/vector operation.
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(items.count), Int32(dimensions), 1,
                    vectors, Int32(dimensions), floats, 1, 0, &scores, 1)
        var best: [(String,Float)] = []
        best.reserveCapacity(41)
        for offset in items.indices {
            guard let item = items[offset], appId == nil || item.appId == appId,
                  documentId == nil || item.documentId == documentId,
                  conversationId == nil || item.conversationId == conversationId else { continue }
            let score = scores[offset]
            if best.count < 40 || score > best.last!.1 {
                best.append((item.id,score)); best.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
                if best.count > 40 { best.removeLast() }
            }
        }
        return best.map { $0.0 }
    }
}
