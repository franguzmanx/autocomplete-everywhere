import Foundation
import ImageIO
import Vision

public enum ContextOCR {
    /// JPEG evidence stays in process memory; neither the image nor recognition diagnostics are persisted.
    public static func recognize(imageBase64: String) throws -> String {
        guard !imageBase64.isEmpty, imageBase64.utf8.count <= 2_800_000,
              let data = Data(base64Encoded:imageBase64),
              let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              CGImageSourceGetType(source).map({ $0 as String }) == "public.jpeg",
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 2048, height.intValue <= 2048,
              width.intValue * height.intValue <= 4_000_000,
              let image = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCache:false] as CFDictionary) else { throw StoreError.invalidInput }
        let orientationValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue:orientationValue) ?? .up
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage:image,orientation:orientation,options:[:]).perform([request]) }
        catch { throw StoreError.ocrUnavailable }
        let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n")
        var bounded = ""; var units = 0
        for scalar in recognized.unicodeScalars {
            let length = scalar.value > 0xffff ? 2 : 1
            guard units + length <= 12000 else { break }
            bounded.unicodeScalars.append(scalar); units += length
        }
        return bounded
    }
}
