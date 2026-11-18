import Foundation
import XCTest
@testable import AutocompleteHelper

final class NotesTextInserterTests: XCTestCase {
    func testTextEditUsesTheSameVerifiedInsertionContract() {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.apple.TextEdit",
            textBefore: "Draft"
        )
        let final = Self.snapshot(
            applicationBundleIdentifier: "com.apple.TextEdit",
            textBefore: "Draft continues"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(final)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster()
        )

        XCTAssertEqual(
            inserter.insert(" continues", expectedSnapshot: initial),
            .inserted(method: .accessibility, snapshot: final)
        )
    }

    func testSafariTextareaUsesVerifiedSyntheticUnicodeInsteadOfWebKitAXWrite() {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            textBefore: "Draft"
        )
        let final = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            textBefore: "Draft continues"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(initial), .captured(final)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster(result: true)
        )

        XCTAssertEqual(
            inserter.insert(" continues", expectedSnapshot: initial),
            .inserted(method: .syntheticUnicode, snapshot: final)
        )
        XCTAssertEqual(accessibility.insertedTexts, [])
    }

    func testChromeUsesVerifiedSyntheticUnicodeInsteadOfAXWrite() {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.google.Chrome",
            surface: .web,
            textBefore: "Draft"
        )
        let final = Self.snapshot(
            applicationBundleIdentifier: "com.google.Chrome",
            surface: .web,
            textBefore: "Draft continues"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(initial), .captured(final)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster(result: true)
        )

        XCTAssertEqual(
            inserter.insert(" continues", expectedSnapshot: initial),
            .inserted(method: .syntheticUnicode, snapshot: final)
        )
        XCTAssertEqual(accessibility.insertedTexts, [])
    }

    func testPreparedSafariInsertionRevalidatesImmediatelyBeforePosting() throws {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            textBefore: "Draft"
        )
        let final = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            textBefore: "Draft continues"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(initial), .captured(final)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster(result: true)
        )

        guard case let .prepared(prepared) = inserter.prepare(for: initial) else {
            return XCTFail("Expected a prepared Safari insertion")
        }
        XCTAssertEqual(accessibility.captureCount, 1)
        XCTAssertEqual(
            inserter.insert(" continues", prepared: prepared),
            .inserted(method: .syntheticUnicode, snapshot: final)
        )
        XCTAssertEqual(accessibility.captureCount, 3)
    }

    func testPreparedSafariInsertionRejectsFocusChangedAfterPreflight() {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            textBefore: "Draft"
        )
        let changedFocus = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            textBefore: "Other field",
            focusGeneration: 2,
            elementIdentifier: "safari-field-2",
            captureSequence: 2
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(changedFocus)],
            attempt: .inserted
        )
        let poster = FakeUnicodeTextPoster(result: true)
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: poster
        )

        guard case let .prepared(prepared) = inserter.prepare(for: initial) else {
            return XCTFail("Expected a prepared Safari insertion")
        }

        XCTAssertEqual(
            inserter.insert(" continues", prepared: prepared),
            .staleField
        )
        XCTAssertEqual(poster.postedTexts, [])
    }

    func testPreparedSafariInsertionRejectsUnavailableFieldAfterPreflight() {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.apple.Safari",
            surface: .web,
            textBefore: "Draft"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [
                .captured(initial),
                .skipped(.accessibilityUnavailable),
            ],
            attempt: .inserted
        )
        let poster = FakeUnicodeTextPoster(result: true)
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: poster
        )

        guard case let .prepared(prepared) = inserter.prepare(for: initial) else {
            return XCTFail("Expected a prepared Safari insertion")
        }

        XCTAssertEqual(
            inserter.insert(" continues", prepared: prepared),
            .fieldUnavailable
        )
        XCTAssertEqual(poster.postedTexts, [])
    }

    func testAccessibilityInsertionPreservesUnicodeAndPlacesCaretAfterSuggestion() {
        let suggestions = [
            " simple",
            "\nmultiline\ntext",
            " 👋🏽✨",
            " café déjà vu",
            " 你好世界",
            " שלום עולם",
        ]

        for suggestion in suggestions {
            let initial = Self.snapshot(textBefore: "Start:", textAfter: " end")
            let final = Self.snapshot(
                textBefore: "Start:" + suggestion,
                textAfter: " end"
            )
            let accessibility = FakeNotesInsertionAccessibility(
                captures: [.captured(initial), .captured(final)],
                attempt: .inserted
            )
            let poster = FakeUnicodeTextPoster()
            let inserter = NotesTextInserter(
                accessibility: accessibility,
                unicodePoster: poster
            )

            XCTAssertEqual(
                inserter.insert(suggestion, expectedSnapshot: initial),
                .inserted(method: .accessibility, snapshot: final)
            )
            XCTAssertEqual(accessibility.insertedTexts, [suggestion])
            XCTAssertEqual(poster.postedTexts, [])
        }
    }

    func testRejectsNonCollapsedSelectionInTheMVP() {
        let initial = Self.snapshot(
            textBefore: "Hello ",
            selectedText: "old",
            textAfter: " text"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster()
        )

        XCTAssertEqual(
            inserter.insert("new", expectedSnapshot: initial),
            .unsupportedSelection
        )
        XCTAssertEqual(accessibility.insertedTexts, [])
    }

    func testVerificationUsesTheBoundedGraphemeSafeTextBeforeSuffix() {
        let suggestion = "👋🏽"
        let initial = Self.snapshot(
            textBefore: String(repeating: "a", count: 8_000),
            selectionLocation: 10_000
        )
        let final = Self.snapshot(
            textBefore: String(repeating: "a", count: 7_996) + suggestion,
            selectionLocation: 10_000 + suggestion.utf16.count
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(final)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster()
        )

        XCTAssertEqual(
            inserter.insert(suggestion, expectedSnapshot: initial),
            .inserted(method: .accessibility, snapshot: final)
        )
    }

    func testRejectsStaleFocusBeforeWriting() {
        let expected = Self.snapshot(textBefore: "Original")
        let changedFocus = Self.snapshot(
            textBefore: "Original",
            focusGeneration: 2,
            elementIdentifier: "notes-field-2"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(changedFocus)],
            attempt: .inserted
        )
        let poster = FakeUnicodeTextPoster()
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: poster
        )

        XCTAssertEqual(
            inserter.insert(" continuation", expectedSnapshot: expected),
            .staleField
        )
        XCTAssertEqual(accessibility.insertedTexts, [])
        XCTAssertEqual(poster.postedTexts, [])
    }

    func testRejectsChangedContentBeforeWriting() {
        let expected = Self.snapshot(textBefore: "Original")
        let changedContent = Self.snapshot(textBefore: "Original changed")
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(changedContent)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster()
        )

        XCTAssertEqual(
            inserter.insert(" continuation", expectedSnapshot: expected),
            .staleField
        )
        XCTAssertEqual(accessibility.insertedTexts, [])
    }

    func testCorrectedSourceWithUnchangedDraftRejectsInsertionBeforeWriting() {
        func context(_ text: String) -> ActiveFieldContext {
            .init(shape: .multiline, sources: [.init(id: "same", containerId: "chat", relation: .sharedContainer, text: text)])
        }
        let expected = Self.snapshot(textBefore: "Yes", fieldContext: context("Tuesday"))
        let revised = Self.snapshot(textBefore: "Yes", fieldContext: context("Correction: Friday"))
        let accessibility = FakeNotesInsertionAccessibility(captures: [.captured(revised)], attempt: .inserted)
        let inserter = NotesTextInserter(accessibility: accessibility, unicodePoster: FakeUnicodeTextPoster())
        XCTAssertEqual(inserter.insert(", Tuesday works.", expectedSnapshot: expected), .staleField)
        XCTAssertTrue(accessibility.insertedTexts.isEmpty)
    }

    func testRecipientChangeWithUnchangedBodyRejectsInsertionBeforeWriting() {
        let expected = Self.snapshot(textBefore: "Original", fieldContext: .init(shape: .multiline, relatedFields: [.init(shape: .singleLine, label: "To", placeholder: nil, text: "Dana")]))
        let revised = Self.snapshot(textBefore: "Original", fieldContext: .init(shape: .multiline, relatedFields: [.init(shape: .singleLine, label: "To", placeholder: nil, text: "Lucía")]))
        let accessibility = FakeNotesInsertionAccessibility(captures: [.captured(revised)], attempt: .inserted)
        let inserter = NotesTextInserter(accessibility: accessibility, unicodePoster: FakeUnicodeTextPoster())
        XCTAssertEqual(inserter.insert(" continuation", expectedSnapshot: expected), .staleField)
        XCTAssertEqual(accessibility.insertedTexts, [])
    }

    func testUsesSyntheticUnicodeOnlyWhenAccessibilityIsUnsupported() {
        let initial = Self.snapshot(textBefore: "Start")
        let final = Self.snapshot(textBefore: "Start 👋🏽")
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(initial), .captured(final)],
            attempt: .unsupported
        )
        let poster = FakeUnicodeTextPoster(result: true)
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: poster
        )

        XCTAssertEqual(
            inserter.insert(" 👋🏽", expectedSnapshot: initial),
            .inserted(method: .syntheticUnicode, snapshot: final)
        )
        XCTAssertEqual(poster.postedTexts, [" 👋🏽"])
    }

    func testDoesNotFallbackAfterAccessibilityWriteFailure() {
        let initial = Self.snapshot(textBefore: "Start")
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial)],
            attempt: .failed
        )
        let poster = FakeUnicodeTextPoster(result: true)
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: poster
        )

        XCTAssertEqual(
            inserter.insert(" text", expectedSnapshot: initial),
            .writeFailed
        )
        XCTAssertEqual(poster.postedTexts, [])
    }

    func testReadinessRequiresAccessibilityOrPreflightedSyntheticEvents() {
        let initial = Self.snapshot(textBefore: "Start")
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(initial)],
            attempt: .unsupported
        )
        let unavailablePoster = FakeUnicodeTextPoster(isAvailable: false)
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: unavailablePoster
        )

        XCTAssertEqual(
            inserter.readiness(for: initial),
            .safeMethodUnavailable
        )
        XCTAssertEqual(
            inserter.insert(" text", expectedSnapshot: initial),
            .safeMethodUnavailable
        )
        XCTAssertEqual(unavailablePoster.postedTexts, [])
    }

    func testReadinessReportsThePreferredSafeMethod() {
        let initial = Self.snapshot(textBefore: "Start")
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(initial)],
            attempt: .inserted
        )
        let poster = FakeUnicodeTextPoster(isAvailable: true)
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: poster
        )

        XCTAssertEqual(inserter.readiness(for: initial), .ready(.accessibility))

        accessibility.attempt = .unsupported
        XCTAssertEqual(inserter.readiness(for: initial), .ready(.syntheticUnicode))
    }

    func testReadinessRejectsUnavailableMovedOrOlderLiveGeometry() {
        let expected = Self.snapshot(
            textBefore: "Start",
            caretBounds: CGRect(x: 10, y: 20, width: 1, height: 18),
            geometryQuality: .exact,
            geometrySource: .zeroLengthRange,
            captureSequence: 3
        )
        let unavailable = Self.snapshot(
            textBefore: "Start",
            caretBounds: nil,
            geometryQuality: .unavailable,
            geometrySource: nil,
            captureSequence: 4
        )
        let moved = Self.snapshot(
            textBefore: "Start",
            caretBounds: CGRect(x: 40, y: 20, width: 1, height: 18),
            geometryQuality: .exact,
            geometrySource: .zeroLengthRange,
            captureSequence: 4
        )
        let older = Self.snapshot(
            textBefore: "Start",
            caretBounds: CGRect(x: 10, y: 20, width: 1, height: 18),
            geometryQuality: .exact,
            geometrySource: .zeroLengthRange,
            captureSequence: 2
        )

        for live in [unavailable, moved, older] {
            let inserter = NotesTextInserter(
                accessibility: FakeNotesInsertionAccessibility(
                    captures: [.captured(live)],
                    attempt: .inserted
                ),
                unicodePoster: FakeUnicodeTextPoster()
            )
            XCTAssertEqual(inserter.readiness(for: expected), .staleField)
        }
    }

    func testReadinessRejectsLiveGeometryProvenanceMismatch() {
        let expected = Self.snapshot(
            textBefore: "Start",
            caretBounds: CGRect(x: 10, y: 20, width: 1, height: 18),
            geometryQuality: .exact,
            geometrySource: .zeroLengthRange,
            captureSequence: 3
        )
        let live = Self.snapshot(
            textBefore: "Start",
            caretBounds: CGRect(x: 10, y: 20, width: 1, height: 18),
            geometryQuality: .derived,
            geometrySource: .precedingGrapheme,
            captureSequence: 4
        )
        let inserter = NotesTextInserter(
            accessibility: FakeNotesInsertionAccessibility(
                captures: [.captured(live)],
                attempt: .inserted
            ),
            unicodePoster: FakeUnicodeTextPoster()
        )

        XCTAssertEqual(inserter.readiness(for: expected), .staleField)
    }

    func testReportsVerificationFailureWhenPostInsertionSnapshotDoesNotMatch() {
        let initial = Self.snapshot(textBefore: "Start")
        let unchanged = Self.snapshot(textBefore: "Start")
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(unchanged)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster()
        )

        XCTAssertEqual(
            inserter.insert(" text", expectedSnapshot: initial),
            .verificationFailed
        )
    }

    func testRetriesOnlyVerificationReadsUntilNotesReflectsTheInsertion() {
        let initial = Self.snapshot(textBefore: "Start")
        let unchanged = Self.snapshot(textBefore: "Start")
        let final = Self.snapshot(textBefore: "Start text")
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(unchanged), .captured(final)],
            attempt: .inserted
        )
        var delayCount = 0
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster(),
            verificationAttempts: 2,
            verificationDelay: { delayCount += 1 }
        )

        XCTAssertEqual(
            inserter.insert(" text", expectedSnapshot: initial),
            .inserted(method: .accessibility, snapshot: final)
        )
        XCTAssertEqual(accessibility.insertedTexts, [" text"])
        XCTAssertEqual(delayCount, 1)
    }

    func testDefaultVerificationBudgetAllowsDelayedWebAccessibilityPublication() {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.google.Chrome",
            surface: .web,
            textBefore: "Draft"
        )
        let unchanged = initial
        let final = Self.snapshot(
            applicationBundleIdentifier: "com.google.Chrome",
            surface: .web,
            textBefore: "Draft continues"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [
                .captured(initial),
                .captured(initial),
                .captured(unchanged),
                .captured(unchanged),
                .captured(unchanged),
                .captured(unchanged),
                .captured(unchanged),
                .captured(final),
            ],
            attempt: .inserted
        )
        var delayCount = 0
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster(result: true),
            verificationDelay: { delayCount += 1 }
        )

        XCTAssertEqual(
            inserter.insert(" continues", expectedSnapshot: initial),
            .inserted(method: .syntheticUnicode, snapshot: final)
        )
        XCTAssertEqual(delayCount, 5)
    }

    func testVerificationAcceptsEquivalentNonBreakingSpaceNormalization() {
        let initial = Self.snapshot(
            applicationBundleIdentifier: "com.google.Chrome",
            surface: .web,
            textBefore: "Draft\u{00A0}"
        )
        let final = Self.snapshot(
            applicationBundleIdentifier: "com.google.Chrome",
            surface: .web,
            textBefore: "Draft continues"
        )
        let accessibility = FakeNotesInsertionAccessibility(
            captures: [.captured(initial), .captured(initial), .captured(final)],
            attempt: .inserted
        )
        let inserter = NotesTextInserter(
            accessibility: accessibility,
            unicodePoster: FakeUnicodeTextPoster(result: true)
        )

        XCTAssertEqual(
            inserter.insert("continues", expectedSnapshot: initial),
            .inserted(method: .syntheticUnicode, snapshot: final)
        )
    }

    func testRejectsUnavailableOrSecureFields() {
        for reason in [
            ActiveFieldSkipReason.accessibilityUnavailable,
            .unsupportedApplication,
            .unsupportedRole,
            .secureField,
            .valueMissing,
            .rangeMissing,
            .rangeOutOfBounds,
            .markerReadFailed,
        ] {
            let accessibility = FakeNotesInsertionAccessibility(
                captures: [.skipped(reason)],
                attempt: .inserted
            )
            let inserter = NotesTextInserter(
                accessibility: accessibility,
                unicodePoster: FakeUnicodeTextPoster()
            )

            XCTAssertEqual(
                inserter.insert(" text", expectedSnapshot: Self.snapshot(textBefore: "Start")),
                .fieldUnavailable
            )
        }
    }

    func testExplicitReplacementSupportsSelectionWithoutCaretGeometry() {
        let initial = Self.snapshot(textBefore: "Hi ", selectedText: "old", textAfter: "!", caretBounds: nil, geometryQuality: .unavailable)
        let final = Self.snapshot(textBefore: "Hi new 👋", textAfter: "!")
        let accessibility = FakeNotesInsertionAccessibility(captures: [.captured(initial), .captured(final)], attempt: .inserted)
        let inserter = NotesTextInserter(accessibility: accessibility, unicodePoster: FakeUnicodeTextPoster())
        guard case let .prepared(prepared) = inserter.prepareReplacement(for: initial) else {
            return XCTFail("A complete selected range should be replaceable")
        }
        XCTAssertEqual(inserter.insert("new 👋", prepared: prepared), .inserted(method: .accessibility, snapshot: final))
    }

    func testReplacementAllowsSourceTextUpdatesButRejectsAChangedConversation() {
        func context(_ text: String, container: String = "chat") -> ActiveFieldContext {
            .init(shape: .multiline, sources: [.init(id: "same", containerId: container, relation: .sharedContainer, text: text)])
        }
        let expected = Self.snapshot(textBefore: "Yes", selectedText: " Tuesday", fieldContext: context("Tuesday"))
        let revised = Self.snapshot(textBefore: "Yes", selectedText: " Tuesday", fieldContext: context("Friday"))
        let anotherChat = Self.snapshot(textBefore: "Yes", selectedText: " Tuesday", fieldContext: context("Friday", container: "other-chat"))
        let accessibility = FakeNotesInsertionAccessibility(captures: [.captured(revised), .captured(anotherChat)], attempt: .inserted)
        let inserter = NotesTextInserter(accessibility: accessibility, unicodePoster: FakeUnicodeTextPoster())
        guard case .prepared = inserter.prepareReplacement(for: expected) else {
            return XCTFail("A selected-text rewrite does not use the surrounding source text")
        }
        XCTAssertEqual(inserter.prepareReplacement(for: expected), .staleField)
        XCTAssertTrue(accessibility.insertedTexts.isEmpty)
    }

    func testReplacementRejectsTruncatedSelectionAndFocusChanges() {
        let initial = Self.snapshot(textBefore: "Hi ", selectedText: "old")
        let changed = Self.snapshot(textBefore: "Hi ", selectedText: "old", focusGeneration: 2)
        let accessibility = FakeNotesInsertionAccessibility(captures: [.captured(changed)], attempt: .inserted)
        let inserter = NotesTextInserter(accessibility: accessibility, unicodePoster: FakeUnicodeTextPoster())
        XCTAssertEqual(inserter.prepareReplacement(for: initial), .staleField)
        XCTAssertEqual(inserter.prepareReplacement(for: Self.snapshot(textBefore: "Hi")), .unsupportedSelection)
        XCTAssertEqual(accessibility.insertedTexts, [])
    }

    private static func snapshot(
        applicationBundleIdentifier: String = "com.apple.Notes",
        surface: WritingSurface = .native,
        textBefore: String,
        selectedText: String = "",
        textAfter: String = "",
        focusGeneration: UInt64 = 1,
        elementIdentifier: String = "notes-field-1",
        selectionLocation: Int? = nil,
        caretBounds: CGRect? = CGRect(x: 10, y: 20, width: 1, height: 18),
        geometryQuality: GeometryQuality = .exact,
        geometrySource: CaretGeometrySource? = .zeroLengthRange,
        captureSequence: UInt64 = 1,
        fieldContext: ActiveFieldContext? = nil
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: applicationBundleIdentifier,
            surface: surface,
            elementIdentifier: elementIdentifier,
            focusGeneration: focusGeneration,
            textBefore: textBefore,
            selectedText: selectedText,
            textAfter: textAfter,
            selectionRange: NSRange(
                location: selectionLocation ?? textBefore.utf16.count,
                length: selectedText.utf16.count
            ),
            caretBounds: caretBounds,
            geometryQuality: geometryQuality,
            geometrySource: geometrySource,
            captureSequence: captureSequence,
            fieldContext: fieldContext
        )
    }
}

