@preconcurrency import ApplicationServices
@preconcurrency import Carbon
import Foundation
import ShortcutRules

struct KeyboardModifiers: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let command = Self(rawValue: 1 << 0)
    static let control = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

struct InteractionKeyBinding: Decodable, Equatable, Sendable {
    let keyCode: Int64
    let modifiers: Int

    static let acceptDefault = Self(keyCode: 48, modifiers: 0)
    static let dismissDefault = Self(keyCode: 53, modifiers: 0)
    var isValid: Bool {
        !ShortcutReservation.isReserved(keyCode: Int(keyCode), modifiers: modifiers)
            && (0...127).contains(keyCode) && modifiers >= 0 && (modifiers & ~6912) == 0
            && ((modifiers & (256 | 2048 | 4096)) != 0 || (modifiers == 0 && [36, 48, 53, 124].contains(keyCode)))
    }
    func matches(_ input: KeyboardInput) -> Bool {
        var flags: KeyboardModifiers = []
        for (carbon, flag) in [(256, KeyboardModifiers.command), (512, .shift), (2048, .option), (4096, .control)] where modifiers & carbon != 0 {
            flags.insert(flag)
        }
        return input.keyCode == keyCode && input.modifiers == flags
    }
}

enum KeyboardTextInput: Equatable, Sendable {
    case none
    case unconfirmed(String, nonComposingLayout: Bool = false)
    case committed(String)
}

struct KeyboardInput: Equatable, Sendable {
    let keyCode: Int64
    let modifiers: KeyboardModifiers
    let isRepeat: Bool
    let textInput: KeyboardTextInput
    let isAutocompleteInsertion: Bool

    init(
        keyCode: Int64,
        modifiers: KeyboardModifiers = [],
        isRepeat: Bool = false,
        textInput: KeyboardTextInput = .none,
        isAutocompleteInsertion: Bool = false
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.textInput = textInput
        self.isAutocompleteInsertion = isAutocompleteInsertion
    }
}

struct KeyboardInputSourceState: Equatable, Sendable {
    let isASCIICapable: Bool
    let isNonComposingKeyboardLayout: Bool
}

struct KeyboardInputCommitmentClassifier: Sendable {
    typealias SourceStateProvider = @Sendable () -> KeyboardInputSourceState?

    private let sourceState: SourceStateProvider

    init(sourceState: @escaping SourceStateProvider) {
        self.sourceState = sourceState
    }

    func classify(_ text: String?) -> KeyboardTextInput {
        guard let text, !text.isEmpty else { return .none }
        let state = sourceState()
        guard let state,
              state.isASCIICapable,
              state.isNonComposingKeyboardLayout,
              text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E })
        else { return .unconfirmed(text, nonComposingLayout: state?.isNonComposingKeyboardLayout == true) }
        return .committed(text)
    }

    static let system = Self {
        guard let unmanagedSource = TISCopyCurrentKeyboardInputSource() else {
            return nil
        }
        let source = unmanagedSource.takeRetainedValue()
        guard let asciiPointer = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceIsASCIICapable
        ),
        let typePointer = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceType
        ) else { return nil }
        let ascii = Unmanaged<CFBoolean>.fromOpaque(asciiPointer)
            .takeUnretainedValue()
        let sourceType = Unmanaged<CFString>.fromOpaque(typePointer)
            .takeUnretainedValue()
        return KeyboardInputSourceState(
            isASCIICapable: CFBooleanGetValue(ascii),
            isNonComposingKeyboardLayout:
                sourceType == kTISTypeKeyboardLayout
        )
    }
}

enum KeyboardSessionStatus: Equatable, Sendable {
    case inactive
    case activeWithoutGhost
    case ghostVisible
    case ready
}

enum KeyboardAction: Equatable, Sendable {
    case hostText(String)
    case hostAmbiguousText
    case hostStateChanged
    /// The host view scrolled or otherwise moved its content without a
    /// content or focus change. The ghost hides and reacquires its anchor;
    /// the suggestion itself stays valid.
    case hostGeometryDisturbed
    case dismissSuggestion
    case acceptSuggestion
    case acceptNextWord
    case nextAlternative
    case previousAlternative
}

enum KeyboardEventPhase: Equatable, Sendable {
    case keyDown
    case keyUp
}

struct KeyboardEventPolicy: Sendable {
    var accept: InteractionKeyBinding = .acceptDefault
    var dismiss: InteractionKeyBinding = .dismissDefault
    private let returnKeyCodes: Set<Int64> = [36, 76]
    private let navigationOrDeletionKeyCodes: Set<Int64> = [
        48, 51, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126,
    ]

    func action(
        for input: KeyboardInput,
        session: KeyboardSessionStatus
    ) -> KeyboardAction {
        if input.modifiers == .option, !input.isRepeat,
           session == .ghostVisible || session == .ready {
            if input.keyCode == 125 { return .nextAlternative }
            if input.keyCode == 126 { return .previousAlternative }
        }
        if input.keyCode == 48,
           input.modifiers == .option,
           !input.isRepeat,
           session == .ready {
            return .acceptNextWord
        }
        if input.modifiers.isEmpty,
           !input.isRepeat,
           case .committed(" ") = input.textInput,
           session == .ghostVisible || session == .ready {
            return .hostAmbiguousText
        }
        if !input.isRepeat {
            if accept.matches(input), session == .ready { return .acceptSuggestion }
            if dismiss.matches(input), session == .ghostVisible || session == .ready { return .dismissSuggestion }
        }

        let commandLikeModifier = !input.modifiers.intersection([
            .command,
            .control,
        ]).isEmpty
        let isHostStateTransition = navigationOrDeletionKeyCodes.contains(input.keyCode)
            || returnKeyCodes.contains(input.keyCode)
            || commandLikeModifier
        if !isHostStateTransition,
           case let .committed(text) = input.textInput {
            return .hostText(text)
        }
        return .hostStateChanged
    }
}

