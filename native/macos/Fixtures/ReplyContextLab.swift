import AppKit

// Standalone, synthetic QA surface. Not part of the shipped application.
// No network, capture, injection, or programmatic suggestion requests.
final class FlippedHistoryView: NSView { override var isFlipped: Bool { true } }

@main
@MainActor
final class ReplyContextLab: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let message = NSTextField(wrappingLabelWithString: "")
    private let editor = NSTextView()
    private let history = NSScrollView()
    private let historyDocument = FlippedHistoryView()
    private let longHistory = NSButton(checkboxWithTitle: "Long history", target: nil, action: nil)
    private var conversation: NSView!
    private let scenarios = NSSegmentedControl(labels: ["Investigation", "Recipe", "No context"], trackingMode: .selectOne, target: nil, action: nil)

    static func main() {
        let delegate = ReplyContextLab()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 760, height: 430),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Autocomplete Everywhere Reply Context QA"
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 430))
        content.setAccessibilityElement(true)
        content.setAccessibilityRole(.group)
        content.setAccessibilityLabel("Synthetic conversation")
        window.contentView = content
        conversation = content

        scenarios.frame = NSRect(x: 24, y: 375, width: 420, height: 28)
        scenarios.target = self
        scenarios.action = #selector(changeScenario)
        scenarios.selectedSegment = 0
        content.addSubview(scenarios)
        longHistory.frame = NSRect(x: 500, y: 375, width: 200, height: 28)
        longHistory.target = self
        longHistory.action = #selector(changeLayout)
        content.addSubview(longHistory)
        history.frame = NSRect(x: 24, y: 250, width: 712, height: 112)
        history.hasVerticalScroller = true
        historyDocument.frame = NSRect(x: 0, y: 0, width: 690, height: 4996)
        historyDocument.setAccessibilityElement(true)
        historyDocument.setAccessibilityRole(.group)
        for index in 0..<120 {
            let old = NSTextField(labelWithString: "Earlier synthetic message \(index)")
            old.frame = NSRect(x: 0, y: index * 40, width: 650, height: 32)
            historyDocument.addSubview(old)
        }
        history.documentView = historyDocument
        history.isHidden = true
        content.addSubview(history)

        message.frame = NSRect(x: 24, y: 260, width: 712, height: 88)
        message.font = .systemFont(ofSize: 16)
        message.setAccessibilityIdentifier("qa-source-message")
        content.addSubview(message)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 32, width: 712, height: 200))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        editor.frame = NSRect(x: 0, y: 0, width: 690, height: 200)
        editor.minSize = NSSize(width: 0, height: 200)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.font = .systemFont(ofSize: 16)
        editor.isRichText = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.setAccessibilityLabel("Your reply")
        editor.setAccessibilityIdentifier("qa-reply-editor")
        scroll.documentView = editor
        // Native wrappers emulate deeply nested editor containers without
        // introducing any app-specific semantic classification.
        var wrapper = NSView(frame: scroll.frame)
        wrapper.setAccessibilityElement(true)
        wrapper.setAccessibilityRole(.group)
        content.addSubview(wrapper)
        for _ in 0..<8 {
            let child = NSView(frame: wrapper.bounds)
            child.setAccessibilityElement(true)
            child.setAccessibilityRole(.group)
            wrapper.addSubview(child)
            wrapper = child
        }
        scroll.frame = wrapper.bounds
        wrapper.addSubview(scroll)
        changeScenario()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func changeLayout() {
        message.removeFromSuperview()
        if longHistory.state == .on {
            message.frame = NSRect(x: 0, y: 4900, width: 670, height: 88)
            historyDocument.addSubview(message)
            history.isHidden = false
            historyDocument.scroll(NSPoint(x: 0, y: 4884))
        } else {
            history.isHidden = true
            message.frame = NSRect(x: 24, y: 260, width: 712, height: 88)
            conversation.addSubview(message)
        }
        window.makeFirstResponder(editor)
    }

    @objc private func changeScenario() {
        message.isHidden = scenarios.selectedSegment == 2
        message.stringValue = scenarios.selectedSegment == 0
            ? "Asistente: Puedo comparar los intentos exitosos y fallidos para investigar la causa. ¿Querés que lo haga?"
            : "Asistente: Puedo preparar una receta de torta de chocolate sin nueces. ¿Querés que la escriba?"
        editor.string = "si"
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        window.makeFirstResponder(editor)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
