import XCTest
import AppKit
import ImageIO
@testable import ContextServiceCore

final class OCRTests: XCTestCase {
    func testRejectsInvalidNonJPEGAndOversizeImages() throws {
        XCTAssertThrowsError(try ContextOCR.recognize(imageBase64: "not base64"))
        XCTAssertThrowsError(try ContextOCR.recognize(imageBase64: String(repeating: "A", count: 2_800_001)))
        XCTAssertThrowsError(try ContextOCR.recognize(imageBase64: image(width: 100, height: 100, type: "public.png").base64EncodedString()))
        XCTAssertThrowsError(try ContextOCR.recognize(imageBase64: image(width: 2049, height: 16).base64EncodedString()))
    }
    func testRecognizesSyntheticJPEGEntirelyInMemory() throws {
        let bytes = try image(width: 600, height: 180, text: "OCR CONTEXT TEST")
        let text = try ContextOCR.recognize(imageBase64: bytes.base64EncodedString())
        XCTAssertTrue(text.uppercased().contains("CONTEXT"))
        XCTAssertLessThanOrEqual(text.utf16.count, 12000)
    }
    private func image(width: Int, height: Int, type: String = "public.jpeg", text: String? = nil) throws -> Data {
        let pixels = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let context = NSGraphicsContext(cgContext: pixels, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        if let text { (text as NSString).draw(at: NSPoint(x: 25, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]) }
        NSGraphicsContext.restoreGraphicsState()
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(pixels.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
