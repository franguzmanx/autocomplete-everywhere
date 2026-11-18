import XCTest
import ApplicationServices
@testable import AutocompleteHelper

final class KeyboardMonitorTests: XCTestCase {
    func testAlternativeArrowsRequireExactOptionAndVisibleGhost() {
        let bindings: [(Int64, KeyboardAction)] = [(125, .nextAlternative), (126, .previousAlternative)]
        for (key, action) in bindings {
            let input = KeyboardInput(keyCode: key, modifiers: .option)
            XCTAssertEqual(policy.action(for: input, session: .ready), action)
            XCTAssertEqual(policy.action(for: input, session: .ghostVisible), action)
            XCTAssertEqual(policy.action(for: input, session: .inactive), .hostStateChanged)
            XCTAssertEqual(policy.action(for: input, session: .activeWithoutGhost), .hostStateChanged)
            XCTAssertEqual(policy.action(for: .init(keyCode: key, modifiers: [.option, .shift]), session: .ready), .hostStateChanged)
        }
    }

    @MainActor
    func testHeldAlternativeArrowAndOptionReleaseNeverAcceptOrRepeat() {
        var actions: [KeyboardAction] = []
        var edits = 0
        let monitor = KeyboardMonitor(sessionProvider: { .ready }, actionHandler: { action in
            actions.append(action)
            return action == .nextAlternative
        }, onUserEdit: { edits += 1 })
        XCTAssertTrue(monitor.process(.init(keyCode: 125, modifiers: .option), phase: .keyDown))
        XCTAssertTrue(monitor.process(.init(keyCode: 125, modifiers: .option, isRepeat: true), phase: .keyDown))
        XCTAssertFalse(monitor.process(.init(keyCode: 58), phase: .keyUp))
        XCTAssertTrue(monitor.process(.init(keyCode: 125), phase: .keyUp))
        XCTAssertEqual(actions, [.nextAlternative])
        XCTAssertEqual(edits, 0)
    }

