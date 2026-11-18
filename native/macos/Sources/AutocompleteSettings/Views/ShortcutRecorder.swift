import AppKit
import ShortcutRules
import KeyboardShortcuts
import SwiftUI

enum SuggestionShortcutKind: String, Codable, CaseIterable, Sendable {
    case request, accept, dismiss
    var title: L10nKey { switch self { case .request: .askForSuggestion; case .accept: .acceptSuggestion; case .dismiss: .dismissSuggestion } }
    var defaultBinding: SuggestionKeyBinding? {
        switch self {
        case .request: .init(accelerator: "Command+Shift+Space", keyCode: 49, modifiers: 768)
        case .accept: .init(accelerator:"Tab",keyCode:48,modifiers:0)
        case .dismiss: .init(accelerator:"Escape",keyCode:53,modifiers:0)
        }
    }
}

struct SuggestionKeyBinding: Codable, Equatable, Sendable {
    var accelerator: String
    var keyCode: Int
    var modifiers: Int

    var isReserved: Bool { ShortcutReservation.isReserved(keyCode: keyCode, modifiers: modifiers) }

    var native: KeyboardShortcuts.Shortcut {
        .init(carbonKeyCode: keyCode, carbonModifiers: modifiers)
    }
    @MainActor var display: String { native.description }

    init(accelerator: String, keyCode: Int, modifiers: Int) {
        self.accelerator = accelerator
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    @MainActor init?(_ shortcut: KeyboardShortcuts.Shortcut, kind: SuggestionShortcutKind = .request) {
        let flags = shortcut.modifiers
        let localKey = kind != .request && flags.isEmpty && [.tab, .escape, .return, .rightArrow].contains(shortcut.key)
        guard localKey || !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        let special: [KeyboardShortcuts.Key: String] = [
            .space: "Space", .return: "Enter", .tab: "Tab", .escape: "Escape", .delete: "Backspace",
            .deleteForward: "Delete", .upArrow: "Up", .downArrow: "Down",
            .leftArrow: "Left", .rightArrow: "Right", .home: "Home", .end: "End",
            .pageUp: "PageUp", .pageDown: "PageDown",
            .f1: "F1", .f2: "F2", .f3: "F3", .f4: "F4", .f5: "F5",
            .f6: "F6", .f7: "F7", .f8: "F8", .f9: "F9", .f10: "F10",
            .f11: "F11", .f12: "F12", .f13: "F13", .f14: "F14", .f15: "F15",
            .f16: "F16", .f17: "F17", .f18: "F18", .f19: "F19", .f20: "F20",
        ]
        let key: String
        if let nativeKey = shortcut.key, let value = special[nativeKey] {
            key = value
        } else if let value = shortcut.nsMenuItemKeyEquivalent?.uppercased(),
                  value.range(of: "^[A-Z0-9]$", options: .regularExpression) != nil {
            key = value
        } else { return nil }
        let modifierNames: [(NSEvent.ModifierFlags, String)] = [
            (.command, "Command"), (.control, "Control"), (.option, "Alt"), (.shift, "Shift"),
        ]
        accelerator = (modifierNames.filter { flags.contains($0.0) }.map(\.1) + [key]).joined(separator: "+")
        keyCode = shortcut.carbonKeyCode
        modifiers = shortcut.carbonModifiers
    }
}

struct SuggestionShortcutRecorder: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    var kind: SuggestionShortcutKind = .request

    var body: some View {
        NativeShortcutRecorder(
            value: store.shortcut(for: kind)?.display ?? "—",
            title: l10n[kind.title],
            prompt: l10n[.pressShortcut],
            resetTitle: l10n[.resetShortcut],
            preparing: l10n[.preparingShortcut],
            unavailable: l10n[.shortcutConflict],
            help: l10n[.recordNativeShortcutHelp],
            onRecordingChange: { active in _ = try await store.request(.setShortcutRecording(active)) },
            onRecord: { native in
                guard let candidate = SuggestionKeyBinding(native, kind: kind) else {
                    return l10n[kind == .request ? .shortcutValidation : .interactionShortcutValidation]
                }
                guard !candidate.isReserved else { return l10n[.shortcutReserved] }
                guard !SuggestionShortcutKind.allCases.contains(where: {
                    $0 != kind && store.shortcut(for: $0)?.native == candidate.native
                }) else { return l10n[.shortcutActionConflict] }
                store.setShortcut(candidate, for: kind)
                return nil
            },
            onReset: { store.setShortcut(kind.defaultBinding, for: kind) }
        )
        .frame(width: 240, height: 28)
        .disabled(kind == .request ? store.pendingShortcut != nil : store.pendingInteractionShortcuts[kind] != nil)
    }
}

