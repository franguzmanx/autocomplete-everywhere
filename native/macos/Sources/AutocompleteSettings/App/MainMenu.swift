import AppKit

/// Standard application menus so copy/paste/undo, hiding and quitting behave like any Mac app.
/// Rebuilt whenever the UI language changes.
@MainActor
enum MainMenu {
    static let applicationName = "Autocomplete Everywhere"

    static func install(l10n: L10n) {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem(l10n: l10n))
        mainMenu.addItem(editMenuItem(l10n: l10n))
        mainMenu.addItem(windowMenuItem(l10n: l10n))
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = mainMenu.items.last?.submenu
    }

    private static func applicationMenuItem(l10n: L10n) -> NSMenuItem {
        let name = applicationName
        let menu = NSMenu(title: name)
        menu.addItem(
            withTitle: l10n.format(.menuHide, name),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = menu.addItem(
            withTitle: l10n[.menuHideOthers],
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: l10n[.menuShowAll],
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: l10n.format(.menuQuit, name),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func editMenuItem(l10n: L10n) -> NSMenuItem {
        let menu = NSMenu(title: l10n[.menuEdit])
        menu.addItem(withTitle: l10n[.undo], action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: l10n[.redo], action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: l10n[.cut], action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: l10n[.copy], action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: l10n[.paste], action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: l10n[.selectAll], action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func windowMenuItem(l10n: L10n) -> NSMenuItem {
        let menu = NSMenu(title: l10n[.menuWindow])
        menu.addItem(
            withTitle: l10n[.minimize],
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(
            withTitle: l10n[.close],
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