private final class FakeNotesInsertionAccessibility: NotesInsertionAccessibility {
    private var captures: [ActiveFieldCaptureResult]
    var attempt: AccessibilityInsertionAttempt
    private(set) var insertedTexts: [String] = []
    private(set) var captureCount = 0

    init(
        captures: [ActiveFieldCaptureResult],
        attempt: AccessibilityInsertionAttempt
    ) {
        self.captures = captures
        self.attempt = attempt
    }

    func capture() -> ActiveFieldCaptureResult {
        captureCount += 1
        if captures.count == 1 { return captures[0] }
        return captures.removeFirst()
    }

    func selectedTextInsertionIsSupported(
        expectedSnapshot: ActiveFieldSnapshot
    ) -> Bool {
        attempt != .unsupported
    }

    func insertSelectedText(
        _ text: String,
        expectedSnapshot: ActiveFieldSnapshot,
        isCurrent: () -> Bool
    ) -> AccessibilityInsertionAttempt {
        guard isCurrent() else { return .failed }
        insertedTexts.append(text)
        return attempt
    }
}

private final class FakeUnicodeTextPoster: UnicodeTextPosting {
    private let result: Bool
    let isAvailable: Bool
    private(set) var postedTexts: [String] = []

    init(result: Bool = false, isAvailable: Bool = true) {
        self.result = result
        self.isAvailable = isAvailable
    }

    func post(_ text: String) -> Bool {
        postedTexts.append(text)
        return result
    }
}
