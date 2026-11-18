import Foundation
import XCTest
@testable import AutocompleteHelper

final class TransformControllerTests: XCTestCase {
    @MainActor
    func testContextRevocationCancelsMatchingRewriteAndRejectsItsLateResult() async throws {
        let writer = TransformTestWriter()
        let queue = TransformTestQueue()
        let snapshot = Self.snapshot()
        let controller = TransformController(capture: { .captured(snapshot) }, replace: { _, _, _ in
            XCTFail("Revoked context must not authorize insertion")
            return .writeFailed
        }, background: { queue.append($0) }, writer: writer, suspendSuggestions: { _ in })
        controller.configure([.init(id: UUID().uuidString, name: "Polish", key: 1)])
        controller.setEnabled(true)
        _ = controller.handle(.init(keyCode: 18, modifiers: [.option]))
        queue.runNext(); await Self.drainMain()
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.invalidateContext(requestIds: [UUID().uuidString])
        XCTAssertTrue(controller.isActive)
        controller.invalidateContext(requestIds: [identity.requestId])
        XCTAssertFalse(controller.isActive)
        controller.receive(.init(identity: identity, text: "Late rewritten text"))
        for _ in 0..<4 { queue.runNext(); await Self.drainMain() }
        XCTAssertEqual(writer.cancellations.count, 1)
    }

    @MainActor
    func testTransientValidationReadDoesNotDiscardPendingRewrite() async throws {
        let writer = TransformTestWriter()
        let queue = TransformTestQueue()
        let reads = RewriteReadSequence([.captured(Self.snapshot()), .skipped(.markerReadFailed)])
        let controller = TransformController(capture: { reads.next() }, replace: { _, _, _ in .writeFailed },
            background: { queue.append($0) }, writer: writer, suspendSuggestions: { _ in })
        controller.configure([.init(id: UUID().uuidString, name: "Polish", key: 1)])
        controller.setEnabled(true)
        _ = controller.handle(.init(keyCode: 18, modifiers: [.option]))
        queue.runNext(); await Self.drainMain()
        XCTAssertEqual(writer.requests.count, 1)
        controller.validateTarget()
        queue.runNext(); await Self.drainMain()
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(writer.cancellations.isEmpty)
        controller.cancel()
    }

    @MainActor
    func testSecureFieldValidationCancelsPendingRewrite() async throws {
        let writer = TransformTestWriter()
        let queue = TransformTestQueue()
        let reads = RewriteReadSequence([.captured(Self.snapshot()), .skipped(.secureField)])
        let controller = TransformController(capture: { reads.next() }, replace: { _, _, _ in .writeFailed },
            background: { queue.append($0) }, writer: writer, suspendSuggestions: { _ in })
        controller.configure([.init(id: UUID().uuidString, name: "Polish", key: 1)])
        controller.setEnabled(true)
        _ = controller.handle(.init(keyCode: 18, modifiers: [.option]))
        queue.runNext(); await Self.drainMain()
        XCTAssertEqual(writer.requests.count, 1)
        controller.validateTarget()
        queue.runNext(); await Self.drainMain()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(writer.cancellations.count, 1)
        controller.cancel()
    }

