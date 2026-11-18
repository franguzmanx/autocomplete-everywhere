import Foundation

/// Detects value edits within the same physical field, independent of input
/// method. Document-aligned overlap prevents caret/selection movement through a
/// bounded capture window from masquerading as editing. This is not authorship.
enum ObservedDraftMutation {
    static func changed(from old: ActiveFieldSnapshot, to new: ActiveFieldSnapshot) -> Bool {
        guard old.applicationBundleIdentifier == new.applicationBundleIdentifier,
              old.elementIdentifier == new.elementIdentifier,
              old.focusGeneration == new.focusGeneration,
              old.selectedText.utf16.count == old.selectionRange.length,
              new.selectedText.utf16.count == new.selectionRange.length else { return false }
        let oldText = old.textBefore + old.selectedText + old.textAfter
        let newText = new.textBefore + new.selectedText + new.textAfter
        let oldStart = old.selectionRange.location - old.textBefore.utf16.count
        let newStart = new.selectionRange.location - new.textBefore.utf16.count
        guard oldStart >= 0, newStart >= 0 else { return false }
        let oldEnd = oldStart + oldText.utf16.count
        let newEnd = newStart + newText.utf16.count
        let oldAtEnd = old.publicationStructure?.textAfterIsEmpty ?? old.textAfter.isEmpty
        let newAtEnd = new.publicationStructure?.textAfterIsEmpty ?? new.textAfter.isEmpty
        if oldAtEnd, newAtEnd, oldEnd != newEnd { return true }
        let overlapStart = max(oldStart, newStart)
        let overlapEnd = min(oldEnd, newEnd)
        guard overlapEnd > overlapStart,
              let oldRange = Range(NSRange(location: overlapStart - oldStart, length: overlapEnd - overlapStart), in: oldText),
              let newRange = Range(NSRange(location: overlapStart - newStart, length: overlapEnd - overlapStart), in: newText) else { return false }
        return oldText[oldRange] != newText[newRange]
    }
}
