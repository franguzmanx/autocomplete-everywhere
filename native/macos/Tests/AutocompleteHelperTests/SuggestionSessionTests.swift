import Foundation
import XCTest
@testable import AutocompleteHelper

final class SuggestionSessionTests: XCTestCase {
    func testNextWordReservesExactPrefixAndKeepsRemainderAfterVerifiedInsertion() throws {
        let initial = Self.snapshot(textBefore: "Podemos reunirnos")
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" el jueves a las diez."))))

        let first = try XCTUnwrap(session.reserveAcceptance(
            visibleIdentity: message.identity, visibleText: " el jueves a las diez.",
            stabilizedSnapshot: initial, nextWordOnly: true
        ))
        XCTAssertEqual(first.text, " el ")
        XCTAssertEqual(first.remainingText, "jueves a las diez.")
        XCTAssertNil(session.presentation(for: message.identity))
        let afterFirst = Self.snapshot(textBefore: "Podemos reunirnos el ", captureSequence: 2)
        XCTAssertTrue(session.resumeAfterPartialAcceptance(first, snapshot: afterFirst))
        XCTAssertEqual(session.presentation(for: message.identity)?.text, "jueves a las diez.")

        let second = try XCTUnwrap(session.reserveAcceptance(
            visibleIdentity: message.identity, visibleText: "jueves a las diez.",
            stabilizedSnapshot: afterFirst, nextWordOnly: true
        ))
        XCTAssertEqual(second.text, "jueves ")
        let afterSecond = Self.snapshot(textBefore: "Podemos reunirnos el jueves ", captureSequence: 3)
        XCTAssertTrue(session.resumeAfterPartialAcceptance(second, snapshot: afterSecond))
        let rest = try XCTUnwrap(session.reserveAcceptance(
            visibleIdentity: message.identity, visibleText: "a las diez.", stabilizedSnapshot: afterSecond
        ))
        XCTAssertEqual(rest.text, "a las diez.")
        XCTAssertEqual(rest.remainingText, "")
        XCTAssertEqual(rest.typedThroughCharacters, 0, "Previously reported word acceptances must not be counted twice")
        XCTAssertTrue(rest.isPartialAcceptance)
    }

    func testWordAcceptancePreservesWhitespacePunctuationAndUnicodeClusters() throws {
        let examples = [
            ("  café, mañana", "  café, ", "mañana"),
            ("👩🏽‍💻 listo", "👩🏽‍💻 ", "listo"),
            ("e\u{301}xito total", "e\u{301}xito ", "total"),
            ("última.", "última.", ""),
            ("uno\n\tdos", "uno\n\t", "dos"),
        ]
        for (text, prefix, remainder) in examples {
            let snapshot = Self.snapshot(textBefore: "Hola")
            let message = Self.message(snapshot: snapshot)
            let session = SuggestionSession()
            session.begin(message, snapshot: snapshot)
            session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(text))))
            let reserved = try XCTUnwrap(session.reserveAcceptance(
                visibleIdentity: message.identity, visibleText: text, stabilizedSnapshot: snapshot, nextWordOnly: true
            ))
            XCTAssertEqual(reserved.text, prefix)
            XCTAssertEqual(reserved.remainingText, remainder)
        }
    }

    func testPartialAcceptanceCannotRestoreCancelledOrChangedField() throws {
        for cancel in [false, true] {
            let initial = Self.snapshot(textBefore: "Hola")
            let message = Self.message(snapshot: initial)
            let session = SuggestionSession()
            session.begin(message, snapshot: initial)
            session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" mundo feliz"))))
            let reserved = try XCTUnwrap(session.reserveAcceptance(
                visibleIdentity: message.identity, visibleText: " mundo feliz", stabilizedSnapshot: initial, nextWordOnly: true
            ))
            if cancel { session.dismiss() }
            let changed = Self.snapshot(textBefore: "Hola mundo ", focusGeneration: cancel ? 1 : 2, captureSequence: 2)
            XCTAssertFalse(session.resumeAfterPartialAcceptance(reserved, snapshot: changed))
            XCTAssertNil(session.presentation(for: message.identity))
        }
    }

    func testWordAcceptanceCannotRestoreRemainderAfterReplySourceChanges() throws {
        let initial = Self.snapshot(textBefore: "Reply", sources: [
            .init(id: "message", containerId: "chat", relation: .sharedContainer, text: "Tuesday")
        ])
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" Tuesday works."))))
        let reserved = try XCTUnwrap(session.reserveAcceptance(
            visibleIdentity: message.identity, visibleText: " Tuesday works.",
            stabilizedSnapshot: initial, nextWordOnly: true
        ))
        let changed = Self.snapshot(textBefore: "Reply Tuesday ", captureSequence: 2, sources: [
            .init(id: "message", containerId: "chat", relation: .sharedContainer, text: "Friday")
        ])
        XCTAssertFalse(session.resumeAfterPartialAcceptance(reserved, snapshot: changed))
        XCTAssertEqual(session.state, .idle)
    }

    func testSelectedVisiblePrefixIsTheOnlyAcceptableText() throws {
        let snapshot = Self.snapshot(textBefore: "Reply")
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" first line\nsecret remainder"))))
        XCTAssertTrue(session.selectVisiblePrefix(" first line", identity: message.identity))
        XCTAssertFalse(session.selectVisiblePrefix(" first line\nsecret remainder", identity: message.identity))
        XCTAssertFalse(session.selectVisiblePrefix("other", identity: message.identity))
        let reserved = session.reserveAcceptance(visibleIdentity: message.identity,
            visibleText: " first line", stabilizedSnapshot: snapshot)
        XCTAssertEqual(reserved?.text, " first line")
        session.completeAcceptance(identity: message.identity)
        XCTAssertNil(session.reserveAcceptance(visibleIdentity: message.identity,
            visibleText: " first line", stabilizedSnapshot: snapshot))
    }

    func testAcceptanceOfPartialWordContainsOnlyVisibleCharacters() throws {
        let snapshot = Self.snapshot(textBefore: "For")
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" understanding the result"))))
        XCTAssertTrue(session.selectVisiblePrefix(" under", identity: message.identity))
        XCTAssertFalse(session.selectVisiblePrefix(" understanding the result", identity: message.identity))
        XCTAssertEqual(session.reserveAcceptance(visibleIdentity: message.identity,
            visibleText: " under", stabilizedSnapshot: snapshot)?.text, " under")
    }

    func testExactLargeArtifactTransportRetainsEveryUTF16Unit() {
        let snapshot = Self.snapshot(textBefore: "Carry this")
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        let text = String(repeating: "界", count: 12_000)
        XCTAssertEqual(session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(text)))), .accepted)
        XCTAssertEqual(session.state, .ready(identity: message.identity, text: text, snapshot: snapshot))
    }

    func testChangedSourceTargetCancelsPendingAndVisibleSuggestionAndBlocksAcceptance() throws {
        let original = Self.snapshot(textBefore: "Reply", sources: [.init(id: "post", containerId: "group", relation: .sharedContainer, text: "Before")])
        let revised = Self.snapshot(textBefore: "Reply", sources: [.init(id: "different-post", containerId: "group", relation: .sharedContainer, text: "After")])
        for ready in [false, true] {
            let session = SuggestionSession()
            let message = Self.message(snapshot: original)
            session.begin(message, snapshot: original)
            if ready { _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes")))) }
            XCTAssertEqual(session.invalidate(with: revised)?.payload.reason, .contentChanged)
            XCTAssertEqual(session.state, .idle)
            XCTAssertEqual(session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" late")))), .ignoredStale)
            session.begin(message, snapshot: original)
            _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes"))))
            XCTAssertFalse(session.canAccept(visibleIdentity: message.identity, visibleText: " yes", stabilizedSnapshot: revised))
        }
    }

    func testCorrectedMessageWithReusedIdentityCannotAcceptOldAnswer() {
        let original = Self.snapshot(textBefore: "Yes", sources: [.init(id: "same-message", containerId: "same-chat", relation: .sharedContainer, text: "Delivery is Tuesday.")])
        let corrected = Self.snapshot(textBefore: "Yes", sources: [.init(id: "same-message", containerId: "same-chat", relation: .sharedContainer, text: "Correction: delivery is Friday.")])
        let session = SuggestionSession()
        let message = Self.message(snapshot: original)
        session.begin(message, snapshot: original)
        _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(", Tuesday works."))))
        XCTAssertFalse(session.canAccept(visibleIdentity: message.identity, visibleText: ", Tuesday works.", stabilizedSnapshot: corrected))
    }

    func testChangedSourceTargetCannotSurviveTypeThrough() {
        let original = Self.snapshot(textBefore: "Reply", sources: [.init(id: "post", containerId: "group", relation: .sharedContainer, text: "Before")])
        let revised = Self.snapshot(textBefore: "Reply y", sources: [.init(id: "different-post", containerId: "group", relation: .sharedContainer, text: "After")])
        let session = SuggestionSession()
        let message = Self.message(snapshot: original)
        session.begin(message, snapshot: original)
        _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes"))))
        _ = session.previewTypeThrough(" y")
        guard case .cancelled = session.reconcileTypeThrough(with: revised) else { return XCTFail("Changed source must cancel") }
    }

    func testSameSourceTextUpdateInvalidatesAcceptanceAndTypeThrough() {
        let original = Self.snapshot(textBefore: "Reply", sources: [.init(id: "post", containerId: "group", relation: .sharedContainer, text: "Before")])
        let updated = Self.snapshot(textBefore: "Reply", sources: [.init(id: "post", containerId: "group", relation: .sharedContainer, text: "Streaming update")])
        let typed = Self.snapshot(textBefore: "Reply y", sources: updated.fieldContext.sources)
        let session = SuggestionSession()
        let message = Self.message(snapshot: original)
        session.begin(message, snapshot: original)
        _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes"))))
        XCTAssertFalse(session.canAccept(visibleIdentity: message.identity, visibleText: " yes", stabilizedSnapshot: updated))
        session.begin(message, snapshot: original)
        _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes"))))
        _ = session.previewTypeThrough(" y")
        guard case .cancelled = session.reconcileTypeThrough(with: typed) else { return XCTFail("Revised evidence must cancel stale type-through") }
    }

    func testRecipientRevisionCancelsPendingVisibleAndTypeThroughWithUnchangedBody() {
        func context(_ recipient: String) -> ActiveFieldContext {
            ActiveFieldContext(shape: .multiline, relatedFields: [.init(shape: .singleLine, label: "To", placeholder: nil, text: recipient)])
        }
        let original = Self.snapshot(textBefore: "Reply", fieldContext: context("Dana"))
        let revised = Self.snapshot(textBefore: "Reply", fieldContext: context("Lucía"))
        XCTAssertNotEqual(original.contentSignature, revised.contentSignature)
        for ready in [false, true] {
            let session = SuggestionSession()
            let message = Self.message(snapshot: original)
            session.begin(message, snapshot: original)
            if ready { _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes")))) }
            XCTAssertEqual(session.invalidate(with: revised)?.payload.reason, .contentChanged)
            XCTAssertEqual(session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" late")))), .ignoredStale)
            session.begin(message, snapshot: original)
            _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes"))))
            XCTAssertFalse(session.canAccept(visibleIdentity: message.identity, visibleText: " yes", stabilizedSnapshot: revised))
            session.begin(message, snapshot: original)
            _ = session.handle(.suggestionFinal(.init(identity: message.identity, result: .text(" yes"))))
            _ = session.previewTypeThrough(" y")
            let typed = Self.snapshot(textBefore: "Reply y", fieldContext: context("Lucía"))
            guard case .cancelled = session.reconcileTypeThrough(with: typed) else { return XCTFail("Recipient revision must cancel type-through") }
        }
    }

    func testAcceptsCurrentFinalAndBecomesReady() {
        let snapshot = Self.snapshot(textBefore: "Hola")
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)

        XCTAssertNil(session.begin(message, snapshot: snapshot))
        XCTAssertEqual(
            session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(
                        identity: message.identity,
                        result: .text(" mundo feliz")
                    )
                )
            ),
            .accepted
        )
        XCTAssertEqual(
            session.state,
            .ready(identity: message.identity, text: " mundo feliz", snapshot: snapshot)
        )
    }

    func testDiscardsLateIdentityWithoutChangingCurrentRequest() {
        let snapshot = Self.snapshot(textBefore: "Hola")
        let session = SuggestionSession()
        let current = Self.message(snapshot: snapshot)
        let stale = Self.message(
            snapshot: snapshot,
            requestID: UUID(uuidString: "5A4673EA-8F23-45A9-A293-54494656987D")!
        )
        session.begin(current, snapshot: snapshot)

        XCTAssertEqual(
            session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(
                        identity: stale.identity,
                        result: .text(" stale")
                    )
                )
            ),
            .ignoredStale
        )
        XCTAssertEqual(session.state, .requesting(identity: current.identity))
    }

    func testRejectsASecondFinalAndDismissesTheSession() {
        let snapshot = Self.snapshot(textBefore: "Hola")
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )

        XCTAssertEqual(
            session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(
                        identity: message.identity,
                        result: .text(" mundo otra vez")
                    )
                )
            ),
            .rejectedCurrent
        )
        XCTAssertEqual(session.state, .idle)
    }

    func testServerResponsesRelyOnMonitorInvalidationInsteadOfIndependentAXReads() {
        let initial = Self.snapshot(textBefore: "Hola")
        let changed = Self.snapshot(textBefore: "Hola", focusGeneration: 2)
        let session = SuggestionSession()
        let first = Self.message(snapshot: initial)
        session.begin(first, snapshot: initial)

        XCTAssertEqual(
            session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(
                        identity: first.identity,
                        result: .text(" mundo")
                    )
                )
            ),
            .accepted
        )
        XCTAssertEqual(
            session.presentationFromLastValidatedSnapshot(
                for: first.identity
            )?.text,
            " mundo"
        )

        XCTAssertEqual(
            session.invalidate(with: changed)?.payload.reason,
            .focusChanged
        )
        XCTAssertEqual(session.state, .idle)

        XCTAssertEqual(
            session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(
                        identity: first.identity,
                        result: .text(" mundo")
                    )
                )
            ),
            .ignoredStale
        )
        XCTAssertEqual(session.state, .idle)
    }

    func testReplacementClassifiesFocusAndContentCancellationWithoutText() throws {
        let firstSnapshot = Self.snapshot(textBefore: "Hola")
        let contentSnapshot = Self.snapshot(textBefore: "Hola otra cosa")
        let focusSnapshot = Self.snapshot(textBefore: "Hola otra cosa", focusGeneration: 2)
        let session = SuggestionSession()
        let first = Self.message(snapshot: firstSnapshot)
        session.begin(first, snapshot: firstSnapshot)

        let contentCancel = try XCTUnwrap(
            session.begin(Self.message(snapshot: contentSnapshot), snapshot: contentSnapshot)
        )
        XCTAssertEqual(contentCancel.payload.reason, .contentChanged)
        XCTAssertFalse(String(data: try JSONEncoder().encode(contentCancel), encoding: .utf8)!.contains("Hola"))

        let focusCancel = try XCTUnwrap(
            session.begin(Self.message(snapshot: focusSnapshot), snapshot: focusSnapshot)
        )
        XCTAssertEqual(focusCancel.payload.reason, .focusChanged)
    }

    func testImmediateInvalidationDismissesAndClassifiesTheActiveRequest() throws {
        let initial = Self.snapshot(textBefore: "Hola")
        let changed = Self.snapshot(textBefore: "Hola cambiado")
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)

        let cancellation = try XCTUnwrap(session.invalidate(with: changed))

        XCTAssertEqual(cancellation.identity, message.identity)
        XCTAssertEqual(cancellation.payload.reason, .contentChanged)
        XCTAssertEqual(session.state, .idle)
    }

    func testReadySuggestionCanBeReservedExactlyOnceForVisibleIdentity() throws {
        let snapshot = Self.snapshot(textBefore: "Hola")
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )

        XCTAssertTrue(
            session.canAccept(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: snapshot
            )
        )
        XCTAssertEqual(
            session.reserveAcceptance(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: snapshot
            ),
            ReservedSuggestion(
                identity: message.identity,
                text: " mundo",
                snapshot: snapshot,
                typedThroughCharacters: 0,
                remainingText: "",
                isPartialAcceptance: false
            )
        )
        XCTAssertNil(
            session.reserveAcceptance(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            session.canAccept(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: snapshot
            )
        )
    }

    func testAcceptanceRequiresExactCurrentFinalVisibleText() {
        let snapshot = Self.snapshot(textBefore: "Hola")
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" final text")
                )
            )
        )

        XCTAssertFalse(
            session.canAccept(
                visibleIdentity: message.identity,
                visibleText: " partial",
                stabilizedSnapshot: snapshot
            )
        )
        XCTAssertEqual(session.state, .idle)
    }

    func testCannotReserveAReadySuggestionAfterFocusTurnsStale() {
        let snapshot = Self.snapshot(textBefore: "Hola")
        var current = snapshot
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )
        current = Self.snapshot(textBefore: "Otro", focusGeneration: 2)

        XCTAssertFalse(
            session.canAccept(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: current
            )
        )
        XCTAssertNil(
            session.reserveAcceptance(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: current
            )
        )
        XCTAssertEqual(session.state, .idle)
    }

    func testTypingMatchingGhostPrefixAdvancesTheReadyPresentation() {
        let initial = Self.snapshot(textBefore: "Hola")
        var current = initial
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )
        current = Self.snapshot(textBefore: "Hola mu")
        _ = session.previewTypeThrough(" mu")

        XCTAssertEqual(
            session.reconcileTypeThrough(with: current),
            .advanced(
                presentation: SuggestionPresentation(
                    identity: message.identity,
                    text: "ndo",
                    snapshot: current
                ),
                acceptedCharacters: 3,
                typedText: " mu"
            )
        )
        XCTAssertEqual(
            session.state,
            .ready(identity: message.identity, text: "ndo", snapshot: current)
        )
        XCTAssertTrue(
            session.canAccept(
                visibleIdentity: message.identity,
                visibleText: "ndo",
                stabilizedSnapshot: current
            )
        )
        XCTAssertEqual(
            session.reserveAcceptance(
                visibleIdentity: message.identity,
                visibleText: "ndo",
                stabilizedSnapshot: current
            ),
            ReservedSuggestion(
                identity: message.identity,
                text: "ndo",
                snapshot: current,
                typedThroughCharacters: 3,
                remainingText: "",
                isPartialAcceptance: true
            )
        )
    }

    func testTypingExactLeadingWhitespaceConsumesOnlyTheTypedPrefix() {
        let initial = Self.snapshot(textBefore: "Hola:")
        var current = initial
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )
        current = Self.snapshot(textBefore: "Hola: m")
        _ = session.previewTypeThrough(" m")

        XCTAssertEqual(
            session.reconcileTypeThrough(with: current),
            .advanced(
                presentation: SuggestionPresentation(
                    identity: message.identity,
                    text: "undo",
                    snapshot: current
                ),
                acceptedCharacters: 2,
                typedText: " m"
            )
        )
    }

    func testCaseMismatchCancelsTypeThroughExactly() {
        let initial = Self.snapshot(textBefore: "Prueba:")
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" funciona")
                )
            )
        )
        guard case let .cancelled(cancellation) = session.previewTypeThrough("Funciona")
        else {
            return XCTFail("Expected exact-case type-through cancellation")
        }
        XCTAssertEqual(cancellation.payload.reason, .contentChanged)
        XCTAssertEqual(session.state, .idle)
    }

    func testUnavailableGeometryCannotReserveTabAcceptance() {
        let snapshot = Self.snapshot(
            textBefore: "Hola",
            geometrySource: .zeroLengthRange,
            captureSequence: 1
        )
        let unavailable = Self.snapshot(
            textBefore: "Hola",
            caretBounds: nil,
            geometryQuality: .unavailable,
            geometrySource: nil,
            captureSequence: 2
        )
        let session = SuggestionSession()
        let message = Self.message(snapshot: snapshot)
        session.begin(message, snapshot: snapshot)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )
        XCTAssertFalse(
            session.canAccept(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: unavailable
            )
        )
        XCTAssertNil(
            session.reserveAcceptance(
                visibleIdentity: message.identity,
                visibleText: " mundo",
                stabilizedSnapshot: unavailable
            )
        )
        XCTAssertEqual(session.state, .idle)
    }

    func testSequentialTypingConsumesOnlyTheNewGhostPrefix() {
        let initial = Self.snapshot(textBefore: "Hello")
        var current = initial
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" world")
                )
            )
        )

        current = Self.snapshot(textBefore: "Hello w")
        _ = session.previewTypeThrough(" w")
        _ = session.reconcileTypeThrough(with: current)
        current = Self.snapshot(textBefore: "Hello wor")
        _ = session.previewTypeThrough("or")

        XCTAssertEqual(
            session.reconcileTypeThrough(with: current),
            .advanced(
                presentation: SuggestionPresentation(
                    identity: message.identity,
                    text: "ld",
                    snapshot: current
                ),
                acceptedCharacters: 4,
                typedText: "or"
            )
        )
    }

    func testTypingTheEntireGhostCompletesWithoutInterceptingTextKeys() {
        let initial = Self.snapshot(textBefore: "Hola")
        let completed = Self.snapshot(textBefore: "Hola mundo")
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )
        _ = session.previewTypeThrough(" mundo")

        XCTAssertEqual(
            session.reconcileTypeThrough(with: completed),
            .completed(
                identity: message.identity,
                snapshot: completed,
                acceptedCharacters: " mundo".utf16.count
            )
        )
        XCTAssertEqual(session.state, .idle)
    }

    func testUnicodePrefixAndBoundedContextRemainGraphemeSafe() {
        let initial = Self.snapshot(
            textBefore: String(repeating: "a", count: 8_000),
            selectionLocation: 10_000
        )
        let typed = " 👋🏽"
        let changed = Self.snapshot(
            textBefore: String(repeating: "a", count: 7_995) + typed,
            selectionLocation: 10_000 + typed.utf16.count
        )
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" 👋🏽 café 你好 שלום")
                )
            )
        )
        _ = session.previewTypeThrough(typed)

        guard case let .advanced(presentation, acceptedCharacters, typedText) =
            session.reconcileTypeThrough(with: changed)
        else {
            return XCTFail("Expected bounded Unicode type-through")
        }
        XCTAssertEqual(presentation.text, " café 你好 שלום")
        XCTAssertEqual(acceptedCharacters, typed.utf16.count)
        XCTAssertEqual(typedText, typed)
    }

    func testIncompatibleTextOrFocusChangeCancelsClosed() throws {
        let initial = Self.snapshot(textBefore: "Hello")
        var current = initial
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(identity: message.identity, result: .text(" world"))
            )
        )
        current = Self.snapshot(textBefore: "Hello x")

        guard case let .cancelled(contentCancellation) = session.reconcileTypeThrough(
            with: current
        ) else {
            return XCTFail("Expected incompatible text cancellation")
        }
        XCTAssertEqual(contentCancellation.payload.reason, .contentChanged)
        XCTAssertEqual(session.state, .idle)

        var focused = initial
        let focusSession = SuggestionSession()
        focusSession.begin(message, snapshot: initial)
        _ = focusSession.handle(
            .suggestionFinal(
                SuggestionFinalCommand(identity: message.identity, result: .text(" world"))
            )
        )
        focused = Self.snapshot(textBefore: "Hello", focusGeneration: 2)
        guard case let .cancelled(focusCancellation) = focusSession.reconcileTypeThrough(
            with: focused
        ) else {
            return XCTFail("Expected focus cancellation")
        }
        XCTAssertEqual(focusCancellation.payload.reason, .focusChanged)
    }

    func testSelectionCompositionAndAmbiguousEditsCancelClosed() {
        let initial = Self.snapshot(textBefore: "Hello", textAfter: " tail")
        let cases = [
            Self.snapshot(
                textBefore: "Hello w",
                selectedText: "marked",
                textAfter: " tail"
            ),
            Self.snapshot(textBefore: "Hello w", textAfter: " changed"),
            Self.snapshot(textBefore: "Hella w", textAfter: " tail"),
        ]

        for changed in cases {
            let session = SuggestionSession()
            let message = Self.message(snapshot: initial)
            session.begin(message, snapshot: initial)
            _ = session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(identity: message.identity, result: .text(" world"))
                )
            )
            guard case let .cancelled(cancellation) = session.reconcileTypeThrough(with: changed) else {
                return XCTFail("Expected ambiguous edit cancellation")
            }
            XCTAssertEqual(cancellation.payload.reason, .contentChanged)
            XCTAssertEqual(session.state, .idle)
        }
    }

    func testRapidCommittedTextAdvancesFromTheLastValidatedSnapshot() {
        let initial = Self.snapshot(textBefore: "Prueba:")
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text("funciona")
                )
            )
        )

        XCTAssertEqual(
            session.previewTypeThrough("f"),
            .advanced(
                presentation: SuggestionPresentation(
                    identity: message.identity,
                    text: "unciona",
                    snapshot: initial
                ),
                acceptedCharacters: 1
            )
        )
        XCTAssertEqual(
            session.previewTypeThrough("u"),
            .advanced(
                presentation: SuggestionPresentation(
                    identity: message.identity,
                    text: "nciona",
                    snapshot: initial
                ),
                acceptedCharacters: 2
            )
        )
        XCTAssertEqual(
            session.presentationFromLastValidatedSnapshot(
                for: message.identity
            )?.text,
            "nciona"
        )
    }

    func testLeadingSuggestionWhitespaceMustBeTypedExactly() {
        let initial = Self.snapshot(textBefore: "Hola")
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" mundo")
                )
            )
        )

        guard case let .cancelled(cancellation) = session.previewTypeThrough("m")
        else {
            return XCTFail("Typing past hidden whitespace must cancel speculation")
        }
        XCTAssertEqual(cancellation.payload.reason, .contentChanged)
        XCTAssertEqual(session.state, .idle)
    }

    func testAuthoritativeCaptureConfirmsPreviewWithoutDoubleConsumption() {
        let initial = Self.snapshot(textBefore: "Prueba:")
        let changed = Self.snapshot(textBefore: "Prueba:fu")
        let session = SuggestionSession()
        let message = Self.message(snapshot: initial)
        session.begin(message, snapshot: initial)
        _ = session.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text("funciona")
                )
            )
        )
        _ = session.previewTypeThrough("f")
        _ = session.previewTypeThrough("u")
        XCTAssertEqual(
            session.reconcileTypeThrough(with: changed),
            .advanced(
                presentation: SuggestionPresentation(
                    identity: message.identity,
                    text: "nciona",
                    snapshot: changed
                ),
                acceptedCharacters: 2,
                typedText: "fu"
            )
        )
        XCTAssertEqual(
            session.presentationFromLastValidatedSnapshot(
                for: message.identity
            )?.text,
            "nciona"
        )
    }

    func testMismatchAndNativeSuggestionAcceptanceCancelSpeculation() {
        let initial = Self.snapshot(textBefore: "Prueba:")
        let message = Self.message(snapshot: initial)

        let mismatch = SuggestionSession()
        mismatch.begin(message, snapshot: initial)
        _ = mismatch.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" funciona")
                )
            )
        )
        guard case let .cancelled(cancellation) = mismatch.previewTypeThrough("x") else {
            return XCTFail("Expected local mismatch cancellation")
        }
        XCTAssertEqual(cancellation.payload.reason, .contentChanged)

        let acceptedByMac = Self.snapshot(textBefore: "Prueba:funciona")
        let nativeAcceptance = SuggestionSession()
        nativeAcceptance.begin(message, snapshot: initial)
        _ = nativeAcceptance.handle(
            .suggestionFinal(
                SuggestionFinalCommand(
                    identity: message.identity,
                    result: .text(" funciona")
                )
            )
        )
        guard case let .cancelled(nativeCancellation) =
            nativeAcceptance.reconcileTypeThrough(with: acceptedByMac)
        else {
            return XCTFail("Expected native suggestion acceptance cancellation")
        }
        XCTAssertEqual(nativeCancellation.payload.reason, .contentChanged)
    }

    private static func message(
        snapshot: ActiveFieldSnapshot,
        requestID: UUID = UUID(uuidString: "DA2F74CE-C1DA-4E2E-85C7-B6D3C4069B63")!
    ) -> SuggestionRequestMessage {
        SuggestionRequestMessage(
            snapshot: snapshot,
            requestID: requestID,
            timestampMs: 1_788_000_000_000
        )
    }

    private static func snapshot(
        textBefore: String,
        selectedText: String = "",
        textAfter: String = "",
        focusGeneration: UInt64 = 1,
        selectionLocation: Int? = nil,
        caretBounds: CGRect? = CGRect(x: 10, y: 20, width: 1, height: 18),
        geometryQuality: GeometryQuality = .exact,
        geometrySource: CaretGeometrySource? = .zeroLengthRange,
        captureSequence: UInt64 = 1,
        sources: [FieldSource] = [],
        fieldContext: ActiveFieldContext? = nil
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Notes",
            elementIdentifier: "notes-field-\(focusGeneration)",
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
            fieldContext: fieldContext ?? ActiveFieldContext(shape: .multiline, sources: sources)
        )
    }
}
