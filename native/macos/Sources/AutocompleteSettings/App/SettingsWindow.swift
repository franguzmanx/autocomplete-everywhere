import AppKit
import SwiftUI

@MainActor
enum SettingsWindow {
    static let initialSize = NSSize(width: 920, height: 680)
    static let minimumSize = NSSize(width: 760, height: 560)

    static func make(store: SettingsStore) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = store.l10n[.windowTitle]
        window.titleVisibility = .hidden
        window.contentMinSize = minimumSize
        window.isOpaque = false
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("autocompletion-settings-window")

        let hosting = NSHostingController(rootView: RootView().environment(store))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(initialSize)
        return window
    }
}