/// Global-hotkey recorders reserve Tab and Escape for navigation. This local
/// recorder must capture those keys because they are the product's defaults.
private struct NativeShortcutRecorder: NSViewRepresentable {
    let value: String
    let title: String
    let prompt: String
    let resetTitle: String
    let preparing: String
    let unavailable: String
    let help: String
    let onRecordingChange: (Bool) async throws -> Void
    let onRecord: (KeyboardShortcuts.Shortcut) -> String?
    let onReset: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl { ShortcutRecorderControl() }
    func updateNSView(_ view: ShortcutRecorderControl, context: Context) {
        view.configure(value: value, title: title, prompt: prompt, resetTitle: resetTitle, help: help,
                       preparing: preparing, unavailable: unavailable, enabled: context.environment.isEnabled,
                       onRecordingChange: onRecordingChange, onRecord: onRecord, onReset: onReset)
    }
    static func dismantleNSView(_ view: ShortcutRecorderControl, coordinator: ()) { view.stopRecording() }
}

@MainActor
final class ShortcutRecorderControl: NSStackView {
    let recordButton = NSButton()
    let resetButton = NSButton()
    private(set) var isRecording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var value = ""
    private var prompt = ""
    private var preparing = ""
    private var unavailable = ""
    private var onRecordingChange: ((Bool) async throws -> Void)?
    private var onRecord: ((KeyboardShortcuts.Shortcut) -> String?)?
    private var onReset: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        recordButton.bezelStyle = .rounded
        recordButton.setButtonType(.momentaryPushIn)
        recordButton.target = self
        recordButton.action = #selector(beginRecording)
        resetButton.bezelStyle = .rounded
        resetButton.setButtonType(.momentaryPushIn)
        resetButton.target = self
        resetButton.action = #selector(reset)
        addArrangedSubview(recordButton)
        addArrangedSubview(resetButton)
        recordButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        recordButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    func configure(value: String, title: String, prompt: String, resetTitle: String, help: String, preparing: String, unavailable: String, enabled: Bool,
                   onRecordingChange: @escaping (Bool) async throws -> Void,
                   onRecord: @escaping (KeyboardShortcuts.Shortcut) -> String?, onReset: @escaping () -> Void) {
        self.value = value
        self.prompt = prompt
        self.preparing = preparing
        self.unavailable = unavailable
        self.onRecordingChange = onRecordingChange
        resetButton.title = resetTitle
        self.onRecord = onRecord
        self.onReset = onReset
        recordButton.setAccessibilityLabel(title)
        if recordButton.toolTip != help { recordButton.toolTip = help }
        resetButton.setAccessibilityLabel(title + " — " + resetTitle)
        if resetButton.toolTip != resetTitle { resetButton.toolTip = resetTitle }
        recordButton.isEnabled = enabled
        resetButton.isEnabled = enabled
        if !isRecording { recordButton.title = value }
    }

    @objc func beginRecording() {
        stopRecording()
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(recordButton)
        isRecording = true
        recordButton.title = preparing
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRecording() }
        }
        // Wait until the parent releases its global registration before asking
        // for keys. Otherwise recording the current shortcut triggers Autocomplete Everywhere.
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.onRecordingChange?(true)
                guard self.isRecording, self.window?.isKeyWindow == true else { return }
                self.recordButton.title = self.prompt
                self.installMonitor()
            } catch {
                self.stopRecording()
                self.showError(self.unavailable)
            }
        }
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            guard event.type == .keyDown || event.type == .flagsChanged else {
                self.stopRecording()
                return event
            }
            // Modifier and shortcut events may have no window association.
            // This is an application-local monitor; key-window ownership is sufficient.
            guard self.window?.isKeyWindow == true else {
                self.stopRecording()
                return event
            }
            if event.type == .flagsChanged {
                let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                let held = symbols.filter { event.modifierFlags.contains($0.0) }.map(\.1).joined()
                self.recordButton.title = held.isEmpty ? self.prompt : held + "…"
                return event
            }
            guard !event.isARepeat, let shortcut = KeyboardShortcuts.Shortcut(event: event) else { return nil }
            self.stopRecording()
            if let error = self.onRecord?(shortcut) { self.showError(error) }
            return nil
        }
    }

    private func showError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window)
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        let wasRecording = isRecording
        isRecording = false
        recordButton.title = value
        if wasRecording, let onRecordingChange {
            Task { try? await onRecordingChange(false) }
        }
    }

    @objc private func reset() { stopRecording(); onReset?() }
}
