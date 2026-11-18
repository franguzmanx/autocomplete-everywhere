import Foundation
import XCTest
@testable import AutocompleteHelper

final class VisibleSuggestionPrefixTests: XCTestCase {
    func testPrefersWordsAndDoesNotSplitEmojiLinksOrExactArtifacts() {
        XCTAssertEqual(VisibleSuggestionPrefix.select(" hello world", maximumUTF16Count: 9, protectedText: []), " hello")
        XCTAssertEqual(VisibleSuggestionPrefix.select(" 👨‍👩‍👧‍👦 next", maximumUTF16Count: 5, protectedText: []), nil)
        XCTAssertEqual(VisibleSuggestionPrefix.select(" élan next", maximumUTF16Count: 3, protectedText: []), " é")
        XCTAssertEqual(VisibleSuggestionPrefix.select(" See https://example.com/long/path next", maximumUTF16Count: 22, protectedText: []), " See")
        XCTAssertEqual(VisibleSuggestionPrefix.select(" Use exact first\nsecond line", maximumUTF16Count: 16, protectedText: ["exact first\nsecond line"]), " Use")
        XCTAssertNil(VisibleSuggestionPrefix.select("exact first\nsecond line", maximumUTF16Count: 11, protectedText: ["exact first\nsecond line"]))
    }

    func testOffersStartOfLongWordWhenNoWholeWordFits() {
        XCTAssertEqual(VisibleSuggestionPrefix.select(" understanding", maximumUTF16Count: 6, protectedText: []), " under")
        XCTAssertNil(VisibleSuggestionPrefix.select(" https://example.com/long", maximumUTF16Count: 6, protectedText: []))
        XCTAssertNil(VisibleSuggestionPrefix.select(" exact-content", maximumUTF16Count: 6, protectedText: ["exact-content"]))
        XCTAssertNil(VisibleSuggestionPrefix.select("  next", maximumUTF16Count: 2, protectedText: []))
    }

    func testCJKCanEndAtNativeWordBoundaryAndKeepsExactPrefix() {
        let text = "你好世界。明天见。"
        let prefix = VisibleSuggestionPrefix.select(text, maximumUTF16Count: 5, protectedText: [])
        XCTAssertNotNil(prefix)
        XCTAssertTrue(text.hasPrefix(prefix ?? ""))
        XCTAssertLessThanOrEqual(prefix?.utf16.count ?? 99, 5)
    }
}
