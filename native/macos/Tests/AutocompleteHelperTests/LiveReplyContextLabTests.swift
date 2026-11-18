import AppKit
import ApplicationServices
import XCTest
@testable import AutocompleteHelper

/// Read-only integration test restricted to our standalone synthetic fixture.
/// Does not accept arbitrary app IDs/PIDs or synthesize input.
final class LiveReplyContextLabTests: XCTestCase {
    func testColdSourceAcquisition() throws {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_REPLY_CONTEXT_COLD"] == "1" else {
            throw XCTSkip("Owned fixture cold-read measurement is opt-in")
        }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.autocompletion.qa.replycontext").first)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Mirror HelperRuntime.start: AppKit display setup precedes capture.
        let setupStart = ProcessInfo.processInfo.systemUptime
        _ = SystemAccessibilityReader(focusedApplicationProvider: { root }).displayGeometries()
        print("QA display initialization elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - setupStart) * 1000))")
        for sample in 0..<20 {
            var outcome: SourceReadOutcome?
            let reader = SystemAccessibilityReader(focusedApplicationProvider: { root }, sourceReadDiagnostic: { outcome = $0 })
            let field = try XCTUnwrap(reader.focusedElement())
            let start = ProcessInfo.processInfo.systemUptime
            let sources = reader.sourceContexts(for: field)
            let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
            print("QA cold read: sample=\(sample) count=\(sources.count) outcome=\(outcome?.rawValue ?? "unknown") elapsedMs=\(Int(milliseconds))")
            XCTAssertEqual(sources.count, 1, "Each fresh reader must acquire the single visible fixture source")
        }
    }

    func testLiveSourceChangesWithOneReader() throws {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_REPLY_CONTEXT_TRANSITIONS"] == "1" else {
            throw XCTSkip("Interactive fixture transition check is opt-in")
        }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.autocompletion.qa.replycontext").first)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let reader = SystemAccessibilityReader(focusedApplicationProvider: { root })
        let field = try XCTUnwrap(reader.focusedElement())
        var initial: [FieldSource] = []
        for _ in 0..<3 {
            initial = reader.sourceContexts(for: field)
            if !initial.isEmpty { break }
        }
        XCTAssertTrue(initial.contains { $0.text.contains("torta de chocolate") })
        var observedInvestigation = false
        var observedHidden = false
        let deadline = ProcessInfo.processInfo.systemUptime + 45
        while ProcessInfo.processInfo.systemUptime < deadline {
            let sources = reader.sourceContexts(for: field)
            if sources.contains(where: { $0.text.contains("intentos exitosos y fallidos") }) {
                observedInvestigation = true
                XCTAssertFalse(sources.contains { $0.text.contains("torta de chocolate") })
            }
            if observedInvestigation && sources.isEmpty {
                observedHidden = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(observedInvestigation, "Change Recipe to Investigation during the check")
        XCTAssertTrue(observedHidden, "Then hide the source with No context")
    }

    func testReadsOnlyTheCurrentSeparateSource() throws {
        guard ProcessInfo.processInfo.environment["AUTOCOMPLETION_REPLY_CONTEXT_LAB"] == "1" else {
            throw XCTSkip("Open the standalone Reply Context QA fixture first")
        }
        let scenario = ProcessInfo.processInfo.environment["AUTOCOMPLETION_REPLY_CONTEXT_SCENARIO"] ?? "investigation"
        guard ["investigation", "recipe", "none", "history"].contains(scenario) else { return XCTFail("Unknown fixture scenario") }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.autocompletion.qa.replycontext").first)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if ProcessInfo.processInfo.environment["AUTOCOMPLETION_REPLY_CONTEXT_DIAGNOSTICS"] == "1" {
            func attribute(_ name: String, _ node: AXUIElement) -> CFTypeRef? {
                var value: CFTypeRef?
                return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
            }
            var queue = [root]
            var index = 0
            while index < queue.count && index < 220 {
                let node = queue[index]; index += 1
                let children = attribute("AXChildren", node) as? [AXUIElement] ?? []
                if !children.isEmpty {
                    let role = attribute("AXRole", node) as? String ?? "unknown"
                    let visible = attribute("AXVisibleChildren", node) as? [AXUIElement]
                    let targetIndex = children.firstIndex { attribute("AXIdentifier", $0) as? String == "qa-source-message" }
                    print("QA structure: role=\(role) children=\(children.count) visible=\(visible?.count ?? -1) targetIndex=\(targetIndex ?? -1)")
                    queue.append(contentsOf: children)
                }
            }
        }
        let reader = SystemAccessibilityReader(focusedApplicationProvider: { root })
        let field = try XCTUnwrap(reader.focusedElement())
        XCTAssertTrue(["si", "si,", "si, "].contains(reader.stringValue(for: field) ?? ""), "The fixture draft must remain synthetic")
        var sources: [FieldSource] = []
        for _ in 0..<3 {
            sources = reader.sourceContexts(for: field)
            if !sources.isEmpty || scenario == "none" { break }
        }
        if scenario == "none" {
            XCTAssertTrue(sources.isEmpty, "Hidden source must be excluded")
        } else if scenario == "history" {
            XCTAssertFalse(sources.isEmpty, "Visible middle-history messages were not captured")
            XCTAssertLessThanOrEqual(sources.count, 6)
            XCTAssertTrue(sources.allSatisfy { $0.text.hasPrefix("Earlier synthetic message ") })
            XCTAssertFalse(sources.contains { $0.text.contains("intentos exitosos y fallidos") || $0.text.contains("torta de chocolate") }, "Offscreen latest message must be excluded")
        } else {
            XCTAssertEqual(sources.count, 1)
            XCTAssertEqual(sources.first?.relation, .sharedContainer)
            let expected = scenario == "recipe" ? "torta de chocolate sin nueces" : "intentos exitosos y fallidos"
            let forbidden = scenario == "recipe" ? "intentos exitosos y fallidos" : "torta de chocolate sin nueces"
            XCTAssertTrue(sources.contains { $0.text.contains(expected) }, "Current source was not captured")
            XCTAssertFalse(sources.contains { $0.text.contains(forbidden) }, "Previous conversation source leaked")
        }
    }
}
