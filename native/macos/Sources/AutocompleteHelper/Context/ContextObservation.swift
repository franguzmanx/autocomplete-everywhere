import AppKit
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

struct ContextObservationMessage: Encodable, Sendable {
    let protocolVersion = 5
    let type = "context_observation"
    let payload: Payload
    struct Source: Encodable, Sendable { let id: String; let text: String }
    struct Image: Encodable, Sendable { let mediaType = "image/jpeg"; let data: String }
    struct Payload: Encodable, Sendable {
        let appId: String
        let documentId: String
        let capturedAtMs: Int64
        let sources: [Source]
        let image: Image?
    }
}

struct ContextObservationPolicy {
    static func allows(configuration: CaptureConfiguration, appId: String, locked: Bool, secure: Bool) -> Bool {
        configuration.contextEnabled && configuration.allows(appId) && !locked && !secure
    }
    static func sourceTexts(_ text: String) -> [String] {
        var result: [String] = []; var chunk = ""; var units = 0; var total = 0
        for scalar in text.unicodeScalars {
            let length = scalar.value > 0xffff ? 2 : 1
            guard total + length <= 12_000 else { break }
            if units + length > 2_000 { result.append(chunk); chunk = ""; units = 0 }
            chunk.unicodeScalars.append(scalar); units += length; total += length
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
    static func childBudget(count: Int, inspected: Int, queued: Int, limit: Int = 256) -> (take: Int, complete: Bool) {
        let remaining = max(0, limit - inspected - queued)
        return (min(count, remaining), count <= remaining)
    }
    static func observedURL(_ raw: String?) -> String? {
        guard let raw, raw.count <= 2_000, let url = URL(string: raw),
            ["http", "https", "file"].contains(url.scheme?.lowercased() ?? ""),
            url.user == nil, url.password == nil else { return nil }
        return url.absoluteString
    }
    static func documentKey(url: String?, title: String) -> String {
        // A changed explicit document or title creates another source; old work remains in history.
        digest(url ?? (title.isEmpty ? "untitled-window" : title))
    }
    static func matchingWindowIndex(title: String, frame: CGRect, candidates: [(String, CGRect)]) -> Int? {
        let matches = candidates.indices.filter { candidates[$0].0 == title && candidates[$0].1 == frame }
        return matches.count == 1 ? matches[0] : nil
    }
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Configuration changes revoke the background actor synchronously, including during an AX scan.
private final class ContextCaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var value = CaptureConfiguration.disabled
    private var epoch = 0
    func update(_ value: CaptureConfiguration) {
        lock.withLock { self.value = value; epoch += 1 }
    }
    func snapshot() -> (CaptureConfiguration, Int) { lock.withLock { (value, epoch) } }
}

/// The main thread owns only scheduling and explicit permission prompts.
@MainActor final class ContextObserver {
    private var configuration = CaptureConfiguration.disabled
    private var timer: Timer?
    private let gate = ContextCaptureGate()
    private let worker: ContextCaptureWorker
    init(excludedPID: pid_t, writer: MessageWriter) {
        worker = ContextCaptureWorker(excludedPID: excludedPID, writer: writer, gate: gate)
    }
    func publishScreenPermission() { Task { await worker.publishScreenPermission() } }
    func requestScreenPermission() {
        guard configuration.isEnabled && configuration.contextEnabled else { return }
        _ = CGRequestScreenCaptureAccess()
        Task { await worker.publishScreenPermission(force: true) }
    }
    func configure(_ value: CaptureConfiguration) {
        guard configuration != value else { return }
        configuration = value
        gate.update(value)
        timer?.invalidate()
        timer = nil
        if value.isEnabled && value.contextEnabled {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [worker] _ in
                Task { await worker.capture() }
            }
        }
    }
}

/// AX handles are created and consumed on this serial actor. No AX object crosses into the UI.
private actor ContextCaptureWorker {
    private let gate: ContextCaptureGate
    private var configuration: CaptureConfiguration { gate.snapshot().0 }
    private var generation: Int { gate.snapshot().1 }
    private var observedGeneration = -1
    private var busy = false
    private var screenPermission: Bool?
    private var lastEmission = Date.distantPast
    private var lastDigest: String?
    private let session = UUID().uuidString
    private let excludedPID: pid_t
    private let writer: MessageWriter
    init(excludedPID: pid_t, writer: MessageWriter, gate: ContextCaptureGate) {
        self.excludedPID = excludedPID; self.writer = writer; self.gate = gate
    }
    func publishScreenPermission(force: Bool = false) {
        let granted = CGPreflightScreenCaptureAccess()
        guard force || screenPermission != granted else { return }
        screenPermission = granted
        try? writer.writeContextScreenPermission(granted: granted)
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
            let app = NSRunningApplication(processIdentifier: pid), permitted(app) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func frame(_ node: AXUIElement) -> CGRect? {
        guard let p = attribute(node, kAXPositionAttribute), let z = attribute(node, kAXSizeAttribute),
            CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(z) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(p, to: AXValue.self), .cgPoint, &point),
            AXValueGetValue(unsafeDowncast(z, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    private func visibleText(_ node: AXUIElement) -> String? {
        guard let rawRange = attribute(node, kAXVisibleCharacterRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(rawRange, to: AXValue.self), .cfRange, &range),
            range.location >= 0, range.length > 0 else { return nil }
        range.length = min(range.length, 12_000)
        guard let value = AXValueCreate(.cfRange, &range), let app = NSWorkspace.shared.frontmostApplication,
            permitted(app) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(node, kAXStringForRangeParameterizedAttribute as CFString, value, &result) == .success else { return nil }
        return result as? String
    }
    private var locked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return (session["CGSSessionScreenIsLocked"] as? Bool == true) || (session["kCGSessionOnConsoleKey"] as? Bool == false)
    }
    private func permitted(_ app: NSRunningApplication) -> Bool {
        guard let appId = app.bundleIdentifier, app.processIdentifier != excludedPID,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              AXIsProcessTrusted() else { return false }
        return ContextObservationPolicy.allows(configuration: configuration, appId: appId, locked: locked, secure: false)
    }
    func capture() async {
        publishScreenPermission()
        if observedGeneration != generation { observedGeneration = generation; lastDigest = nil }
        guard !busy, Date().timeIntervalSince(lastEmission) >= 2,
              let app = NSWorkspace.shared.frontmostApplication, permitted(app), let appId = app.bundleIdentifier else { return }
        lastEmission = Date()
        busy = true
        defer { busy = false }
        let epoch = generation
        let deadline = ProcessInfo.processInfo.systemUptime + 0.12
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.05)
        guard let rawWindow = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return }
        let window = unsafeDowncast(rawWindow, to: AXUIElement.self)
        // Inspect roles before values; secure subtrees never authorize text or image reads.
        if let focused = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
           attribute(unsafeDowncast(focused, to: AXUIElement.self), kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return }
        guard let windowFrame = frame(window) else { return }
        var safeForImage = true
        var queue = [window]
        var nodes: [AXUIElement] = []
        while !queue.isEmpty && nodes.count < 256 && ProcessInfo.processInfo.systemUptime < deadline {
            let node = queue.removeFirst()
            if attribute(node, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { safeForImage = false; continue }
            if attribute(node, "AXHidden") as? Bool == true { continue }
            nodes.append(node)
            if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                let budget = ContextObservationPolicy.childBudget(count: children.count, inspected: nodes.count, queued: queue.count)
                safeForImage = safeForImage && budget.complete
                queue.append(contentsOf: children.prefix(budget.take))
            }
        }
        safeForImage = safeForImage && queue.isEmpty
        let title = attribute(window, kAXTitleAttribute) as? String ?? ""
        func urlAttribute(_ node: AXUIElement, _ key: String) -> String? {
            let value = attribute(node, key)
            return ContextObservationPolicy.observedURL((value as? URL)?.absoluteString ?? value as? String)
        }
        var documentURL = urlAttribute(window, kAXDocumentAttribute)
        if documentURL == nil {
            let urlDeadline = ProcessInfo.processInfo.systemUptime + 0.05
            for node in nodes {
                guard ProcessInfo.processInfo.systemUptime < urlDeadline else { break }
                guard attribute(node, kAXRoleAttribute) as? String == "AXWebArea" else { continue }
                guard let bounds = frame(node), bounds.intersects(windowFrame) else { continue }
                if let url = urlAttribute(node, kAXURLAttribute) { documentURL = url; break }
            }
        }
        let documentId = "\(session):\(app.processIdentifier):\(CFHash(window)):\(ContextObservationPolicy.documentKey(url: documentURL, title: title))"
        var chunks: [String] = documentURL.map { [$0] } ?? []
        let textDeadline = ProcessInfo.processInfo.systemUptime + 0.12
        var seen = Set<String>()
        var remaining = 12_000
        for node in nodes {
            guard remaining > 0, ProcessInfo.processInfo.systemUptime < textDeadline else { break }
            // Visible descendants only; never traverse hidden documents or change selection.
            if attribute(node, "AXHidden") as? Bool == true { continue }
            guard let nodeFrame = frame(node), nodeFrame.width > 0, nodeFrame.height > 0, nodeFrame.intersects(windowFrame) else { continue }
            let role = attribute(node, kAXRoleAttribute) as? String
            if role == kAXTextAreaRole || role == kAXTextFieldRole {
                if let text = visibleText(node), !text.isEmpty, seen.insert(text).inserted {
                    let bounded = String(text.prefix(remaining)); chunks.append(bounded); remaining -= bounded.count
                }
            }
            let keys = role == kAXStaticTextRole ? [kAXValueAttribute, kAXTitleAttribute] : [kAXTitleAttribute]
            for key in keys {
                guard let value = attribute(node, key) as? String else { continue }
                let text = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(remaining))
                if !text.isEmpty && seen.insert(text).inserted { chunks.append(text); remaining -= text.count }
            }
        }
        var image: ContextObservationMessage.Image?
        if safeForImage && configuration.contextImagesEnabled && CGPreflightScreenCaptureAccess() {
            if let result = try? await captureImage(app: app, title: title, expectedWindow: window, frame: windowFrame, epoch: epoch) {
                image = result
            }
        }
        guard epoch == generation, permitted(app), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
        guard let currentWindow = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(currentWindow) == AXUIElementGetTypeID(),
            CFEqual(currentWindow, window) else { return }
        let sourceTexts = ContextObservationPolicy.sourceTexts(chunks.joined(separator: "\n"))
        let text = sourceTexts.joined()
        guard !text.isEmpty || image != nil else { return }
        let digest = ContextObservationPolicy.digest(documentId + text + (image?.data ?? ""))
        guard digest != lastDigest else { return }
        let payload = ContextObservationMessage.Payload(appId: appId, documentId: documentId,
            capturedAtMs: Int64(Date().timeIntervalSince1970 * 1_000),
            sources: sourceTexts.enumerated().map { index, value in
                .init(id: "\(documentId):\(digest):\(index)", text: value)
            }, image: image)
        do {
            try writer.writeContextObservation(.init(payload: payload))
            lastDigest = digest
            lastEmission = Date()
        } catch { writer.writeDiagnostic("context_observation_write_failed") }
    }
    private func captureImage(app: NSRunningApplication, title: String, expectedWindow: AXUIElement, frame expectedFrame: CGRect, epoch: Int) async throws -> ContextObservationMessage.Image? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard generation == epoch, permitted(app), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if let focus = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(focus) == AXUIElementGetTypeID(),
           attribute(unsafeDowncast(focus, to: AXUIElement.self), kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return nil }
        guard let currentWindow = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(currentWindow) == AXUIElementGetTypeID(),
            CFEqual(currentWindow, expectedWindow), frame(expectedWindow) == expectedFrame else { return nil }
        let candidates = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }
        guard let index = ContextObservationPolicy.matchingWindowIndex(title: title, frame: expectedFrame,
            candidates: candidates.map { ($0.title ?? "", $0.frame) }) else { return nil }
        let window = candidates[index]
        guard window.frame.width > 1, window.frame.height > 1 else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(1, 1280 / max(window.frame.width, window.frame.height))
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        let screenshot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: screenshot).representation(using: .jpeg, properties: [.compressionFactor: 0.6]), data.count <= 1_500_000 else { return nil }
        return .init(data: data.base64EncodedString())
    }
}