@MainActor
final class KeyboardMonitor {
    typealias SessionProvider = @MainActor () -> KeyboardSessionStatus
    typealias ActionHandler = @MainActor (KeyboardAction) -> Bool

    var inputHandler: (@MainActor (KeyboardInput) -> Bool)?

    private var policy: KeyboardEventPolicy
    private let sessionProvider: SessionProvider
    private let actionHandler: ActionHandler
    private let onUserEdit: () -> Void
    private let inputCommitmentClassifier: KeyboardInputCommitmentClassifier
    private let consumedKeyLock = NSLock()
    private var consumedKeyCodes: Set<Int64> = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    init(
        policy: KeyboardEventPolicy = KeyboardEventPolicy(),
        inputCommitmentClassifier: KeyboardInputCommitmentClassifier = .system,
        sessionProvider: @escaping SessionProvider,
        actionHandler: @escaping ActionHandler,
        onUserEdit: @escaping () -> Void = {}
    ) {
        self.policy = policy
        self.inputCommitmentClassifier = inputCommitmentClassifier
        self.sessionProvider = sessionProvider
        self.actionHandler = actionHandler
        self.onUserEdit = onUserEdit
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardMonitorCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        let targetRunLoop = CFRunLoopGetMain()
        eventTap = tap
        runLoopSource = source
        runLoop = targetRunLoop
        CFRunLoopAddSource(targetRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func configure(accept: InteractionKeyBinding, dismiss: InteractionKeyBinding) {
        policy.accept = accept
        policy.dismiss = dismiss
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoop, let runLoopSource {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        consumedKeyLock.withLock { consumedKeyCodes.removeAll() }
    }

    @discardableResult
    func process(_ input: KeyboardInput, phase: KeyboardEventPhase) -> Bool {
        guard !input.isAutocompleteInsertion else { return false }
        if phase == .keyUp {
            return consumedKeyLock.withLock {
                consumedKeyCodes.remove(input.keyCode) != nil
            }
        }

        if consumedKeyLock.withLock({ consumedKeyCodes.contains(input.keyCode) }) {
            return true
        }

        if inputHandler?(input) == true {
            _ = consumedKeyLock.withLock { consumedKeyCodes.insert(input.keyCode) }
            return true
        }
        let action = policy.action(for: input, session: sessionProvider())
        // Signal edits without retaining key contents. Navigation, copy and
        // pointer events cannot establish authorship. Synthetic acceptance is
        // excluded by the runtime while insertion is in progress.
        let commandEdit = input.modifiers.contains(.command)
            && [6, 7, 9].contains(input.keyCode) // undo/redo, cut, paste
        // Non-ASCII layout output cannot predict the ghost, but can identify a
        // physical edit opportunity. IME/unknown sources never establish one:
        // AX may expose their preedit, so it is not evidence of committed writing.
        // Option-produced diacritics may also be dead-key preedit.
        let unpredictedLayoutEdit: Bool
        if case let .unconfirmed(text, nonComposingLayout: true) = input.textInput {
            unpredictedLayoutEdit = !input.modifiers.contains(.option) && !text.isEmpty
                && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                && ![48, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 115, 116, 119, 121, 123, 124, 125, 126].contains(input.keyCode)
        } else { unpredictedLayoutEdit = false }
        let ordinaryEdit = input.modifiers.intersection([.command, .control]).isEmpty
            && ([36, 76, 51, 117].contains(input.keyCode)
                || unpredictedLayoutEdit
                || { if case .hostText = action { return true }; return action == .hostAmbiguousText }())
        if action != .acceptSuggestion && action != .dismissSuggestion, commandEdit || ordinaryEdit { onUserEdit() }
        if case .hostText = action {
            _ = actionHandler(action)
            return false
        }
        if action == .hostStateChanged || action == .hostAmbiguousText
            || action == .hostGeometryDisturbed {
            _ = actionHandler(action)
            return false
        }
        guard actionHandler(action) else { return false }
        _ = consumedKeyLock.withLock {
            consumedKeyCodes.insert(input.keyCode)
        }
        return true
    }

    fileprivate func handle(_ event: CGEvent, type: CGEventType) -> Bool {
        let input = KeyboardInput(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            modifiers: Self.modifiers(from: event.flags),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            textInput: inputCommitmentClassifier.classify(
                type == .keyDown ? Self.unicodeText(from: event) : nil
            ),
            isAutocompleteInsertion: SyntheticInsertionEvent.isOwn(event)
        )
        return process(input, phase: type == .keyDown ? .keyDown : .keyUp)
    }

    fileprivate func enableAfterSystemDisable() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private static func modifiers(from flags: CGEventFlags) -> KeyboardModifiers {
        var modifiers: KeyboardModifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }

    private static func unicodeText(from event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(
            maxStringLength: 0,
            actualStringLength: &length,
            unicodeString: nil
        )
        guard length > 0 else { return nil }
        var codeUnits = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(
            maxStringLength: length,
            actualStringLength: &length,
            unicodeString: &codeUnits
        )
        let text = String(utf16CodeUnits: codeUnits, count: length)
        return text.isEmpty ? nil : text
    }

}

private func keyboardMonitorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            monitor.enableAfterSystemDisable()
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passUnretained(event)
    }

    let consumed = MainActor.assumeIsolated {
        monitor.handle(event, type: type)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
