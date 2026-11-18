import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let transport = PipeTransport()
    private(set) lazy var store = SettingsStore(
        transport: transport,
        diagnostics: { [transport] code in transport.diagnostic(code) }
    )
    private var window: NSWindow?
    private var terminatingAfterPipeClosed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MainMenu.install(l10n: store.l10n)
        observeLanguage()

        store.onShowRequested = { [weak self] in self?.showWindow() }
        store.onConnectionClosed = { [weak self] in
            guard let self else { return }
            terminatingAfterPipeClosed = true
            NSApp.terminate(nil)
        }

        let window = SettingsWindow.make(store: store)
        window.delegate = self
        self.window = window
        showWindow()
        store.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !terminatingAfterPipeClosed && store.writingSaving { return .terminateCancel }
        guard !terminatingAfterPipeClosed, store.hasUnsavedChanges else { return .terminateNow }
        return confirmDiscard(
            title: store.l10n[.quitUnsavedTitle],
            detail: store.l10n[.quitUnsavedDetail],
            confirm: store.l10n[.quit]
        ) ? .terminateNow : .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !store.writingSaving else { return false }
        guard store.hasUnsavedChanges else { return true }
        let discard = confirmDiscard(
            title: store.l10n[.unsavedTitle],
            detail: store.l10n[.unsavedDetail],
            confirm: store.l10n[.discard]
        )
        if discard { store.discardWritingChanges(); store.closeEditor() }
        return discard
    }

    private func showWindow() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirmDiscard(title: String, detail: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: store.l10n[.keepEditing])
        if let window {
            return runSheet(alert, on: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func runSheet(_ alert: NSAlert, on window: NSWindow) -> NSApplication.ModalResponse {
        var response: NSApplication.ModalResponse = .cancel
        alert.beginSheetModal(for: window) { result in
            response = result
            NSApp.stopModal(withCode: result)
        }
        NSApp.runModal(for: alert.window)
        return response
    }

    private func observeLanguage() {
        withObservationTracking {
            _ = store.language
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                MainMenu.install(l10n: self.store.l10n)
                self.observeLanguage()
            }
        }
    }
}
