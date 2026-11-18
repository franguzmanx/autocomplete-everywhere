import Foundation

/// Selects text boundaries only. It never rewrites, summarizes or guesses intent.
enum VisibleSuggestionPrefix {
    static func select(_ text: String, maximumUTF16Count: Int, protectedText: [String]) -> String? {
        guard maximumUTF16Count > 0 else { return nil }
        let value = text as NSString
        let whole = NSRange(location: 0, length: value.length)
        var protectedRanges: [NSRange] = []
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        protectedRanges += detector.matches(in: text, range: whole).map(\.range)
        for exact in protectedText where !exact.isEmpty {
            var search = whole
            while search.length > 0 {
                let found = value.range(of: exact, options: .literal, range: search)
                guard found.location != NSNotFound else { break }
                protectedRanges.append(found)
                let end = NSMaxRange(found)
                search = NSRange(location: end, length: value.length - end)
            }
        }
        var boundaries = Set<Int>()
        // Native word segmentation also handles scripts without spaces.
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            boundaries.insert(range.upperBound.utf16Offset(in: text))
        }
        // Keep punctuation and standalone emoji when the entire token fits.
        for index in text.indices {
            let end = text.index(after: index)
            if !text[index].isWhitespace && (end == text.endIndex || text[end].isWhitespace) {
                boundaries.insert(end.utf16Offset(in: text))
            }
        }
        let graphemeBoundaries = Set(text.indices.map { $0.utf16Offset(in: text) } + [value.length])
        let isAllowed: (Int) -> Bool = { boundary in
            boundary <= maximumUTF16Count && graphemeBoundaries.contains(boundary)
                && !protectedRanges.contains { $0.location < boundary && boundary < NSMaxRange($0) }
        }
        // Prefer complete words. When the remaining line cannot hold one,
        // an exact grapheme prefix still helps the author continue typing.
        // Links and artifact ranges remain indivisible.
        let end = boundaries.filter(isAllowed).max()
            ?? graphemeBoundaries.filter(isAllowed).max()
        guard let end else { return nil }
        let prefix = value.substring(to: end)
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prefix
    }
}