    @MainActor
    func testCompletedRewriteReplacesSelectionWithoutAnotherKeystroke() async throws {
        let writer = TransformTestWriter()
        let queue = TransformTestQueue()
        let snapshot = Self.snapshot()
        let writes = TransformTestWrites()
        let controller = TransformController(capture: { .captured(snapshot) }, replace: { text, target, isCurrent in
            XCTAssertTrue(isCurrent())
            XCTAssertEqual(target.selectionRange, snapshot.selectionRange)
            writes.texts.append(text)
            return .inserted(method: .accessibility, snapshot: target)
        }, background: { queue.append($0) }, writer: writer, suspendSuggestions: { _ in })
        controller.configure([.init(id: UUID().uuidString, name: "Polish", key: 1)])
        controller.setEnabled(true)
        XCTAssertTrue(controller.handle(.init(keyCode: 18, modifiers: [.option])))
        queue.runNext(); await Self.drainMain()
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.receive(.init(identity: identity, text: "Rewritten"))
        controller.receive(.init(identity: identity, text: "Rewritten"))
        for _ in 0..<4 { queue.runNext(); await Self.drainMain() }
        XCTAssertEqual(writes.texts, ["Rewritten"], "Duplicate results must not replace twice")
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.handle(.init(keyCode: 48)), "Tab remains the host key after replacement")
    }

    @MainActor
    func testEscapeDiscardsLateResultsWithoutWriting() async throws {
        let writer = TransformTestWriter()
        let queue = TransformTestQueue()
        let snapshot = Self.snapshot()
        let controller = TransformController(capture: { .captured(snapshot) }, replace: { _, _, _ in
            XCTFail("Cancelled transformation must never write")
            return .writeFailed
        }, background: { queue.append($0) }, writer: writer, suspendSuggestions: { _ in })
        controller.configure([.init(id: UUID().uuidString, name: "Polish", key: 1)])
        controller.setEnabled(true)
        XCTAssertTrue(controller.handle(.init(keyCode: 18, modifiers: [.option])))
        queue.runNext()
        await Self.drainMain()
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        XCTAssertTrue(controller.handle(.init(keyCode: 53)))
        controller.receive(.init(identity: identity, text: "Rewritten"))
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(writer.cancellations.count, 1)
        XCTAssertFalse(controller.handle(.init(keyCode: 48)))
    }

    @MainActor
    func testCancellationBeforeDirectInsertionQueueRunsPreventsTheWrite() async throws {
        let writer = TransformTestWriter()
        let queue = TransformTestQueue()
        let snapshot = Self.snapshot()
        let controller = TransformController(capture: { .captured(snapshot) }, replace: { _, _, _ in
            XCTFail("A cancelled insertion reservation must never write")
            return .writeFailed
        }, background: { queue.append($0) }, writer: writer, suspendSuggestions: { _ in })
        controller.configure([.init(id: UUID().uuidString, name: "Polish", key: 1)])
        controller.setEnabled(true)
        _ = controller.handle(.init(keyCode: 18, modifiers: [.option]))
        queue.runNext(); await Self.drainMain()
        let identity = try XCTUnwrap(writer.requests.last?.identity)
        controller.receive(.init(identity: identity, text: "Rewritten"))
        queue.runNext(); await Self.drainMain()
        controller.cancel()
        queue.runNext(); await Self.drainMain()
        XCTAssertFalse(controller.isActive)
    }

    @MainActor
    func testSecureOrUnavailableCaptureNeverMakesARequest() async {
        let writer = TransformTestWriter()
        let queue = TransformTestQueue()
        let controller = TransformController(capture: { .skipped(.secureField) }, replace: { _, _, _ in .writeFailed },
            background: { queue.append($0) }, writer: writer, suspendSuggestions: { _ in })
        controller.configure([.init(id: UUID().uuidString, name: "Polish", key: 1)])
        controller.setEnabled(true)
        _ = controller.handle(.init(keyCode: 18, modifiers: [.option]))
        queue.runNext(); await Self.drainMain()
        XCTAssertTrue(writer.requests.isEmpty)
        XCTAssertFalse(controller.isActive)
    }

    private static func drainMain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    private static func snapshot() -> ActiveFieldSnapshot {
        ActiveFieldSnapshot(applicationBundleIdentifier: "com.apple.Notes", surface: .native,
            elementIdentifier: "synthetic-field", focusGeneration: 1, textBefore: "", selectedText: "Original", textAfter: "",
            selectionRange: NSRange(location: 0, length: 8), caretBounds: nil, geometryQuality: .unavailable)
    }
}

private final class TransformTestWriter: TransformMessageWriting, @unchecked Sendable {
    var requests: [TransformRequestMessage] = []
    var cancellations: [CancelRequestMessage] = []
    func writeTransformRequest(_ message: TransformRequestMessage) { requests.append(message) }
    func writeCancelRequest(_ message: CancelRequestMessage) { cancellations.append(message) }
}
private final class TransformTestQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable () -> Void] = []
    func append(_ work: @escaping @Sendable () -> Void) { lock.withLock { pending.append(work) } }
    func runNext() {
        let work = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        work?()
    }
}

private final class TransformTestWrites: @unchecked Sendable { var texts: [String] = [] }

private final class RewriteReadSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ActiveFieldCaptureResult]
    init(_ results: [ActiveFieldCaptureResult]) { self.results = results }
    func next() -> ActiveFieldCaptureResult { lock.withLock { results.isEmpty ? .skipped(.markerReadFailed) : results.removeFirst() } }
}