    func testInsertionEventTagDoesNotMatchOrdinaryEvents() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertFalse(SyntheticInsertionEvent.isOwn(event))
        SyntheticInsertionEvent.mark(event)
        XCTAssertTrue(SyntheticInsertionEvent.isOwn(event))
        let ordinary = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertFalse(SyntheticInsertionEvent.isOwn(ordinary))
    }

    @MainActor
    func testOwnInsertionPassesThroughWithoutCancellingWorkOrCountingAsTyping() {
        var observed = 0
        var edits = 0
        let monitor = KeyboardMonitor(sessionProvider: { .activeWithoutGhost }, actionHandler: { _ in
            observed += 1
            return false
        }, onUserEdit: { edits += 1 })
        monitor.inputHandler = { _ in observed += 1; return false }
        let inserted = KeyboardInput(keyCode: 0, textInput: .committed("Replacement"), isAutocompleteInsertion: true)
        XCTAssertFalse(monitor.process(inserted, phase: .keyDown))
        XCTAssertFalse(monitor.process(inserted, phase: .keyUp))
        XCTAssertEqual(observed, 0)
        XCTAssertEqual(edits, 0)
        XCTAssertFalse(monitor.process(.init(keyCode: 0, textInput: .committed("a")), phase: .keyDown))
        XCTAssertGreaterThan(observed, 0)
        XCTAssertEqual(edits, 1, "Real typing must still cancel work and count as authored input")
    }

    func testCustomShortcutsOnlyInterceptVisibleReadySuggestionsAndExactModifiers() {
        let policy = KeyboardEventPolicy(
            accept: .init(keyCode: 36, modifiers: 256),
            dismiss: .init(keyCode: 2, modifiers: 4096)
        )
        let accept = KeyboardInput(keyCode: 36, modifiers: .command)
        let dismiss = KeyboardInput(keyCode: 2, modifiers: .control)
        XCTAssertEqual(policy.action(for: accept, session: .ready), .acceptSuggestion)
        XCTAssertEqual(policy.action(for: accept, session: .inactive), .hostStateChanged)
        XCTAssertEqual(policy.action(for: accept, session: .activeWithoutGhost), .hostStateChanged)
        XCTAssertEqual(policy.action(for: dismiss, session: .ready), .dismissSuggestion)
        XCTAssertEqual(policy.action(for: dismiss, session: .inactive), .hostStateChanged)
        XCTAssertEqual(policy.action(for: .init(keyCode: 36, modifiers: [.command, .shift]), session: .ready), .hostStateChanged)
        XCTAssertEqual(policy.action(for: .init(keyCode: 36, modifiers: .command, isRepeat: true), session: .ready), .hostStateChanged)
        XCTAssertEqual(policy.action(for: .init(keyCode: 48), session: .ready), .hostStateChanged)
        XCTAssertEqual(policy.action(for: .init(keyCode: 53), session: .ready), .hostStateChanged)
    }

    func testFixedBindingsAreInvalidForConfigurableActions() {
        for key: Int64 in [48, 125, 126, 18, 19, 20, 21, 23, 22, 26, 28, 25] {
            XCTAssertFalse(InteractionKeyBinding(keyCode: key, modifiers: 2048).isValid)
            let binding = InteractionKeyBinding(keyCode: key, modifiers: 2560)
            XCTAssertTrue(binding.isValid)
            let input = KeyboardInput(keyCode: key, modifiers: [.option, .shift])
            XCTAssertEqual(KeyboardEventPolicy(dismiss: binding).action(for: input, session: .ready), .dismissSuggestion)
        }
    }

    @MainActor
    func testUnconfirmedPrintableInputMarksOnlyAnEditOpportunityWithoutPrediction() {
        var edits = 0
        var actions: [KeyboardAction] = []
        let monitor = KeyboardMonitor(sessionProvider: { .inactive }, actionHandler: { actions.append($0); return false }, onUserEdit: { edits += 1 })
        for text in ["ñ", "é", "ж", "n"] {
            XCTAssertFalse(monitor.process(.init(keyCode: 0, textInput: .unconfirmed(text, nonComposingLayout: true)), phase: .keyDown))
        }
        XCTAssertEqual(edits, 4)
        XCTAssertEqual(actions, Array(repeating: .hostStateChanged, count: 4))
        for input in [KeyboardInput(keyCode: 14, modifiers: .option), // dead key without text
                      .init(keyCode: 14, modifiers: .option, textInput: .unconfirmed("´", nonComposingLayout: true)), // dead-key preedit
                      .init(keyCode: 58), // modifier
                      .init(keyCode: 0, textInput: .unconfirmed("日本")), // composing input source
                      .init(keyCode: 0, textInput: .unconfirmed("n")), // unknown input source
                      .init(keyCode: 123, textInput: .unconfirmed("x")), // navigation
                      .init(keyCode: 0, modifiers: .control, textInput: .unconfirmed("ñ")),
                      .init(keyCode: 0, textInput: .unconfirmed("\u{1B}")),
                      .init(keyCode: 0, textInput: .unconfirmed("ñ"), isAutocompleteInsertion: true)] {
            _ = monitor.process(input, phase: .keyDown)
        }
        XCTAssertEqual(edits, 4)
    }

    private let policy = KeyboardEventPolicy()
    @MainActor
    func testLiveShortcutUpdateConsumesOnlyHandledKeyAndItsRelease() {
        var ready = false
        var actions: [KeyboardAction] = []
        var edits = 0
        let monitor = KeyboardMonitor(sessionProvider: { ready ? .ready : .inactive }, actionHandler: { action in
            actions.append(action)
            return action == .acceptSuggestion
        }, onUserEdit: { edits += 1 })
        monitor.configure(accept: .init(keyCode: 9, modifiers: 256), dismiss: .dismissDefault)
        let key = KeyboardInput(keyCode: 9, modifiers: .command)
        XCTAssertFalse(monitor.process(key, phase: .keyDown))
        ready = true
        XCTAssertTrue(monitor.process(key, phase: .keyDown))
        XCTAssertEqual(actions.last, .acceptSuggestion)
        XCTAssertEqual(edits, 1, "Only the earlier host paste counts as an edit")
        ready = false
        XCTAssertTrue(monitor.process(key, phase: .keyUp))
        XCTAssertFalse(monitor.process(key, phase: .keyUp))
    }

    @MainActor
    func testOnlyEditingKeysMarkAnAuthoredChange() {
        var edits = 0
        let monitor = KeyboardMonitor(sessionProvider: { .inactive }, actionHandler: { _ in false }, onUserEdit: { edits += 1 })
        for key in [123, 124, 48, 53] {
            _ = monitor.process(KeyboardInput(keyCode: Int64(key)), phase: .keyDown)
        }
        _ = monitor.process(KeyboardInput(keyCode: 8, modifiers: .command), phase: .keyDown)
        XCTAssertEqual(edits, 0)
        for key in [36, 51, 117] {
            _ = monitor.process(KeyboardInput(keyCode: Int64(key)), phase: .keyDown)
        }
        _ = monitor.process(KeyboardInput(keyCode: 9, modifiers: .command), phase: .keyDown)
        _ = monitor.process(KeyboardInput(keyCode: 0, textInput: .committed("a")), phase: .keyDown)
        _ = monitor.process(KeyboardInput(keyCode: 0), phase: .keyUp)
        XCTAssertEqual(edits, 5)
    }


    func testConsumesPlainTabOnlyWhenSuggestionIsReady() {
        let tab = KeyboardInput(keyCode: 48)

        XCTAssertEqual(policy.action(for: tab, session: .inactive), .hostStateChanged)
        XCTAssertEqual(policy.action(for: tab, session: .activeWithoutGhost), .hostStateChanged)
        XCTAssertEqual(
            policy.action(for: tab, session: .ghostVisible),
            .hostStateChanged
        )
        XCTAssertEqual(policy.action(for: tab, session: .ready), .acceptSuggestion)
    }

    func testEscapeDismissesOnlyAnActiveSession() {
        let escape = KeyboardInput(keyCode: 53)

        XCTAssertEqual(policy.action(for: escape, session: .inactive), .hostStateChanged)
        XCTAssertEqual(policy.action(for: escape, session: .activeWithoutGhost), .hostStateChanged)
        XCTAssertEqual(policy.action(for: escape, session: .ghostVisible), .dismissSuggestion)
        XCTAssertEqual(policy.action(for: escape, session: .ready), .dismissSuggestion)
    }

    func testReturnDismissesAnActiveSuggestionWithoutBecomingTextInput() {
        for keyCode: Int64 in [36, 76] {
            let enter = KeyboardInput(keyCode: keyCode)

            XCTAssertEqual(policy.action(for: enter, session: .inactive), .hostStateChanged)
            XCTAssertEqual(
                policy.action(for: enter, session: .ghostVisible),
                .hostStateChanged
            )
            XCTAssertEqual(
                policy.action(for: enter, session: .ready),
                .hostStateChanged
            )
        }
    }

    func testModifiedTabAndEscapeHideTheVisibleGhostBeforePassingThrough() {
        let modifiers: [KeyboardModifiers] = [.command, .control, .shift, [.option, .shift], [.option, .command]]

        for modifier in modifiers {
            XCTAssertEqual(
                policy.action(
                    for: KeyboardInput(keyCode: 48, modifiers: modifier),
                    session: .ready
                ),
                .hostStateChanged
            )
            XCTAssertEqual(
                policy.action(
                    for: KeyboardInput(keyCode: 53, modifiers: modifier),
                    session: .ghostVisible
                ),
                .hostStateChanged
            )
        }
    }

    func testTextKeysPassThroughWithoutHidingInEverySessionState() {
        let textInputs = [
            KeyboardInput(keyCode: 0, textInput: .committed("a")),
            KeyboardInput(keyCode: 12, textInput: .committed("q")),
            KeyboardInput(keyCode: 0, modifiers: .shift, textInput: .committed("A")),
        ]

        for input in textInputs {
            guard case let .committed(text) = input.textInput else {
                return XCTFail("Expected committed test fixture")
            }
            XCTAssertEqual(policy.action(for: input, session: .inactive), .hostText(text))
            XCTAssertEqual(policy.action(for: input, session: .activeWithoutGhost), .hostText(text))
            XCTAssertEqual(policy.action(for: input, session: .ghostVisible), .hostText(text))
            XCTAssertEqual(policy.action(for: input, session: .ready), .hostText(text))
        }
    }

    func testNavigationAndDeletionKeysOnlyHideAVisibleGhost() {
        let navigationInputs = [
            KeyboardInput(keyCode: 51),
            KeyboardInput(keyCode: 117),
            KeyboardInput(keyCode: 123),
            KeyboardInput(keyCode: 124),
            KeyboardInput(keyCode: 125),
            KeyboardInput(keyCode: 126),
        ]

        for input in navigationInputs {
            XCTAssertEqual(policy.action(for: input, session: .inactive), .hostStateChanged)
            XCTAssertEqual(policy.action(for: input, session: .activeWithoutGhost), .hostStateChanged)
            XCTAssertEqual(
                policy.action(for: input, session: .ghostVisible),
                .hostStateChanged
            )
            XCTAssertEqual(
                policy.action(for: input, session: .ready),
                .hostStateChanged
            )
        }
    }

    func testAutoRepeatPassesThrough() {
        XCTAssertEqual(
            policy.action(
                for: KeyboardInput(keyCode: 48, isRepeat: true),
                session: .ready
            ),
            .hostStateChanged
        )
    }

    func testOptionTabAcceptsOneWordOnlyWhenReady() {
        let input = KeyboardInput(keyCode: 48, modifiers: .option)
        XCTAssertEqual(policy.action(for: input, session: .ready), .acceptNextWord)
        for state: KeyboardSessionStatus in [.inactive, .activeWithoutGhost, .ghostVisible] {
            XCTAssertEqual(policy.action(for: input, session: state), .hostStateChanged)
        }
        XCTAssertEqual(policy.action(
            for: KeyboardInput(keyCode: 48, modifiers: .option, isRepeat: true),
            session: .ready
        ), .hostStateChanged)
    }

    @MainActor
    func testOptionTabAcceptsOnlyOnceUntilTabIsReleased() {
        var actions: [KeyboardAction] = []
        let monitor = KeyboardMonitor(sessionProvider: { .ready }, actionHandler: {
            actions.append($0)
            return true
        })
        XCTAssertTrue(monitor.process(KeyboardInput(keyCode: 48, modifiers: .option), phase: .keyDown))
        XCTAssertTrue(monitor.process(KeyboardInput(keyCode: 48, modifiers: .option, isRepeat: true), phase: .keyDown))
        // Releasing Option before Tab must still release the consumed Tab latch.
        XCTAssertTrue(monitor.process(KeyboardInput(keyCode: 48), phase: .keyUp))
        XCTAssertEqual(actions, [.acceptNextWord])
    }

    @MainActor
    func testMonitorConsumesOnlyAtomicallyReservedKeyDownAndMatchingKeyUp() {
        var reservations = 0
        let monitor = KeyboardMonitor(
            sessionProvider: { .ready },
            actionHandler: { action in
                XCTAssertEqual(action, .acceptSuggestion)
                guard reservations == 0 else { return false }
                reservations += 1
                return true
            }
        )
        let tab = KeyboardInput(keyCode: 48)

        XCTAssertTrue(monitor.process(tab, phase: .keyDown))
        XCTAssertTrue(monitor.process(tab, phase: .keyDown))
        XCTAssertTrue(monitor.process(tab, phase: .keyUp))
        XCTAssertFalse(monitor.process(tab, phase: .keyUp))
        XCTAssertEqual(reservations, 1)
    }

    @MainActor
    func testConsumedKeyLatchAlsoConsumesRepeatAndDuplicateKeyDownUntilKeyUp() {
        let monitor = KeyboardMonitor(
            sessionProvider: { .ready },
            actionHandler: { _ in true }
        )
        let tab = KeyboardInput(keyCode: 48)

        XCTAssertTrue(monitor.process(tab, phase: .keyDown))
        XCTAssertTrue(
            monitor.process(
                KeyboardInput(keyCode: 48, isRepeat: true),
                phase: .keyDown
            )
        )
        XCTAssertTrue(monitor.process(tab, phase: .keyDown))
        XCTAssertTrue(monitor.process(tab, phase: .keyUp))
        XCTAssertFalse(monitor.process(tab, phase: .keyUp))
    }

    @MainActor
    func testRejectedReservationPassesBothKeyDownAndKeyUpThrough() {
        let monitor = KeyboardMonitor(
            sessionProvider: { .ready },
            actionHandler: { _ in false }
        )
        let tab = KeyboardInput(keyCode: 48)

        XCTAssertFalse(monitor.process(tab, phase: .keyDown))
        XCTAssertFalse(monitor.process(tab, phase: .keyUp))
    }

    @MainActor
    func testReturnDismissesTheGhostButStillPassesThroughToNotes() {
        var actions: [KeyboardAction] = []
        let monitor = KeyboardMonitor(
            sessionProvider: { .ready },
            actionHandler: { action in
                actions.append(action)
                return true
            }
        )
        let enter = KeyboardInput(keyCode: 36)

        XCTAssertFalse(monitor.process(enter, phase: .keyDown))
        XCTAssertFalse(monitor.process(enter, phase: .keyUp))
        XCTAssertEqual(actions, [.hostStateChanged])
    }

    @MainActor
    func testOrdinaryTextKeyKeepsTheGhostStableWhilePassingThroughToNotes() {
        var actions: [KeyboardAction] = []
        let monitor = KeyboardMonitor(
            sessionProvider: { .ready },
            actionHandler: { action in
                actions.append(action)
                return true
            }
        )
        let letter = KeyboardInput(keyCode: 3, textInput: .committed("f"))

        XCTAssertFalse(monitor.process(letter, phase: .keyDown))
        XCTAssertFalse(monitor.process(letter, phase: .keyUp))
        XCTAssertEqual(actions, [.hostText("f")])
    }

    func testNonASCIITextCannotBeAssumedCommittedForLocalPreview() {
        XCTAssertEqual(
            policy.action(
                for: KeyboardInput(keyCode: 0, textInput: .unconfirmed("👋🏽")),
                session: .ready
            ),
            .hostStateChanged
        )
        XCTAssertEqual(
            policy.action(
                for: KeyboardInput(keyCode: 0, textInput: .unconfirmed("日本")),
                session: .ready
            ),
            .hostStateChanged
        )
        XCTAssertEqual(
            policy.action(
                for: KeyboardInput(keyCode: 0),
                session: .ready
            ),
            .hostStateChanged
        )
    }

    func testSpaceCannotBeLocallyPreviewedWhileGhostIsVisible() {
        let space = KeyboardInput(
            keyCode: 49,
            textInput: .committed(" ")
        )

        XCTAssertEqual(
            policy.action(for: space, session: .inactive),
            .hostText(" ")
        )
        XCTAssertEqual(
            policy.action(for: space, session: .activeWithoutGhost),
            .hostText(" ")
        )
        XCTAssertEqual(
            policy.action(for: space, session: .ghostVisible),
            .hostAmbiguousText
        )
        XCTAssertEqual(
            policy.action(for: space, session: .ready),
            .hostAmbiguousText
        )
    }

    @MainActor
    func testRapidTextInputPublishesEveryCommittedASCIIPayload() {
        var actions: [KeyboardAction] = []
        let monitor = KeyboardMonitor(
            sessionProvider: { .ready },
            actionHandler: {
                actions.append($0)
                return false
            }
        )

        for (keyCode, text) in [(Int64(3), "f"), (Int64(32), "u"), (Int64(0), "n")] {
            XCTAssertFalse(
                monitor.process(
                    KeyboardInput(keyCode: keyCode, textInput: .committed(text)),
                    phase: .keyDown
                )
            )
        }

        XCTAssertEqual(actions, [.hostText("f"), .hostText("u"), .hostText("n")])
    }

    func testCommitmentClassifierRequiresSafeASCIIKeyboardAndText() {
        let safe = KeyboardInputCommitmentClassifier {
            KeyboardInputSourceState(
                isASCIICapable: true,
                isNonComposingKeyboardLayout: true
            )
        }
        let japanese = KeyboardInputCommitmentClassifier {
            KeyboardInputSourceState(
                isASCIICapable: false,
                isNonComposingKeyboardLayout: false
            )
        }
        let unknown = KeyboardInputCommitmentClassifier { nil }

        XCTAssertEqual(safe.classify("f"), .committed("f"))
        XCTAssertEqual(safe.classify("é"), .unconfirmed("é", nonComposingLayout: true))
        XCTAssertEqual(japanese.classify("f"), .unconfirmed("f"))
        XCTAssertEqual(japanese.classify("日本"), .unconfirmed("日本"))
        XCTAssertEqual(unknown.classify("f"), .unconfirmed("f"))
        XCTAssertEqual(safe.classify(nil), .none)
    }
}
