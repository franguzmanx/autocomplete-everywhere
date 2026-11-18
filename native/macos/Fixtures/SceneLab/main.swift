import AppKit

final class SceneGroup: NSView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? { subviews }
}

@MainActor
final class SceneLab: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let source = NSTextField(wrappingLabelWithString: "")
    private let thread = NSTextField(labelWithString: "Project Jacaranda • Dana")
    private let draft = NSTextView()
    private var revision = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 760, height: 590), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Autocomplete Everywhere Scene Lab — generic Accessibility fixture"
        window.isReleasedWhenClosed = false
        let root = SceneGroup(frame: NSRect(x: 0, y: 0, width: 760, height: 590))
        root.setAccessibilityLabel("Writing situation")
        window.contentView = root

        let heading = NSTextField(labelWithString: "Source → draft")
        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        heading.frame = NSRect(x: 28, y: 530, width: 650, height: 34)
        root.addSubview(heading)

        let messageGroup = SceneGroup(frame: NSRect(x: 28, y: 322, width: 704, height: 186))
        messageGroup.setAccessibilityLabel("Read-only message group")
        root.addSubview(messageGroup)
        thread.frame = NSRect(x: 12, y: 145, width: 670, height: 24)
        thread.font = .systemFont(ofSize: 15, weight: .semibold)
        messageGroup.addSubview(thread)
        source.frame = NSRect(x: 12, y: 20, width: 670, height: 112)
        source.font = .systemFont(ofSize: 18)
        source.setAccessibilityIdentifier("scene-source")
        messageGroup.addSubview(source)
        updateSource()

        let scroll = NSScrollView(frame: NSRect(x: 28, y: 104, width: 704, height: 200))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        draft.frame = NSRect(x: 0, y: 0, width: 700, height: 196)
        draft.isRichText = false
        draft.font = .systemFont(ofSize: 19)
        draft.textContainerInset = NSSize(width: 12, height: 12)
        draft.isVerticallyResizable = true
        draft.isHorizontallyResizable = false
        draft.autoresizingMask = [.width]
        draft.textContainer?.widthTracksTextView = true
        draft.setAccessibilityLabel("Reply draft")
        draft.setAccessibilityIdentifier("scene-draft")
        scroll.documentView = draft
        root.addSubview(scroll)

        let change = NSButton(title: "Change source", target: self, action: #selector(changeSource))
        change.frame = NSRect(x: 28, y: 54, width: 164, height: 32)
        root.addSubview(change)
        let other = NSButton(title: "Other thread", target: self, action: #selector(otherThread))
        other.frame = NSRect(x: 204, y: 54, width: 164, height: 32)
        root.addSubview(other)
        let note = NSTextField(labelWithString: "Source buttons preserve your draft. This fixture has no send action or AI integration.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 28, y: 22, width: 704, height: 18)
        root.addSubview(note)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(draft)
    }

    private func updateSource() {
        source.stringValue = revision % 2 == 0
            ? "Dana: La entrega de Jacaranda es el martes 17 a las 14:00. ¿Puedes confirmar que prepararás la propuesta y traerás los planos?"
            : "Dana: Cambio confirmado: la entrega de Jacaranda será el jueves 19 a las 09:30. No traigas los planos; necesitamos el presupuesto revisado. ¿Puedes confirmarlo?"
        NSAccessibility.post(element: source, notification: .valueChanged)
    }

    @objc private func changeSource() {
        thread.stringValue = "Project Jacaranda • Dana"
        revision += 1
        updateSource()
        window.makeFirstResponder(draft)
    }

    @objc private func otherThread() {
        thread.stringValue = "Birthday dinner • Lucía"
        source.stringValue = "Lucía: Para la cena del sábado somos ocho. ¿Puedes traer una tarta de chocolate sin nueces? Llegamos a las 21:00."
        NSAccessibility.post(element: source, notification: .valueChanged)
        window.makeFirstResponder(draft)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SceneLabMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = SceneLab()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
