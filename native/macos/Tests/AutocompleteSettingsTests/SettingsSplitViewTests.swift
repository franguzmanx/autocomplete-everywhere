import AppKit
import XCTest
@testable import AutocompleteSettings

@MainActor
final class SettingsSplitViewTests: XCTestCase {
    func testSidebarUsesFlushNativeMaterialAndKeepsDetailRoomAtMinimumWidth() {
        _ = NSApplication.shared
        let controller = SettingsSplitController(store: SettingsStore(transport: FakeTransport()))
        controller.view.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.adjustSubviews()

        XCTAssertEqual(controller.splitViewItems.count, 2)
        let sidebar = controller.splitViewItems[0]
        let material = sidebar.viewController.view as? NSVisualEffectView
        XCTAssertNotNil(material)
        XCTAssertEqual(material?.material, .sidebar)
        XCTAssertEqual(material?.blendingMode, .behindWindow)
        XCTAssertEqual(sidebar.behavior, .default)
        XCTAssertEqual(controller.splitView.subviews[0].frame.minX, 0, accuracy: 1)
        XCTAssertGreaterThanOrEqual(controller.splitView.subviews[0].frame.width, 184)
        XCTAssertLessThanOrEqual(controller.splitView.subviews[0].frame.width, 240)
        XCTAssertGreaterThanOrEqual(controller.splitView.subviews[1].frame.width, 500)
    }

    func testWindowKeepsNativeChromeAcrossSections() async throws {
        _ = NSApplication.shared
        let store = SettingsStore(transport: FakeTransport())
        var status = try Fixtures.status()
        status.uiLanguage = .en
        status.permissions.inputMonitoring = .granted
        status.pausedUntil = nil
        status.connection = .ready
        status.shortcutRegistered = true
        store.apply(.state(status, entries: [], transforms: Fixtures.transforms))
        let window = SettingsWindow.make(store: store)
        defer { window.close() }
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.backgroundColor, .windowBackgroundColor)

        // Opt-in QA captures only this synthetic offscreen window by its own ID, never the desktop.
        if let path = ProcessInfo.processInfo.environment["AUTOCOMPLETION_SETTINGS_RENDER_PATH"] {
            try captureSyntheticWindow(window, to: path)
            window.setContentSize(SettingsWindow.minimumSize)
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            try captureSyntheticWindow(window, to: path.replacingOccurrences(of: ".png", with: "-minimum.png"))
        }
        store.navigate(.section(.rewrites))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.title, store.l10n[.sectionRewrites])
        if let path = ProcessInfo.processInfo.environment["AUTOCOMPLETION_SETTINGS_RENDER_PATH"] {
            try captureSyntheticWindow(window, to: path.replacingOccurrences(of: ".png", with: "-rewrites.png"))
        }
        store.navigate(.section(.library))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.title, store.l10n[.sectionLibrary])
        if let path = ProcessInfo.processInfo.environment["AUTOCOMPLETION_SETTINGS_RENDER_PATH"] {
            try captureSyntheticWindow(window, to: path.replacingOccurrences(of: ".png", with: "-library.png"))
        }
        store.navigate(.section(.applications))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.titleVisibility, .hidden)
        if let path = ProcessInfo.processInfo.environment["AUTOCOMPLETION_SETTINGS_RENDER_PATH"] {
            try captureSyntheticWindow(window, to: path.replacingOccurrences(of: ".png", with: "-applications.png"))
        }
        // General with something to recover from: signed out while paused.
        status.account.state = .signedOut
        status.enabled = false
        store.apply(.state(status, entries: [], transforms: Fixtures.transforms))
        store.navigate(.section(.general))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.title, store.l10n[.sectionGeneral])
        if let path = ProcessInfo.processInfo.environment["AUTOCOMPLETION_SETTINGS_RENDER_PATH"] {
            try captureSyntheticWindow(window, to: path.replacingOccurrences(of: ".png", with: "-attention.png"))
        }
    }

    private func captureSyntheticWindow(_ window: NSWindow, to path: String) throws {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
    }

    func testSidebarRemainsVisible() {
        _ = NSApplication.shared
        let controller = SettingsSplitController(store: SettingsStore(transport: FakeTransport()))
        _ = controller.view
        let sidebar = controller.splitViewItems[0]
        XCTAssertFalse(sidebar.isCollapsed)
        XCTAssertFalse(sidebar.canCollapse)
    }
}
