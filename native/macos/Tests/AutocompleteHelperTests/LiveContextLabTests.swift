import AppKit
import ApplicationServices
import XCTest
@testable import AutocompleteHelper

/// Opt-in checks against the separate local dev/context-lab.cjs fixture only.
/// Never accepts a process ID or application name from the environment.
final class LiveContextLabTests: XCTestCase {
    func testCapturesCurrentConversationThroughNestedEditor() throws {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_CONTEXT_LAB"] == "1" else {
            throw XCTSkip("Run the controlled Electron Context Lab first")
        }
        let phase = ProcessInfo.processInfo.environment["AUTOCOMPLETION_CONTEXT_LAB_PHASE"] ?? "proposal"
        let expected: String
        let forbidden: String
        switch phase {
        case "proposal": expected = "Thursday at 16:00"; forbidden = "Monday at 10:00"
        case "revised": expected = "Monday at 10:00"; forbidden = "Thursday at 16:00"
        case "dinner": expected = "chocolate cake without nuts"; forbidden = "Jacaranda"
        default: return XCTFail("Unknown controlled fixture phase")
        }
        let (reader, field) = try controlledDraft()
        var foundMessage = false
        for _ in 0..<10 {
            let started = ProcessInfo.processInfo.systemUptime
            let sources = reader.sourceContexts(for: field)
            print("Context Lab sample: sources=\(sources.count), hint=\(sources.contains { $0.text == "Markdown formatting is available." }), ms=\((ProcessInfo.processInfo.systemUptime - started) * 1000)")
            foundMessage = sources.contains { $0.text.contains(expected) }
            if foundMessage {
                XCTAssertFalse(sources.contains { $0.text.contains(forbidden) }, "Previous message must not survive a source revision or conversation switch")
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(foundMessage, "Nearby composer chrome must not hide the current conversation")
    }

    func testColdElectronSourceAcquisitionAfterRuntimeDisplaySetup() throws {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_CONTEXT_LAB_COLD"] == "1" else {
            throw XCTSkip("Controlled Electron cold reads are opt-in")
        }
        let (setupReader, _) = try controlledDraft()
        _ = setupReader.displayGeometries()
        for sample in 0..<20 {
            let (reader, field) = try controlledDraft()
            let started = ProcessInfo.processInfo.systemUptime
            let sources = reader.sourceContexts(for: field)
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            print("Electron cold source: sample=\(sample), count=\(sources.count), ms=\(Int(elapsed))")
            XCTAssertTrue(sources.contains { $0.text.contains("Thursday at 16:00") }, "The first source read must find the visible controlled message")
        }
    }

    func testControlledElectronDraftExposesSelectionAndCaret() throws {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_CONTEXT_LAB"] == "1" else {
            throw XCTSkip("Run the controlled Electron Context Lab first")
        }
        var stage: WebTextReadStage?
        let (reader, field) = try controlledDraft(webDiagnostic: { stage = $0 })
        let context = reader.webTextContext(for: field)
        XCTAssertNotNil(context, "Controlled editor capture failed at \(stage?.rawValue ?? "unknown")")
        guard let context else { return }
        XCTAssertTrue(context.textBefore.hasPrefix("Autocomplete Everywhere QA — "))
        XCTAssertTrue(context.selectedText.isEmpty && context.textAfter.isEmpty, "Place the cursor at the end of the QA draft")
        let capture = ActiveFieldCapture(reader: reader)
        capture.updateConfiguration(.enabled)
        guard case let .captured(snapshot) = capture.capture() else { return XCTFail("Controlled web capture failed") }
        XCTAssertEqual(snapshot.surface, .web)
        XCTAssertNotNil(snapshot.caretBounds)
        XCTAssertNotEqual(snapshot.geometryQuality, .unavailable)
        print("Controlled Electron selection: stage=\(stage?.rawValue ?? "unknown"), caret=\(snapshot.caretBounds != nil), sources=\(snapshot.fieldContext.sources.count)")
    }

    private func controlledDraft(webDiagnostic: ((WebTextReadStage) -> Void)? = nil) throws -> (SystemAccessibilityReader, AccessibilityElement) {
        let fixture = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.Electron")
                .first { app in
                    let root = AXUIElementCreateApplication(app.processIdentifier)
                    guard let window = self.attribute("AXFocusedWindow", from: root),
                          CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
                    return self.attribute("AXTitle", from: window as! AXUIElement) as? String == "Autocomplete Everywhere Context Lab"
                },
            "The controlled Context Lab must be running"
        )
        let root = AXUIElementCreateApplication(fixture.processIdentifier)
        let reader = SystemAccessibilityReader(focusedApplicationProvider: { root }, webReadDiagnostic: webDiagnostic)
        reader.prepareFrontmostWebContent()
        let focused = try XCTUnwrap(reader.focusedElement())
        let field = reader.prepareWebContent(for: focused)
        XCTAssertEqual(reader.role(for: field), "AXTextArea")
        XCTAssertTrue(reader.stringValue(for: field)?.hasPrefix("Autocomplete Everywhere QA — ") == true, "Focus the controlled QA draft")
        return (reader, field)
    }

    private func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }
}
