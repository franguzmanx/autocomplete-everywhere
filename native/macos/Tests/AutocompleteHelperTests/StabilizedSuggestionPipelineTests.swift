import Foundation
import XCTest
@testable import AutocompleteHelper

final class StabilizedSuggestionPipelineTests: XCTestCase {
    func testInitialFarSampleNeverReachesThePresenter() {
        let harness = Harness(initial: Self.snapshot(text: "Prueba:", x: 900, sequence: 1))

        harness.poll(Self.snapshot(text: "Prueba:", x: 900, sequence: 1), at: 0)
        harness.poll(Self.snapshot(text: "Prueba:", x: 120, sequence: 2), at: 0.1)
        harness.poll(Self.snapshot(text: "Prueba:", x: 121, sequence: 3), at: 0.2)
        harness.poll(Self.snapshot(text: "Prueba:", x: 120.5, sequence: 4), at: 0.3)

        XCTAssertEqual(harness.presenter.presentedXs, [121])
        XCTAssertEqual(harness.presenter.visibleText, "funciona")
    }

    func testTypedPrefixHidesOldGhostUntilTwoCurrentGeometrySamplesAgree() {
        let harness = Self.readyHarness()

        harness.handle(.hostText("f"))
        XCTAssertNil(harness.presenter.visibleText)

        harness.poll(Self.snapshot(text: "Prueba:f", x: 130, sequence: 4), at: 0.31)
        XCTAssertNil(harness.presenter.visibleText)

        harness.poll(Self.snapshot(text: "Prueba:f", x: 131, sequence: 5), at: 0.32)
        XCTAssertEqual(harness.presenter.visibleText, "unciona")
        XCTAssertEqual(harness.presenter.presentedXs.last, 131)
    }

    func testRapidValidPrefixContinuesWhileGhostIsHidden() {
        let harness = Self.readyHarness()

        harness.handle(.hostText("f"))
        harness.handle(.hostText("u"))
        harness.handle(.hostText("n"))
        XCTAssertNil(harness.presenter.visibleText)

        harness.poll(Self.snapshot(text: "Prueba:fun", x: 145, sequence: 4), at: 0.31)
        XCTAssertNil(harness.presenter.visibleText)
        harness.poll(Self.snapshot(text: "Prueba:fun", x: 146, sequence: 5), at: 0.32)

        XCTAssertEqual(harness.presenter.visibleText, "ciona")
        XCTAssertEqual(harness.presenter.presentedXs.last, 146)
    }

    func testMismatchWhileHiddenCancelsAndCannotReviveOldSuggestion() {
        let harness = Self.readyHarness()

        harness.handle(.hostText("f"))
        harness.handle(.hostText("x"))
        XCTAssertNil(harness.presenter.visibleText)
        XCTAssertEqual(harness.session.state, .idle)

        harness.poll(Self.snapshot(text: "Prueba:fx", x: 145, sequence: 4), at: 0.31)
        harness.poll(Self.snapshot(text: "Prueba:fx", x: 146, sequence: 5), at: 0.32)

        XCTAssertNil(harness.presenter.visibleText)
    }

    func testTabPassesThroughWhilePrefixGeometryIsBeingReacquired() {
        let harness = Self.readyHarness()

        harness.handle(.hostText("f"))

        XCTAssertFalse(harness.pressTab())
        XCTAssertNil(harness.presenter.visibleText)
        XCTAssertEqual(harness.acceptanceReservations, 0)
    }

    func testTypingTheWholeSuggestionStaysSilentUntilAuthoritativeCompletion() {
        let harness = Self.readyHarness()

        harness.handle(.hostText("funciona"))
        XCTAssertNil(harness.presenter.visibleText)

        harness.poll(
            Self.snapshot(text: "Prueba:funciona", x: 190, sequence: 4),
            at: 0.31
        )

        XCTAssertNil(harness.presenter.visibleText)
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testResponseArrivingAfterHostTextDuringRequestCannotUsePreInputAnchor() {
        let harness = Harness(
            initial: Self.snapshot(text: "Prueba:", x: 100, sequence: 1),
            responseMode: .manual
        )
        harness.poll(Self.snapshot(text: "Prueba:", x: 100, sequence: 1), at: 0)
        harness.poll(Self.snapshot(text: "Prueba:", x: 101, sequence: 2), at: 0.1)
        harness.poll(Self.snapshot(text: "Prueba:", x: 101, sequence: 3), at: 0.3)
        XCTAssertEqual(harness.session.state, .requesting(identity: harness.currentIdentity!))

        harness.handle(.hostText("f"))
        harness.receiveFinal("funciona")
        XCTAssertNil(harness.presenter.visibleText)

        harness.poll(Self.snapshot(text: "Prueba:f", x: 130, sequence: 4), at: 0.31)
        XCTAssertNil(harness.presenter.visibleText)
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testResponseCannotRenderAfterGenerationAdvancesBeforeQueuedInvalidation() {
        let harness = Harness(
            initial: Self.snapshot(text: "Prueba:", x: 100, sequence: 1),
            responseMode: .manual
        )
        harness.poll(Self.snapshot(text: "Prueba:", x: 100, sequence: 1), at: 0)
        harness.poll(Self.snapshot(text: "Prueba:", x: 101, sequence: 2), at: 0.1)
        harness.poll(Self.snapshot(text: "Prueba:", x: 101, sequence: 3), at: 0.3)

        harness.advanceGenerationWithoutStateCallback()
        harness.receiveFinal("funciona")

        XCTAssertNil(harness.presenter.visibleText)
    }

    func testNativePillAcceptanceWithoutKeyboardPreviewCancelsClosed() {
        let harness = Self.readyHarness()

        harness.poll(
            Self.snapshot(text: "Prueba:funciona", x: 190, sequence: 4),
            at: 0.31
        )

        XCTAssertNil(harness.presenter.visibleIdentity)
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testNonemptyIMETextHidesAndWaitsForAuthoritativeCapture() {
        let harness = Self.readyHarness()
        let classifier = KeyboardInputCommitmentClassifier {
            KeyboardInputSourceState(
                isASCIICapable: false,
                isNonComposingKeyboardLayout: false
            )
        }
        let action = KeyboardEventPolicy().action(
            for: KeyboardInput(
                keyCode: 0,
                textInput: classifier.classify("日本")
            ),
            session: .ready
        )

        harness.handle(action)

        XCTAssertEqual(action, .hostStateChanged)
        XCTAssertNil(harness.presenter.visibleIdentity)
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testInvalidGeometryPassesTabThroughWithoutInsertionReservation() {
        let harness = Self.readyHarness()
        harness.poll(Self.unavailable(text: "Prueba:", sequence: 4), at: 0.31)

        XCTAssertFalse(harness.pressTab())
        XCTAssertNil(harness.presenter.visibleIdentity)
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testPendingDivergentAnchorPreservesGhostButPassesTabThrough() {
        let harness = Self.readyHarness()

        harness.poll(Self.snapshot(text: "Prueba:", x: 700, sequence: 4), at: 0.31)

        XCTAssertEqual(harness.presenter.visibleText, "funciona")
        XCTAssertFalse(harness.pressTab())
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testSpaceDefersToAXAndNativeCompletionNeverEmitsAStalePreview() {
        let harness = Self.readyHarness()
        let action = KeyboardEventPolicy().action(
            for: KeyboardInput(
                keyCode: 49,
                textInput: .committed(" ")
            ),
            session: .ready
        )

        harness.handle(action)
        XCTAssertEqual(action, .hostAmbiguousText)
        XCTAssertNil(harness.presenter.visibleIdentity)
        XCTAssertEqual(harness.presenter.presentedTexts, ["funciona"])

        harness.poll(
            Self.snapshot(text: "Prueba:funciona ", x: 200, sequence: 4),
            at: 0.31
        )

        XCTAssertEqual(harness.presenter.presentedTexts, ["funciona"])
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testLeadingWhitespaceMismatchPassesHostTextThroughAndCancelsGhost() {
        let harness = Harness(
            initial: Self.snapshot(text: "Hola", x: 100, sequence: 1),
            finalText: " mundo"
        )
        harness.poll(Self.snapshot(text: "Hola", x: 100, sequence: 1), at: 0)
        harness.poll(Self.snapshot(text: "Hola", x: 101, sequence: 2), at: 0.1)
        harness.poll(Self.snapshot(text: "Hola", x: 101, sequence: 3), at: 0.3)

        let action = KeyboardAction.hostText("m")
        harness.handle(action)

        XCTAssertEqual(action, .hostText("m"))
        XCTAssertNil(harness.presenter.visibleIdentity)
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testFinalSilenceDoesNotSuppressARequestAfterSubsequentContentChange() {
        let harness = Harness(
            initial: Self.snapshot(text: "", x: 100, sequence: 1),
            responseMode: .finalSilence
        )

        harness.poll(Self.snapshot(text: "", x: 100, sequence: 1), at: 0)
        harness.poll(Self.snapshot(text: "", x: 101, sequence: 2), at: 0.1)
        harness.poll(Self.snapshot(text: "", x: 101, sequence: 3), at: 0.3)

        XCTAssertEqual(harness.suggestionRequests, 1)
        XCTAssertEqual(harness.session.state, .idle)

        harness.poll(Self.snapshot(text: "Prueba", x: 150, sequence: 4), at: 0.31)
        harness.poll(Self.snapshot(text: "Prueba", x: 151, sequence: 5), at: 0.32)
        harness.poll(Self.snapshot(text: "Prueba", x: 151, sequence: 6), at: 0.61)

        XCTAssertEqual(harness.suggestionRequests, 2)
    }

    private static func readyHarness() -> Harness {
        let harness = Harness(initial: snapshot(text: "Prueba:", x: 100, sequence: 1))
        harness.poll(snapshot(text: "Prueba:", x: 100, sequence: 1), at: 0)
        harness.poll(snapshot(text: "Prueba:", x: 101, sequence: 2), at: 0.1)
        harness.poll(snapshot(text: "Prueba:", x: 101, sequence: 3), at: 0.3)
        XCTAssertEqual(harness.presenter.visibleText, "funciona")
        return harness
    }

    private static func snapshot(
        text: String,
        x: CGFloat,
        sequence: UInt64
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Notes",
            elementIdentifier: "notes-field",
            focusGeneration: 1,
            textBefore: text,
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            caretBounds: CGRect(x: x, y: 100, width: 0, height: 18),
            inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
            geometryQuality: .exact,
            geometrySource: .zeroLengthRange,
            captureSequence: sequence
        )
    }

    private static func unavailable(
        text: String,
        sequence: UInt64
    ) -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(
            applicationBundleIdentifier: "com.apple.Notes",
            elementIdentifier: "notes-field",
            focusGeneration: 1,
            textBefore: text,
            selectedText: "",
            textAfter: "",
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            caretBounds: nil,
            inputFrame: CGRect(x: 40, y: 60, width: 960, height: 540),
            geometryQuality: .unavailable,
            geometrySource: nil,
            captureSequence: sequence
        )
    }
}

private final class Harness {
    enum ResponseMode {
        case final
        case finalSilence
        case manual
    }

    let session = SuggestionSession()
    let presenter = FakeSuggestionPresenter()
    var state = StabilizedSuggestionState()
    let generation = ActiveFieldGeneration()
    var current: ActiveFieldSnapshot
    let responseMode: ResponseMode
    let finalText: String
    private(set) var acceptanceReservations = 0
    private(set) var suggestionRequests = 0
    var currentIdentity: SuggestionRequestMessage.Identity? { session.currentIdentity }

    lazy var monitor = ActiveFieldMonitor(
        capture: { [unowned self] in .captured(current) },
        quietInterval: 0.3,
        onStableSnapshot: { [unowned self] snapshot, callbackGeneration in
            beginSuggestion(snapshot, generation: callbackGeneration)
        },
        onGeometryChanged: { [unowned self] snapshot, callbackGeneration in
            acceptGeometry(snapshot, generation: callbackGeneration)
        },
        onGeometryHidden: { [unowned self] _ in
            if state.shouldHideForUnstableGeometry() { presenter.dismiss() }
        },
        onInvalidated: { [unowned self] snapshot, _ in invalidate(with: snapshot) },
        generation: generation,
        scheduleAfterHostPublication: { _, _ in }
    )

    init(
        initial: ActiveFieldSnapshot,
        responseMode: ResponseMode = .final,
        finalText: String = "funciona"
    ) {
        current = initial
        self.responseMode = responseMode
        self.finalText = finalText
        monitor.updateConfiguration(CaptureConfiguration.enabled)
    }

    func poll(_ snapshot: ActiveFieldSnapshot, at time: TimeInterval) {
        current = snapshot
        monitor.poll(at: time)
    }

    func preview(_ text: String) {
        switch session.previewTypeThrough(text) {
        case let .advanced(presentation, _):
            state.beginReacquisition()
            presenter.dismiss(identity: presentation.identity)
        case let .completed(identity, _): presenter.dismiss(identity: identity)
        case let .cancelled(cancellation):
            state.clear()
            presenter.dismiss(identity: cancellation.identity)
        case .ignored:
            state.beginReacquisition()
            presenter.dismiss()
        }
    }

    func handle(_ action: KeyboardAction) {
        switch action {
        case let .hostText(text):
            preview(text)
            monitor.refreshAfterInput()
        case .hostAmbiguousText:
            state.clear()
            presenter.dismiss()
        case .hostStateChanged, .dismissSuggestion:
            state.clear()
            _ = session.dismiss()
            presenter.dismiss()
        case .hostGeometryDisturbed:
            if state.shouldHideForUnstableGeometry() { presenter.dismiss() }
            monitor.requestReanchor()
            monitor.refreshAfterInput()
        case .acceptSuggestion: _ = attemptTab()
        case .acceptNextWord: _ = attemptTab(nextWordOnly: true)
        case .nextAlternative, .previousAlternative: break // Controller tests own version navigation.
        }
    }

    func receiveFinal(_ text: String) {
        guard let identity = session.currentIdentity else { return }
        handleResponse(
            .suggestionFinal(
                SuggestionFinalCommand(identity: identity, result: .text(text))
            ),
            identity: identity
        )
    }

    func advanceGenerationWithoutStateCallback() {
        monitor.refreshAfterInput()
    }

    func attemptTab(nextWordOnly: Bool = false) -> Bool {
        guard let identity = presenter.visibleIdentity,
              let stored = session.presentationFromLastValidatedSnapshot(for: identity)
        else { return false }
        let stabilized = monitor.stabilizedSnapshot(matching: stored.snapshot)
        guard session.reserveAcceptance(
            visibleIdentity: identity,
            visibleText: presenter.visibleText,
            stabilizedSnapshot: stabilized,
            nextWordOnly: nextWordOnly
        ) != nil else {
            state.clear()
            presenter.dismiss(identity: identity)
            return false
        }
        acceptanceReservations += 1
        return true
    }

    func pressTab() -> Bool {
        let status: KeyboardSessionStatus
        if let identity = presenter.visibleIdentity,
           let presentation = session.presentationFromLastValidatedSnapshot(for: identity) {
            status = monitor.stabilizedSnapshot(matching: presentation.snapshot) != nil
                ? .ready
                : .ghostVisible
        } else {
            status = session.state == .idle ? .inactive : .activeWithoutGhost
        }
        let action = KeyboardEventPolicy().action(
            for: KeyboardInput(keyCode: 48),
            session: status
        )
        guard action == .acceptSuggestion else {
            handle(action)
            return false
        }
        return attemptTab()
    }

    private func beginSuggestion(
        _ snapshot: ActiveFieldSnapshot,
        generation callbackGeneration: UInt64
    ) {
        suggestionRequests += 1
        state.begin(at: snapshot, generation: callbackGeneration)
        let message = SuggestionRequestMessage(snapshot: snapshot)
        _ = session.begin(message, snapshot: snapshot)
        switch responseMode {
        case .final:
            _ = session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(
                        identity: message.identity,
                        result: .text(finalText)
                    )
                )
            )
            presentCurrent(identity: message.identity)
        case .finalSilence:
            _ = session.handle(
                .suggestionFinal(
                    SuggestionFinalCommand(
                        identity: message.identity,
                        result: .silence("not_useful")
                    )
                )
            )
            presentCurrent(identity: message.identity)
        case .manual:
            break
        }
    }

    private func handleResponse(
        _ command: HelperCommand,
        identity: SuggestionRequestMessage.Identity
    ) {
        switch session.handle(command) {
        case .accepted:
            if case .suggestionFinal = command {
                presentCurrent(identity: identity)
            }
        case .rejectedCurrent:
            state.clear()
            presenter.dismiss(identity: identity)
        case .ignoredStale:
            break
        }
    }

    private func presentCurrent(identity: SuggestionRequestMessage.Identity) {
        if let stored = session.presentationFromLastValidatedSnapshot(for: identity),
           let anchored = state.anchored(
               stored,
               currentGeneration: generation.current
           ) {
            presenter.present(anchored)
        }
    }

    private func invalidate(with snapshot: ActiveFieldSnapshot?) {
        if let snapshot {
            switch session.reconcileTypeThrough(with: snapshot) {
            case let .advanced(presentation, _, _):
                monitor.markHandled(snapshot)
                let preserved = state.reconcileAuthoritativeAdvance()
                if !preserved { presenter.dismiss(identity: presentation.identity) }
                return
            case let .completed(identity, completedSnapshot, _):
                monitor.markHandled(completedSnapshot)
                state.clear()
                presenter.dismiss(identity: identity)
                return
            case let .cancelled(cancellation):
                state.clear()
                presenter.dismiss(identity: cancellation.identity)
                return
            case .ignored: break
            }
        }
        _ = session.invalidate(with: snapshot)
        state.clear()
        presenter.dismiss()
    }

    private func acceptGeometry(
        _ snapshot: ActiveFieldSnapshot,
        generation callbackGeneration: UInt64
    ) {
        state.acceptGeometry(snapshot, generation: callbackGeneration)
        guard let identity = session.currentIdentity,
              let stored = session.presentationFromLastValidatedSnapshot(for: identity),
              let anchored = state.anchored(
                  stored,
                  currentGeneration: generation.current
              )
        else {
            state.clear()
            presenter.dismiss()
            return
        }
        presenter.present(anchored)
    }
}

private final class FakeSuggestionPresenter {
    private(set) var visibleIdentity: SuggestionRequestMessage.Identity?
    private(set) var visibleText: String?
    private(set) var presentedXs: [CGFloat] = []
    private(set) var presentedTexts: [String] = []

    @discardableResult
    func present(_ presentation: SuggestionPresentation) -> Bool {
        guard !presentation.text.contains(where: { $0.isNewline }) else {
            dismiss(identity: presentation.identity)
            return false
        }
        visibleIdentity = presentation.identity
        visibleText = presentation.text
        presentedTexts.append(presentation.text)
        if let x = presentation.snapshot.caretBounds?.minX { presentedXs.append(x) }
        return true
    }

    func dismiss(identity: SuggestionRequestMessage.Identity? = nil) {
        guard identity == nil || identity == visibleIdentity else { return }
        visibleIdentity = nil
        visibleText = nil
    }
}
