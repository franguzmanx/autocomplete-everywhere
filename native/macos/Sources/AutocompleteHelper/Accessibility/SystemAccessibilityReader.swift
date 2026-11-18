import CryptoKit
import AppKit
import ApplicationServices
import Foundation

struct AppKitScreenDescriptor: Equatable, Sendable {
    let frame: CGRect
    let backingScaleFactor: CGFloat
}

struct AccessibilityTraversalNode: Hashable {
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

struct RelatedEditableTopology {
    let element: AXUIElement
    let shape: ActiveFieldShape
    let label: String?
    let placeholder: String?
}

struct RelatedFieldScanState {
    let key: String
    var expiresAt: TimeInterval
    var traversal: EditableNeighborhoodTraversal<AccessibilityTraversalNode>
    var editables: [RelatedEditableTopology]
    var totalVisits: Int
    var isComplete: Bool
    var foundSecureField: Bool
    var previousEditables: [RelatedEditableTopology]? = nil

    var visibleEditables: [RelatedEditableTopology] {
        guard !foundSecureField else { return [] }
        return isComplete ? editables : (previousEditables ?? editables)
    }

    mutating func restartTraversal(seeds: [EditableNeighborhoodTraversal<AccessibilityTraversalNode>.Seed], at now: TimeInterval) {
        // A partial refresh is not a new topology. Continue reading the live
        // values of known controls until the replacement scan completes.
        previousEditables = visibleEditables
        traversal = EditableNeighborhoodTraversal(seeds: seeds)
        editables = []
        totalVisits = 0
        isComplete = false
        foundSecureField = false
        expiresAt = now + 2
    }
}

/// Categorical outcomes from values already read by the normal capture path.
/// Contains no text, identity, coordinates, or additional Accessibility reads.
struct WebCaretEvidence: Equatable, Sendable {
    let markerSelectionMatches: Bool
    let nodeValueMatches: Bool
    let lineValueMatches: Bool
    let nodeContained: Bool
    let nodeIsText: Bool
    let nodeCandidateAvailable: Bool
    let nodeCandidateSelected: Bool
}

enum SourceReadOutcome: String {
    case available
    case noVisibleSources = "no_visible_sources"
    case deadline
}

struct WebTextMarkerReadBudget {
    static let bootstrapTimeout: Float = 6
    static let steadyStateTimeout: Float = 0.5

    private var readyProcessIdentifiers: Set<pid_t> = []

    func timeout(for processIdentifier: pid_t) -> Float {
        readyProcessIdentifiers.contains(processIdentifier)
            ? Self.steadyStateTimeout
            : Self.bootstrapTimeout
    }

    mutating func recordSuccess(for processIdentifier: pid_t) {
        readyProcessIdentifiers.insert(processIdentifier)
    }
}

final class SystemAccessibilityReader: AccessibilityReading {
    /// Upper bound for one Accessibility round trip. The default (6 s) lets a
    /// busy host freeze the capture queue; a bounded failure is reported as a
    /// transient read failure instead.
    static let messagingTimeout: Float = 0.5
    private let manualAccessibilityLock = NSLock()
    private var preparedWebProcessIdentifiers: Set<pid_t> = []
    private var warmedWebProcessIdentifiers: Set<pid_t> = []
    private var webTextMarkerReadBudget = WebTextMarkerReadBudget()
    private let relatedFieldCacheLock = NSLock()
    private var relatedFieldScanState: RelatedFieldScanState?

    private let excludedProcessIdentifier: pid_t?
    private let focusedApplicationProvider: () -> AXUIElement?
    private let workspaceProcessProvider: () -> pid_t?
    private let webCaretDiagnostic: ((WebCaretEvidence) -> Void)?
    private let typographyDiagnostic: ((String) -> Void)?
    private let webReadDiagnostic: ((WebTextReadStage) -> Void)?
    private let sourceReadDiagnostic: ((SourceReadOutcome) -> Void)?
    private let focusDiagnostic: ((pid_t?, pid_t?) -> Void)?
    private let focusDiagnosticLock = NSLock()
    private var lastFocusDiagnosticKey: String?

    init(
        excludedProcessIdentifier: pid_t? = nil,
        focusedApplicationProvider: @escaping () -> AXUIElement? = SystemAccessibilityReader.systemFocusedApplication,
        workspaceProcessProvider: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        focusDiagnostic: ((pid_t?, pid_t?) -> Void)? = nil,
        webCaretDiagnostic: ((WebCaretEvidence) -> Void)? = nil,
        typographyDiagnostic: ((String) -> Void)? = nil,
        webReadDiagnostic: ((WebTextReadStage) -> Void)? = nil,
        sourceReadDiagnostic: ((SourceReadOutcome) -> Void)? = nil
    ) {
        self.excludedProcessIdentifier = excludedProcessIdentifier
        self.focusedApplicationProvider = focusedApplicationProvider
        self.workspaceProcessProvider = workspaceProcessProvider
        self.webCaretDiagnostic = webCaretDiagnostic
        self.typographyDiagnostic = typographyDiagnostic
        self.webReadDiagnostic = webReadDiagnostic
        self.sourceReadDiagnostic = sourceReadDiagnostic
        self.focusDiagnostic = focusDiagnostic
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
    }

    static func systemFocusedApplication() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// NSWorkspace activation metadata can lag AX focus. It is diagnostic only;
    /// capture, bootstrap and the physical parent boundary share AX authority.
    private func focusedApplication() -> (element: AXUIElement, pid: pid_t)? {
        let element = focusedApplicationProvider()
        var pid: pid_t = 0
        let focusedPID: pid_t? = element.flatMap {
            AXUIElementGetPid($0, &pid) == .success ? pid : nil
        }
        if let focusDiagnostic {
            let workspacePID = workspaceProcessProvider()
            let key = "\(focusedPID ?? -1):\(workspacePID ?? -1)"
            let changed = focusDiagnosticLock.withLock {
                guard lastFocusDiagnosticKey != key else { return false }
                lastFocusDiagnosticKey = key
                return true
            }
            if changed { focusDiagnostic(focusedPID, workspacePID) }
        }
        guard let element, let focusedPID else { return nil }
        return (element, focusedPID)
    }

    /// Structural evidence only: shared-container siblings are never a reply target.
    /// Cache topology briefly, refresh text on every capture. No text is retained.
    private var sourceTopology: (key: String, expires: TimeInterval, nodes: [(AXUIElement, String, FieldSource.Relation)])?

    func sourceContexts(for element: AccessibilityElement) -> [FieldSource] {
        guard let focused = element.rawValue,
              subrole(for: element) != (kAXSecureTextFieldSubrole as String) else { return [] }
        let key = element.identifier
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = now + 0.12
        func identity(_ node: AXUIElement) -> String {
            var pid: pid_t = 0
            AXUIElementGetPid(node, &pid)
            return SHA256.hash(data: Data("\(pid):\(CFHash(node))".utf8)).map { String(format: "%02x", $0) }.joined()
        }
        func elements(_ value: CFTypeRef?) -> [AXUIElement] {
            guard let value else { return [] }
            if CFGetTypeID(value) == AXUIElementGetTypeID() { return [unsafeDowncast(value, to: AXUIElement.self)] }
            return value as? [AXUIElement] ?? []
        }
        // One capture shares structural evidence across hit provenance and
        // visibility walks. Missing AX attributes are cached too. Values are
        // local to this call; source text is always read directly.
        var structuralValues: [AccessibilityTraversalNode: [String: CFTypeRef]] = [:]
        var missingAttributes: [AccessibilityTraversalNode: Set<String>] = [:]
        func sourceAttribute(_ name: String, from node: AXUIElement) -> CFTypeRef? {
            if name == (kAXValueAttribute as String) { return attribute(name, from: node) }
            let key = AccessibilityTraversalNode(element: node)
            if let value = structuralValues[key]?[name] { return value }
            if missingAttributes[key]?.contains(name) == true { return nil }
            if let value = attribute(name, from: node) {
                structuralValues[key, default: [:]][name] = value
                return value
            }
            missingAttributes[key, default: []].insert(name)
            return nil
        }
        let displays = displayGeometries().map(\.accessibilityFrame)
        func visibleText(_ node: AXUIElement) -> String? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(node, 0.02)
            defer { AXUIElementSetMessagingTimeout(node, Self.messagingTimeout) }
            guard sourceAttribute(kAXSubroleAttribute as String, from: node) as? String != (kAXSecureTextFieldSubrole as String),
                  sourceAttribute(kAXRoleAttribute as String, from: node) as? String == "AXStaticText",
                  sourceAttribute("AXHidden", from: node) as? Bool != true,
                  let frame = rectangle(from: sourceAttribute("AXFrame", from: node)) else { return nil }
            var branch = node
            var seen: Set<CFHashCode> = [CFHash(node)]
            var ancestry: [SourceVisibility.Ancestor] = []
            for _ in 0..<SourceVisibility.maximumAncestorCount {
                guard ProcessInfo.processInfo.systemUptime < deadline,
                      let parent = elements(sourceAttribute(kAXParentAttribute as String, from: branch)).first,
                      seen.insert(CFHash(parent)).inserted else { return nil }
                AXUIElementSetMessagingTimeout(parent, 0.02)
                defer { AXUIElementSetMessagingTimeout(parent, Self.messagingTimeout) }
                guard sourceAttribute(kAXSubroleAttribute as String, from: parent) as? String != (kAXSecureTextFieldSubrole as String),
                      let role = sourceAttribute(kAXRoleAttribute as String, from: parent) as? String else { return nil }
                let clips = ["AXScrollArea", "AXWebArea", "AXWindow"].contains(role)
                let isWindow = role == "AXWindow"
                ancestry.append(.init(
                    frame: clips ? rectangle(from: sourceAttribute("AXFrame", from: parent)) : nil,
                    clips: clips,
                    hidden: sourceAttribute("AXHidden", from: parent) as? Bool == true,
                    isWindow: isWindow
                ))
                if isWindow { break }
                if role == "AXApplication" { return nil }
                branch = parent
            }
            return SourceVisibility.readText(frame: frame, displays: displays, ancestors: ancestry, readExcerpt: {
                guard ProcessInfo.processInfo.systemUptime < deadline,
                      var range = self.rangeValue(self.attribute(kAXVisibleCharacterRangeAttribute as String, from: node)),
                      range.location >= 0, range.length > 0, range.length <= 2_000,
                      range.location <= Int.max - range.length,
                      let parameter = AXValueCreate(.cfRange, &range),
                      ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                var rawBounds: CFTypeRef?
                guard AXUIElementCopyParameterizedAttributeValue(node, kAXBoundsForRangeParameterizedAttribute as CFString,
                        parameter, &rawBounds) == .success,
                      let bounds = self.rectangle(from: rawBounds) else { return nil }
                return SourceVisibility.Excerpt(frame: bounds, read: {
                    guard ProcessInfo.processInfo.systemUptime < deadline,
                          let current = self.rangeValue(self.attribute(kAXVisibleCharacterRangeAttribute as String, from: node)),
                          current.location == range.location, current.length == range.length,
                          ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                    var rawText: CFTypeRef?
                    guard AXUIElementCopyParameterizedAttributeValue(node, kAXStringForRangeParameterizedAttribute as CFString,
                            parameter, &rawText) == .success,
                          let text = rawText as? String, text.utf16.count == range.length else { return nil }
                    return text
                })
            }) {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                return sourceAttribute(kAXValueAttribute as String, from: node) as? String
            }
        }
        // Seed a scroll branch from its actual viewport before spending the
        // node budget on its oldest offscreen descendants. Hits remain mere
        // source candidates and pass the same ancestry/visibility validation.
        func sourceChildren(_ candidate: AXUIElement, role: String) -> [AccessibilityTraversalNode] {
            var priority: [AccessibilityTraversalNode] = []
            if role == "AXScrollArea",
               let viewport = rectangle(from: sourceAttribute("AXFrame", from: candidate)),
               viewport.width > 0, viewport.height > 0 {
                var pid: pid_t = 0
                AXUIElementGetPid(focused, &pid)
                let application = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(application, 0.02)
                for fraction: CGFloat in [0.5, 0.25, 0.75] {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                    var hit: AXUIElement?
                    guard AXUIElementCopyElementAtPosition(application, Float(viewport.midX),
                        Float(viewport.minY + viewport.height * fraction), &hit) == .success,
                        let hit, !CFEqual(hit, candidate) else { continue }
                    var branch = hit
                    var visited: Set<CFHashCode> = []
                    for _ in 0..<32 {
                        guard ProcessInfo.processInfo.systemUptime < deadline,
                              visited.insert(CFHash(branch)).inserted else { break }
                        if CFEqual(branch, candidate) {
                            let node = AccessibilityTraversalNode(element: hit)
                            if !priority.contains(node) { priority.append(node) }
                            break
                        }
                        AXUIElementSetMessagingTimeout(branch, 0.02)
                        defer { AXUIElementSetMessagingTimeout(branch, Self.messagingTimeout) }
                        guard let branchRole = sourceAttribute(kAXRoleAttribute as String, from: branch) as? String,
                              !["AXWindow", "AXWebArea", "AXApplication"].contains(branchRole),
                              sourceAttribute(kAXSubroleAttribute as String, from: branch) as? String != (kAXSecureTextFieldSubrole as String),
                              !isEditableTextElement(branch, role: branchRole),
                              let parent = elements(sourceAttribute(kAXParentAttribute as String, from: branch)).first
                        else { break }
                        branch = parent
                    }
                }
            }
            let visible = sourceAttribute(kAXVisibleChildrenAttribute as String, from: candidate) as? [AXUIElement]
            let children = ReadOnlySourceTraversal.visibleChildren(reported: visible) {
                elements(sourceAttribute(kAXChildrenAttribute as String, from: candidate))
            }.map(AccessibilityTraversalNode.init(element:))
            return priority + children.filter { !priority.contains($0) }
        }
        var result: [FieldSource] = []
        defer {
            sourceReadDiagnostic?(ProcessInfo.processInfo.systemUptime >= deadline
                ? .deadline : result.isEmpty ? .noVisibleSources : .available)
        }
        var nodes: [(AXUIElement, String, FieldSource.Relation)] = []
        if let cache = sourceTopology, cache.key == key, cache.expires > now {
            for (node, container, relation) in cache.nodes {
                if let text = visibleText(node) {
                    result.append(FieldSource(id: identity(node), containerId: container, relation: relation, text: text))
                }
            }
            if result.count == cache.nodes.count, !cache.nodes.isEmpty { return result }
            // Scrolling or deletion invalidated a cached candidate. Refill from
            // the bounded tree now; invisible nodes cannot monopolize slots.
            sourceTopology = nil
            result.removeAll()
        }
        var seenSources: Set<AccessibilityTraversalNode> = []
        for (name, relation) in [("AXTitleUIElement", FieldSource.Relation.labelledBy), ("AXDescriptionUIElements", .describedBy)] {
            for node in elements(sourceAttribute(name, from: focused)).prefix(32) {
                guard result.count < FieldSource.maximumCount, ProcessInfo.processInfo.systemUptime < deadline else { break }
                guard seenSources.insert(AccessibilityTraversalNode(element: node)).inserted,
                      let text = visibleText(node) else { continue }
                let container = identity(focused)
                nodes.append((node, container, relation))
                result.append(FieldSource(id: identity(node), containerId: container, relation: relation, text: text))
            }
        }
        var branch = focused
        var containerID = ""
        var ancestors: Set<CFHashCode> = [CFHash(focused)]
        if result.count < FieldSource.maximumCount {
            let _: [AccessibilityTraversalNode] = ReadOnlySourceTraversal.collectNearest(
                maximumSources: FieldSource.maximumCount - result.count,
                shouldContinue: { ProcessInfo.processInfo.systemUptime < deadline },
                rootsForRing: { _ -> [AccessibilityTraversalNode]? in
                    guard let parent = elements(sourceAttribute(kAXParentAttribute as String, from: branch)).first,
                          ancestors.insert(CFHash(parent)).inserted,
                          let role = sourceAttribute(kAXRoleAttribute as String, from: parent) as? String,
                          !["AXWindow", "AXWebArea", "AXApplication"].contains(role) else { return nil }
                    let roots = ReadOnlySourceTraversal.nearestSiblings(
                        elements(sourceAttribute(kAXChildrenAttribute as String, from: parent))
                            .map(AccessibilityTraversalNode.init(element:)),
                        to: AccessibilityTraversalNode(element: branch), limit: 32
                    )
                    branch = parent
                    containerID = identity(parent)
                    return roots
                }
            ) { (node: AccessibilityTraversalNode) in
                guard !seenSources.contains(node) else { return .prune }
                let candidate = node.element
                AXUIElementSetMessagingTimeout(candidate, 0.02)
                defer { AXUIElementSetMessagingTimeout(candidate, Self.messagingTimeout) }
                guard sourceAttribute(kAXSubroleAttribute as String, from: candidate) as? String != (kAXSecureTextFieldSubrole as String),
                      sourceAttribute("AXHidden", from: candidate) as? Bool != true,
                      let role = sourceAttribute(kAXRoleAttribute as String, from: candidate) as? String else { return .prune }
                if role == "AXStaticText" {
                    seenSources.insert(node)
                    guard let text = visibleText(candidate) else { return .prune }
                    nodes.append((candidate, containerID, .sharedContainer))
                    result.append(FieldSource(id: identity(candidate), containerId: containerID, relation: .sharedContainer, text: text))
                    return .source
                }
                guard !["AXWindow", "AXWebArea", "AXApplication"].contains(role),
                      !isEditableTextElement(candidate, role: role) else { return .prune }
                return .container(sourceChildren(candidate, role: role))
            }
        }
        sourceTopology = nodes.isEmpty ? nil : (key, now + 0.5, nodes)
        return result
    }

    func displayGeometries() -> [DisplayGeometry] {
        Self.displayGeometries(
            from: NSScreen.screens.map {
                AppKitScreenDescriptor(
                    frame: $0.frame,
                    backingScaleFactor: $0.backingScaleFactor
                )
            }
        )
    }

    static func displayGeometries(
        from screens: [AppKitScreenDescriptor]
    ) -> [DisplayGeometry] {
        guard let primaryTop = screens.first?.frame.maxY else { return [] }
        return screens.map { screen in
            // AX screen frames and NSScreen.frame are both expressed in logical
            // screen points. backingScaleFactor is relevant only for backing pixels.
            DisplayGeometry(
                accessibilityFrame: CGRect(
                    x: screen.frame.minX,
                    y: primaryTop - screen.frame.maxY,
                    width: screen.frame.width,
                    height: screen.frame.height
                ),
                appKitFrame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor
            )
        }
    }

    func frontmostProcessIdentifier() -> Int32? {
        focusedApplication()?.pid
    }

    func frontmostApplicationBundleIdentifier() -> String? {
        guard let pid = focusedApplication()?.pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    func focusedElement() -> AccessibilityElement? {
        guard let application = focusedApplication(),
              application.pid != excludedProcessIdentifier else { return nil }
        AXUIElementSetMessagingTimeout(application.element, Self.messagingTimeout)
        guard let focusedValue = attribute(kAXFocusedUIElementAttribute as String, from: application.element),
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let rawElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(rawElement, Self.messagingTimeout)
        var actualPID: pid_t = 0
        guard AXUIElementGetPid(rawElement, &actualPID) == .success,
              actualPID == application.pid,
              actualPID != excludedProcessIdentifier else { return nil }
        return accessibilityElement(from: rawElement)
    }

    /// Materializes accessibility for Chromium/Electron hosts whose web tree
    /// is lazy. These hosts can expose an AXWebArea in the active window while
    /// AXFocusedUIElement still returns no value. A bounded, content-free tree
    /// walk activates the bridge; ActiveFieldCapture then retries focus once.
    func prepareFrontmostWebContent() {
        guard let application = focusedApplication(),
              application.pid != excludedProcessIdentifier else { return }
        let processIdentifier = application.pid
        let shouldWarm = manualAccessibilityLock.withLock {
            warmedWebProcessIdentifiers.insert(processIdentifier).inserted
        }
        guard shouldWarm else { return }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, Self.messagingTimeout)
        _ = AXUIElementSetAttributeValue(
            applicationElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        materializeWebAccessibilityTree(in: applicationElement)
    }

    func userInterfaceIdentifier(for element: AccessibilityElement) -> String? {
        guard let raw = element.rawValue else { return nil }
        return attribute("AXIdentifier", from: raw) as? String
    }

    func applicationBundleIdentifier(for element: AccessibilityElement) -> String? {
        guard let processIdentifier = processIdentifier(for: element) else { return nil }
        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }

    func processIdentifier(for element: AccessibilityElement) -> Int32? {
        guard let rawElement = element.rawValue else { return nil }
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(rawElement, &processIdentifier) == .success else {
            return nil
        }
        return processIdentifier
    }

    func isWebContentElement(_ element: AccessibilityElement) -> Bool {
        guard let rawElement = element.rawValue else { return false }
        return webTextMarkerProvider(for: rawElement) != nil
    }

    /// Chromium may expose text-marker strings while returning page-level or
    /// zero rectangles for every marker range. Asking the host to materialize
    /// its manual accessibility tree makes inline glyph geometry available;
    /// the attribute is capability-based and harmless when a host does not
    /// implement it. Refresh the focused element afterward because Chromium
    /// can rebuild that tree in response to the request.
    func prepareWebContent(for element: AccessibilityElement) -> AccessibilityElement {
        guard let processIdentifier = processIdentifier(for: element) else { return element }
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, Self.messagingTimeout)

        let shouldPrepare = manualAccessibilityLock.withLock {
            preparedWebProcessIdentifiers.insert(processIdentifier).inserted
        }
        if shouldPrepare {
            _ = AXUIElementSetAttributeValue(
                applicationElement,
                "AXManualAccessibility" as CFString,
                kCFBooleanTrue
            )
        }

        guard let focusedValue = attribute(
            kAXFocusedUIElementAttribute as String,
            from: applicationElement
        ), CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return element
        }
        let refreshed = unsafeDowncast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(refreshed, Self.messagingTimeout)
        guard webTextMarkerProvider(for: refreshed) != nil else { return element }
        return accessibilityElement(from: refreshed)
    }

    private func accessibilityElement(from rawElement: AXUIElement) -> AccessibilityElement {
        var processIdentifier: pid_t = 0
        AXUIElementGetPid(rawElement, &processIdentifier)
        return AccessibilityElement(
            identifier: "\(processIdentifier):\(CFHash(rawElement))",
            rawValue: rawElement
        )
    }

    func role(for element: AccessibilityElement) -> String? {
        stringAttribute(kAXRoleAttribute as String, from: element)
    }

    func subrole(for element: AccessibilityElement) -> String? {
        stringAttribute(kAXSubroleAttribute as String, from: element)
    }

    static func semanticPlaceholder(
        accessibilityPlaceholder: String?,
        syntheticPlaceholder: String?
    ) -> String? {
        boundedSemanticText(accessibilityPlaceholder)
            ?? boundedSemanticText(syntheticPlaceholder)
    }

    static func semanticLabel(
        description: String?,
        title: String?,
        help: String?
    ) -> String? {
        boundedSemanticText(description)
            ?? boundedSemanticText(title)
            ?? boundedSemanticText(help)
    }

    static func relatedFieldContexts(
        from candidates: [RelatedFieldCandidate]
    ) -> [RelatedFieldContext] {
        let secureSubrole = kAXSecureTextFieldSubrole as String
        guard !candidates.contains(where: { $0.subrole == secureSubrole }) else {
            return []
        }
        return candidates.compactMap { candidate in
            let trimmed = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let shape: ActiveFieldShape = candidate.role == (kAXTextFieldRole as String)
                ? .singleLine
                : .multiline
            return RelatedFieldContext(
                shape: shape,
                label: boundedSemanticText(candidate.label),
                placeholder: boundedSemanticText(candidate.placeholder),
                text: BoundedText.prefix(trimmed[...], maximumUTF16Units: 2_000)
            )
        }
        .prefix(3)
        .map { $0 }
    }

    private static func boundedSemanticText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(160))
    }

    func stringValue(for element: AccessibilityElement) -> String? {
        guard let rawElement = element.rawValue else { return nil }
        let value = attribute(kAXValueAttribute as String, from: rawElement)
        if let text = value as? String {
            return text
        }
        return (value as? NSAttributedString)?.string
    }

    func selectedTextRange(for element: AccessibilityElement) -> NSRange? {
        guard
            let rawElement = element.rawValue,
            let range = rangeValue(
                attribute(kAXSelectedTextRangeAttribute as String, from: rawElement)
            )
        else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }

    func bounds(for range: NSRange, in element: AccessibilityElement) -> CGRect? {
        guard let rawElement = element.rawValue else { return nil }
        var accessibilityRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &accessibilityRange) else {
            return nil
        }

        var rawBounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            rawElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &rawBounds
        ) == .success,
            let bounds = rectangle(from: rawBounds),
            Self.isUsableTextBounds(bounds)
        else { return nil }
        return bounds
    }

    private static func isUsableTextBounds(_ bounds: CGRect) -> Bool {
        bounds.minX.isFinite
            && bounds.minY.isFinite
            && bounds.width.isFinite
            && bounds.width >= 0
            && bounds.height.isFinite
            && bounds.height > 0
    }

    private func rectangle(from rawValue: CFTypeRef?) -> CGRect? {
        guard let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgRect else { return nil }
        var rectangle = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rectangle) else { return nil }
        return rectangle
    }

    private func rangeValue(_ rawValue: CFTypeRef?) -> CFRange? {
        guard let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    func frame(for element: AccessibilityElement) -> CGRect? {
        guard let rawElement = element.rawValue else { return nil }
        return rectangle(from: attribute("AXFrame", from: rawElement))
    }

    func textStyle(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> ActiveFieldTextStyle? {
        textStyleRuns(for: range, in: element)?.first?.style
    }

    func textStyleRuns(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> [ActiveFieldTextStyleRun]? {
        guard let attributed = attributedString(for: range, in: element) else {
            return nil
        }
        return Self.textStyleRuns(from: attributed)
    }

    /// A field-owned paragraph terminator carries insertion typography even
    /// when the editable value is empty. Never borrow neighboring prose.
    static func emptyFieldTextStyle(from attributed: NSAttributedString, fieldValue: String) -> ActiveFieldTextStyle? {
        guard fieldValue.isEmpty, (1...2).contains(attributed.length),
              attributed.string.allSatisfy(\.isNewline) else { return nil }
        return textStyleRuns(from: attributed)?.first?.style
    }

    static func markerTextStyle(
        from attributed: NSAttributedString,
        expectedText: String
    ) -> ActiveFieldTextStyle? {
        guard !attributed.string.isEmpty,
              !attributed.string.contains(where: \Character.isNewline),
              expectedText.hasPrefix(attributed.string) else { return nil }
        return textStyleRuns(from: attributed)?.first?.style
    }

    /// Read the insertion character independently: an unstyled run earlier in
    /// the paragraph does not invalidate the font at the verified cursor edge.
    static func focusedRangeTextStyle(
        value: String, selection: NSRange,
        markerTextBefore: String, markerTextAfter: String,
        read: (NSRange) -> NSAttributedString?,
        diagnostic: ((String) -> Void)? = nil
    ) -> ActiveFieldTextStyle? {
        guard selection.length == 0,
              let range = Range(selection, in: value),
              range.lowerBound > value.startIndex else {
            diagnostic?("typography_focused_range_ineligible"); return nil
        }
        guard String(value[..<range.lowerBound]) == markerTextBefore,
              String(value[range.upperBound...]) == markerTextAfter else {
            diagnostic?("typography_focused_range_text_disagreement"); return nil
        }
        let characterStart = value.index(before: range.lowerBound)
        let characterRange = characterStart..<range.lowerBound
        let expected = String(value[characterRange])
        guard !expected.contains(where: \Character.isNewline) else {
            diagnostic?("typography_focused_range_ineligible"); return nil
        }
        guard let attributed = read(NSRange(characterRange, in: value)) else {
            diagnostic?("typography_focused_range_read_unavailable"); return nil
        }
        guard attributed.string == expected else {
            diagnostic?("typography_focused_range_result_disagreement"); return nil
        }
        let style = insertionTextStyle(from: attributed, expectedText: expected)
        diagnostic?(style == nil ? "typography_focused_range_font_missing" : "typography_focused_range_available")
        return style
    }

    static func insertionTextStyle(from attributed: NSAttributedString, expectedText: String) -> ActiveFieldTextStyle? {
        guard attributed.length > 0, attributed.string == expectedText,
              attributed.string.last?.isNewline == false else { return nil }
        let attributes = attributed.attributes(at: attributed.length - 1, effectiveRange: nil)
        return textStyle(from: attributes[NSAttributedString.Key("AXFont")] ?? attributes[.font],
                         foregroundColor: attributes[NSAttributedString.Key("AXForegroundColor")] ?? attributes[.foregroundColor])
    }

    static func textStyleRuns(from attributed: NSAttributedString) -> [ActiveFieldTextStyleRun]? {
        let fontKey = NSAttributedString.Key("AXFont")
        let foregroundColorKey = NSAttributedString.Key("AXForegroundColor")
        var runs: [ActiveFieldTextStyleRun] = []
        var valid = true
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length)
        ) { attributes, effectiveRange, stop in
            guard let style = Self.textStyle(
                from: attributes[fontKey] ?? attributes[.font],
                foregroundColor: attributes[foregroundColorKey] ?? attributes[.foregroundColor]
            ) else {
                valid = false
                stop.pointee = true
                return
            }
            if let previous = runs.last,
               previous.style == style,
               NSMaxRange(previous.range) == effectiveRange.location {
                runs[runs.count - 1] = ActiveFieldTextStyleRun(
                    range: NSUnionRange(previous.range, effectiveRange),
                    style: style
                )
            } else {
                runs.append(
                    ActiveFieldTextStyleRun(range: effectiveRange, style: style)
                )
            }
        }
        return valid && !runs.isEmpty ? runs : nil
    }

    func paragraphAttributes(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> ActiveFieldParagraphAttributes? {
        guard let attributed = attributedString(for: range, in: element) else {
            return nil
        }
        return Self.paragraphAttributes(from: attributed)
    }

    static func paragraphAttributes(
        from attributed: NSAttributedString
    ) -> ActiveFieldParagraphAttributes? {
        guard attributed.length > 0 else { return nil }
        guard !hasAttribute(
            NSAttributedString.Key("AXListItemPrefix"),
            in: attributed
        ), !hasAttribute(
            NSAttributedString.Key("AXListItemLevel"),
            in: attributed
        ) else { return nil }

        var paragraph: NSParagraphStyle?
        var sawMissingStyle = false
        var isUniform = true
        attributed.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let value else {
                sawMissingStyle = true
                if paragraph != nil {
                    isUniform = false
                    stop.pointee = true
                }
                return
            }
            guard let style = value as? NSParagraphStyle else {
                isUniform = false
                stop.pointee = true
                return
            }
            if sawMissingStyle {
                isUniform = false
                stop.pointee = true
            } else if let paragraph, !paragraph.isEqual(style) {
                isUniform = false
                stop.pointee = true
            } else {
                paragraph = style
            }
        }
        guard isUniform else { return nil }
        guard let paragraph else { return .plain }

        return ActiveFieldParagraphAttributes(
            firstLineHeadIndent: paragraph.firstLineHeadIndent,
            headIndent: paragraph.headIndent,
            tailIndent: paragraph.tailIndent,
            lineSpacing: paragraph.lineSpacing,
            paragraphSpacingBefore: paragraph.paragraphSpacingBefore,
            paragraphSpacingAfter: paragraph.paragraphSpacing,
            tabStops: paragraph.tabStops.map(\.location),
            listMarker: nil,
            listLevel: nil
        )
    }

    private func attributedString(
        for range: NSRange,
        in element: AccessibilityElement
    ) -> NSAttributedString? {
        guard range.length > 0, let rawElement = element.rawValue else { return nil }
        var accessibilityRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &accessibilityRange) else {
            return nil
        }
        var rawAttributedString: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            rawElement,
            kAXAttributedStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &rawAttributedString
        ) == .success,
            let attributed = rawAttributedString as? NSAttributedString,
            attributed.length > 0
        else { return nil }
        return attributed
    }

    private static func textStyle(
        from value: Any?,
        foregroundColor: Any?
    ) -> ActiveFieldTextStyle? {
        if let font = value as? NSFont, font.pointSize.isFinite, font.pointSize > 0 {
            return ActiveFieldTextStyle(fontName: font.fontName, fontSize: font.pointSize,
                                        foregroundColor: textColor(from: foregroundColor))
        }
        guard let attributes = value as? NSDictionary,
              let fontSize = attributes["AXFontSize"] as? NSNumber,
              fontSize.doubleValue.isFinite,
              fontSize.doubleValue > 0
        else { return nil }
        let reportedName = attributes["AXFontName"] as? String
        let fontName = reportedName?.isEmpty == false
            ? reportedName!
            : ".AppleSystemUIFont"
        return ActiveFieldTextStyle(
            fontName: fontName,
            fontSize: CGFloat(fontSize.doubleValue),
            foregroundColor: textColor(from: foregroundColor)
        )
    }

    private static func textColor(from value: Any?) -> ActiveFieldTextColor? {
        let color: NSColor?
        if let nsColor = value as? NSColor {
            color = nsColor
        } else if let value {
            let rawColor = value as CFTypeRef
            guard CFGetTypeID(rawColor) == CGColor.typeID else { return nil }
            color = NSColor(cgColor: unsafeDowncast(rawColor, to: CGColor.self))
        } else {
            color = nil
        }
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        return ActiveFieldTextColor(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
    }

    private static func hasAttribute(
        _ key: NSAttributedString.Key,
        in attributed: NSAttributedString
    ) -> Bool {
        var found = false
        attributed.enumerateAttribute(
            key,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard value != nil else { return }
            found = true
            stop.pointee = true
        }
        return found
    }

    private func stringAttribute(
        _ name: String,
        from element: AccessibilityElement
    ) -> String? {
        guard let rawElement = element.rawValue else { return nil }
        return attribute(name, from: rawElement) as? String
    }

    private func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else {
            return nil
        }
        return value
    }

    private func webAreaAncestor(of element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<24 {
            if attribute(kAXRoleAttribute as String, from: current) as? String == "AXWebArea" {
                return current
            }
            guard let parent = attribute(kAXParentAttribute as String, from: current),
                  CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return nil }
            current = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return nil
    }

    private func webTextMarkerProvider(for element: AXUIElement) -> AXUIElement? {
        if let webArea = webAreaAncestor(of: element) {
            return webArea
        }
        var attributeNames: CFArray?
        var parameterizedAttributeNames: CFArray?
        guard AXUIElementCopyAttributeNames(element, &attributeNames) == .success,
              AXUIElementCopyParameterizedAttributeNames(
                  element,
                  &parameterizedAttributeNames
              ) == .success,
              Self.hasUsableTextMarkerProvider(
                  attributeNames: attributeNames as? [String] ?? [],
                  parameterizedAttributeNames:
                      parameterizedAttributeNames as? [String] ?? []
              )
        else { return nil }
        return element
    }

    static func hasUsableTextMarkerProvider(
        attributeNames: [String],
        parameterizedAttributeNames: [String]
    ) -> Bool {
        let attributes = Set(attributeNames)
        let parameterized = Set(parameterizedAttributeNames)
        return attributes.contains("AXSelectedTextMarkerRange")
            && parameterized.isSuperset(of: [
                "AXTextMarkerRangeForUIElement",
                "AXStringForTextMarkerRange",
                "AXBoundsForTextMarkerRange",
            ])
    }

    private func materializeWebAccessibilityTree(in application: AXUIElement) {
        guard let windows = attribute(kAXWindowsAttribute as String, from: application)
            as? [AXUIElement]
        else { return }

        var queue = windows.map { ($0, 0) }
        var visited: Set<CFHashCode> = []
        while !queue.isEmpty, visited.count < 512 {
            let (element, depth) = queue.removeFirst()
            let identity = CFHash(element)
            guard visited.insert(identity).inserted else { continue }
            AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

            if attribute(kAXRoleAttribute as String, from: element) as? String == "AXWebArea" {
                // Reading the web area's children is the activation edge in
                // Chromium builds that do not implement AXManualAccessibility.
                _ = attribute(kAXChildrenAttribute as String, from: element)
                return
            }
            guard depth < 16,
                  let children = attribute(kAXChildrenAttribute as String, from: element)
                    as? [AXUIElement]
            else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
    }

    // MARK: - Web content through text markers

    func webTextContext(for element: AccessibilityElement) -> WebTextContext? {
        func failed(_ stage: WebTextReadStage) -> WebTextContext? {
            webReadDiagnostic?(stage)
            return nil
        }
        guard let rawElement = element.rawValue else { return failed(.element) }
        let webProcessIdentifier = processIdentifier(for: element)
        let markerReadTimeout = webProcessIdentifier.map { processIdentifier in
            manualAccessibilityLock.withLock {
                webTextMarkerReadBudget.timeout(for: processIdentifier)
            }
        } ?? Self.messagingTimeout
        AXUIElementSetMessagingTimeout(rawElement, markerReadTimeout)

        guard let role = role(for: element),
              role != "AXWebArea",
              let markerProvider = webTextMarkerProvider(for: rawElement)
        else { return failed(.provider) }
        AXUIElementSetMessagingTimeout(markerProvider, markerReadTimeout)
        let markers = TextMarkerReader(webArea: markerProvider)

        var selectionFailure = WebTextReadStage.selection
        guard let selection = markers.selectedRange(fallback: rawElement, failed: { selectionFailure = $0 })
        else { return failed(selectionFailure) }
        let selectionStart = AXTextMarkerRangeCopyStartMarker(selection)
        let selectionEnd = AXTextMarkerRangeCopyEndMarker(selection)
        var ownershipFailure = WebTextReadStage.selectionMapping
        guard let selectionMarkerElement = markers.element(
                  for: selectionStart,
                  within: rawElement,
                  failed: { ownershipFailure = $0 }
              ) else { return failed(ownershipFailure) }
        guard let elementRange = markers.range(forElement: rawElement) else { return failed(.elementRange) }
        guard let fieldValue = stringValue(for: element) else { return failed(.fieldValue) }
        guard let fieldSelection = selectedTextRange(for: element) else { return failed(.fieldSelection) }
        guard let focusedText = FocusedEditableText(
                  value: fieldValue,
                  selection: fieldSelection
              )
        else { return failed(.focusedText) }
        let elementStart = AXTextMarkerRangeCopyStartMarker(elementRange)
        let elementEnd = AXTextMarkerRangeCopyEndMarker(elementRange)

        guard let before = markers.boundedString(
            from: elementStart,
            to: selectionStart,
            maximumUTF16Units: 8_000,
            keeping: .suffix
        ) else { return failed(.before) }
        guard let selectedFull = markers.string(from: selectionStart, to: selectionEnd) else { return failed(.selected) }
        guard let after = markers.boundedString(
                from: selectionEnd,
                to: elementEnd,
                maximumUTF16Units: 2_000,
                keeping: .prefix
            )
        else { return failed(.after) }
        webReadDiagnostic?(.success)
        if let webProcessIdentifier {
            manualAccessibilityLock.withLock {
                webTextMarkerReadBudget.recordSuccess(for: webProcessIdentifier)
            }
        }
        AXUIElementSetMessagingTimeout(rawElement, Self.messagingTimeout)
        AXUIElementSetMessagingTimeout(markerProvider, Self.messagingTimeout)
        let selected = BoundedText.prefix(
            focusedText.selectedText[...],
            maximumUTF16Units: 2_000
        )
        let isCollapsed = focusedText.selectionLength == 0
        let elementFrame = frame(for: element)
        let selectionMarkerRole = attribute(kAXRoleAttribute as String, from: selectionMarkerElement) as? String
        let selectionMarkerValue = attribute(
            kAXValueAttribute as String,
            from: selectionMarkerElement
        )
        let selectionMarkerText = (selectionMarkerValue as? String)
            ?? (selectionMarkerValue as? NSAttributedString)?.string
        let selectionMarkerBounds = rectangle(
            from: attribute("AXFrame", from: selectionMarkerElement)
        )

        let typographySample: (text: String, bounds: CGRect)? = if isCollapsed,
           let wordStart = markers.previousWordStartMarker(of: selectionStart),
           let text = markers.string(from: wordStart, to: selectionStart),
           let bounds = markers.bounds(from: wordStart, to: selectionStart),
           Self.isUsableTextBounds(bounds),
           !text.contains(where: \Character.isNewline) {
            (text, bounds)
        } else {
            nil
        }

        var candidates: [CaretGeometryCandidate] = []
        var zeroLengthBounds: CGRect?
        if isCollapsed {
            if let bounds = markers.bounds(from: selectionStart, to: selectionStart),
               Self.isUsableTextBounds(bounds) {
                zeroLengthBounds = bounds
                candidates.append(.init(rect: bounds, source: .zeroLengthRange))
            }
            if let previous = markers.previousMarker(of: selectionStart),
               let text = markers.string(from: previous, to: selectionStart),
               !text.isEmpty, text.first?.isNewline == false,
               let bounds = markers.bounds(from: previous, to: selectionStart),
               Self.isGraphemeBox(bounds) {
                candidates.append(.init(rect: bounds, source: .precedingGrapheme))
            }
            if let next = markers.nextMarker(of: selectionEnd),
               let text = markers.string(from: selectionEnd, to: next),
               !text.isEmpty,
               let bounds = markers.bounds(from: selectionEnd, to: next) {
                if text.first?.isNewline == false, Self.isGraphemeBox(bounds) {
                    candidates.append(.init(rect: bounds, source: .followingGrapheme))
                }
            }
        }

        var nodeCandidateAvailable = false
        var nodeCandidateSelected = false
        var lineBounds: CGRect?
        var currentLineText: String?
        var ownedVisualLineStyle: ActiveFieldTextStyle?
        if let lineRange = markers.lineRange(at: selectionStart) {
            let lineStart = AXTextMarkerRangeCopyStartMarker(lineRange)
            let lineEnd = AXTextMarkerRangeCopyEndMarker(lineRange)
            let rawLineBounds = markers.bounds(from: lineStart, to: lineEnd)
            if let rawLineBounds, Self.isUsableTextBounds(rawLineBounds) {
                lineBounds = rawLineBounds
            }
            let lineTextBefore = markers.string(from: lineStart, to: selectionStart)
            let lineTextAfter = markers.string(from: selectionEnd, to: lineEnd)
            if let lineTextBefore, let lineTextAfter {
                currentLineText = lineTextBefore + lineTextAfter
            }
            if let lineTextBefore, let lineTextAfter,
               Self.markerNodeLineEdgeCandidate(
                   focusedText: focusedText, nodeRole: selectionMarkerRole,
                   nodeText: selectionMarkerText, currentLineText: currentLineText,
                   nodeBounds: selectionMarkerBounds, inputFrame: elementFrame) == nil,
               let measured = Self.ownedVisualLineBounds(
                   focusedText: focusedText, nodeRole: selectionMarkerRole,
                   nodeText: selectionMarkerText, lineTextBefore: lineTextBefore,
                   lineTextAfter: lineTextAfter, inputFrame: elementFrame,
                   readBounds: { range in
                       AXUIElementSetMessagingTimeout(selectionMarkerElement, 0.02)
                       defer { AXUIElementSetMessagingTimeout(selectionMarkerElement, Self.messagingTimeout) }
                       return self.bounds(for: range, in: self.accessibilityElement(from: selectionMarkerElement))
                   }
               ) {
                lineBounds = measured
                typographyDiagnostic?("typography_owned_visual_line_measured")
                // The numeric range and endpoint glyphs establish this line;
                // use only its text/width for the existing explicit estimate.
                if let currentLineText,
                   let lineText = FocusedEditableText(value: currentLineText,
                       selection: NSRange(location: currentLineText.utf16.count, length: 0)) {
                    ownedVisualLineStyle = Self.measuredNodeTextStyle(
                        focusedText: lineText, nodeRole: selectionMarkerRole,
                        nodeText: currentLineText, currentLineText: currentLineText,
                        nodeBounds: measured, inputFrame: elementFrame)
                }
            }
            candidates = Self.candidatesOnCurrentLine(
                candidates,
                textBefore: lineTextBefore,
                textAfter: lineTextAfter,
                lineBounds: lineBounds
            )
            // Collect measured line evidence even when a glyph was reported.
            // The resolver validates candidates before giving glyphs priority;
            // a detached glyph must not prevent an otherwise valid anchor.
            if isCollapsed,
               let reportedLineBounds = lineBounds,
               let lineTextBefore, let lineTextAfter {
                let markerNodeCandidate = Self.markerNodeLineEdgeCandidate(
                    focusedText: focusedText,
                    nodeRole: selectionMarkerRole,
                    nodeText: selectionMarkerText,
                    currentLineText: currentLineText,
                    nodeBounds: selectionMarkerBounds,
                    inputFrame: elementFrame
                )
                nodeCandidateAvailable = markerNodeCandidate != nil
                if let lineEdge = Self.terminalLineEdgeCandidate(
                    lineBounds: reportedLineBounds,
                    lineTextBefore: lineTextBefore,
                    lineTextAfter: lineTextAfter,
                    markerNodeCandidate: markerNodeCandidate
                ) {
                    nodeCandidateSelected = markerNodeCandidate == lineEdge
                    candidates.append(lineEdge)
                    lineBounds = Self.effectiveTerminalLineBounds(
                        reportedLineBounds: reportedLineBounds,
                        selectedCandidate: lineEdge
                    )
                }
            }
        }

        webCaretDiagnostic?(WebCaretEvidence(
            markerSelectionMatches: before.fullLength == focusedText.selectionLocation
                && selectedFull.utf16.count == focusedText.selectionLength,
            nodeValueMatches: selectionMarkerText == focusedText.textBefore,
            lineValueMatches: currentLineText == selectionMarkerText,
            nodeContained: selectionMarkerBounds.map { node in
                elementFrame?.insetBy(dx: -4, dy: -4).contains(node) == true
            } ?? false,
            nodeIsText: selectionMarkerRole == kAXStaticTextRole as String,
            nodeCandidateAvailable: nodeCandidateAvailable,
            nodeCandidateSelected: nodeCandidateSelected
        ))

        let syntheticPlaceholder = Self.isSyntheticWebPlaceholder(
            focusedText: focusedText,
            textBefore: before.text,
            selectedText: selectedFull,
            textAfter: after.text,
            textBeforeFullLength: before.fullLength,
            currentLineText: currentLineText,
            zeroLengthBounds: zeroLengthBounds,
            lineBounds: lineBounds,
            elementFrame: elementFrame
        )
        let resolvedText = syntheticPlaceholder ? FocusedEditableText.empty : focusedText
        let placeholder = Self.semanticPlaceholder(
            accessibilityPlaceholder: stringAttribute(
                kAXPlaceholderValueAttribute as String,
                from: element
            ),
            syntheticPlaceholder: syntheticPlaceholder ? after.text : nil
        )
        let label = Self.semanticLabel(
            description: stringAttribute(kAXDescriptionAttribute as String, from: element),
            title: stringAttribute(kAXTitleAttribute as String, from: element),
            help: stringAttribute(kAXHelpAttribute as String, from: element)
        )
        let semanticIdentifier = Self.boundedSemanticText(
            stringAttribute(kAXIdentifierAttribute as String, from: element)
                ?? stringAttribute("AXDOMIdentifier", from: element)
        )
        let relatedFields = liveRelatedFieldContexts(
            near: rawElement,
            applicationBundleIdentifier: applicationBundleIdentifier(for: element) ?? ""
        )
        // A numeric range on the editable container may expose a different
        // descendant's font. Read the same marker text used to establish the
        // empty placeholder, rather than borrowing container typography.
        let placeholderStyle: ActiveFieldTextStyle?
        if syntheticPlaceholder,
           let next = markers.nextMarker(of: selectionEnd),
           let attributed = markers.attributedString(from: selectionEnd, to: next) {
            placeholderStyle = Self.markerTextStyle(from: attributed, expectedText: after.text)
        } else {
            placeholderStyle = nil
        }
        var hostPlaceholderBounds: CGRect?
        if syntheticPlaceholder,
           let elementFrame,
           let placeholderStyle,
           let caret = Self.emptyWebCaret(in: elementFrame, style: placeholderStyle) {
            // Some web hosts publish an empty composer as a block range.
            // That rectangle is evidence of an empty editor, not
            // caret geometry. Replace every block candidate with one narrow,
            // typography-sized line-start anchor.
            candidates = [.init(rect: caret, source: .lineStart)]
            lineBounds = caret
            hostPlaceholderBounds = Self.placeholderMaskBounds(
                for: after.text,
                caret: caret,
                style: placeholderStyle,
                inside: elementFrame
            )
        }

        var paragraphBounds: CGRect?
        var paragraphTextBefore = ""
        var paragraphTextBeforeIsComplete = true
        var paragraphStyleRuns: [ActiveFieldTextStyleRun]?
        var paragraphAttributes: ActiveFieldParagraphAttributes?
        if let paragraphRange = markers.paragraphRange(at: selectionStart) {
            let paragraphStart = AXTextMarkerRangeCopyStartMarker(paragraphRange)
            let paragraphEnd = AXTextMarkerRangeCopyEndMarker(paragraphRange)
            if let bounds = markers.bounds(from: paragraphStart, to: paragraphEnd),
               Self.isUsableTextBounds(bounds) {
                paragraphBounds = bounds
            }
            if let length = markers.length(from: paragraphStart, to: selectionStart),
               length <= 2_000,
               let text = markers.string(from: paragraphStart, to: selectionStart) {
                paragraphTextBefore = text
                if !text.isEmpty,
                   let attributed = markers.attributedString(
                       from: paragraphStart,
                       to: selectionStart
                   ),
                   attributed.length == text.utf16.count {
                    paragraphStyleRuns = Self.textStyleRuns(from: attributed)
                    paragraphAttributes = Self.paragraphAttributes(from: attributed)
                }
            } else {
                paragraphTextBeforeIsComplete = false
            }
        }
        let emptyFieldStyle: ActiveFieldTextStyle?
        if fieldValue.isEmpty, let length = markers.length(from: elementStart, to: elementEnd),
           (1...2).contains(length),
           let attributed = markers.attributedString(from: elementStart, to: elementEnd) {
            emptyFieldStyle = Self.emptyFieldTextStyle(from: attributed, fieldValue: fieldValue)
        } else { emptyFieldStyle = nil }
        let insertionStyle: ActiveFieldTextStyle?
        if isCollapsed, let previous = markers.previousMarker(of: selectionStart),
           let text = markers.string(from: previous, to: selectionStart),
           let attributed = markers.attributedString(from: previous, to: selectionStart) {
            insertionStyle = Self.insertionTextStyle(from: attributed, expectedText: text)
        } else { insertionStyle = nil }
        let markerStyle = emptyFieldStyle ?? insertionStyle ?? placeholderStyle ?? paragraphStyleRuns?.last?.style
        // Range-based and marker-based Accessibility are independent capabilities.
        // Read only the insertion grapheme, and only when both text coordinates agree.
        // Never read container typography for an empty field or a placeholder.
        var focusedRangeDiagnostic: String?
        let focusedRangeStyle = markerStyle == nil ? Self.focusedRangeTextStyle(
            value: fieldValue, selection: fieldSelection,
            markerTextBefore: before.text, markerTextAfter: after.text,
            read: { self.attributedString(for: $0, in: element) },
            diagnostic: { focusedRangeDiagnostic = $0 }
        ) : nil
        let measuredStyle = markerStyle == nil && focusedRangeStyle == nil
            ? ownedVisualLineStyle ?? Self.measuredNodeTextStyle(
                focusedText: focusedText, nodeRole: selectionMarkerRole,
                nodeText: selectionMarkerText, currentLineText: currentLineText,
                nodeBounds: selectionMarkerBounds, inputFrame: elementFrame
            ) : nil
        if measuredStyle != nil { typographyDiagnostic?("typography_owned_node_estimated") }
        let caretTextStyle = measuredStyle ?? Self.webCalibratedTextStyle(
            markerStyle ?? focusedRangeStyle,
            sampleText: typographySample?.text,
            sampleBounds: typographySample?.bounds,
            currentLineBounds: lineBounds,
            caretBounds: candidates.first(where: {
                ($0.source == .zeroLengthRange || $0.source.isLineEdge)
                    && $0.rect.width <= 1
            })?.rect,
            fieldBounds: elementFrame,
            diagnostic: { code in
                self.typographyDiagnostic?(code == "typography_default_font_unavailable"
                    ? (focusedRangeDiagnostic ?? code) : code)
            }
        )

        return WebTextContext(
            editableIdentifier: element.identifier,
            role: role,
            subrole: subrole(for: element),
            textBefore: BoundedText.suffix(
                resolvedText.textBefore[...],
                maximumUTF16Units: 8_000
            ),
            selectedText: selected,
            textAfter: BoundedText.prefix(
                resolvedText.textAfter[...],
                maximumUTF16Units: 2_000
            ),
            selectionLocation: resolvedText.selectionLocation,
            selectionLength: resolvedText.selectionLength,
            frame: elementFrame,
            caretCandidates: candidates,
            lineBounds: lineBounds,
            paragraphBounds: paragraphBounds,
            paragraphTextBefore: paragraphTextBefore,
            paragraphTextBeforeIsComplete: paragraphTextBeforeIsComplete,
            paragraphStyleRuns: paragraphStyleRuns,
            caretTextStyle: caretTextStyle,
            hostPlaceholderBounds: hostPlaceholderBounds,
            paragraphAttributes: paragraphAttributes,
            label: label,
            placeholder: placeholder,
            semanticIdentifier: semanticIdentifier,
            relatedFields: relatedFields
        )
    }

    /// Reads bounded text and semantic labels from nearby editable siblings.
    /// The model interprets their relationship; this layer only enforces
    /// proximity and privacy boundaries.
    private func liveRelatedFieldContexts(
        near focused: AXUIElement,
        applicationBundleIdentifier: String
    ) -> [RelatedFieldContext] {
        let cacheKey = "\(applicationBundleIdentifier):\(CFHash(focused))"
        let now = Date.timeIntervalSinceReferenceDate
        var state = relatedFieldCacheLock.withLock { () -> RelatedFieldScanState? in
            guard let cached = relatedFieldScanState,
                  cached.key == cacheKey
            else { return nil }
            return cached
        } ?? RelatedFieldScanState(
            key: cacheKey,
            expiresAt: now + 2,
            traversal: EditableNeighborhoodTraversal(
                seeds: relatedFieldSeeds(near: focused)
            ),
            editables: [],
            totalVisits: 0,
            isComplete: false,
            foundSecureField: false
        )

        if state.isComplete, state.expiresAt <= now {
            state.restartTraversal(seeds: relatedFieldSeeds(near: focused), at: now)
        }

        if !state.isComplete, !state.foundSecureField, state.totalVisits < 1_024 {
            let deadline = Date.timeIntervalSinceReferenceDate + 0.05
            var traversal = state.traversal
            var discovered = state.editables
            var foundSecureField = false
            let result = traversal.scan(
                maximumVisits: min(256, 1_024 - state.totalVisits),
                shouldContinue: {
                    Date.timeIntervalSinceReferenceDate <= deadline
                        && !foundSecureField
                        && discovered.count < 3
                }
            ) { node in
                let candidate = node.element
                AXUIElementSetMessagingTimeout(candidate, Self.messagingTimeout)
                let candidateRole = attribute(
                    kAXRoleAttribute as String,
                    from: candidate
                ) as? String
                let candidateSubrole = attribute(
                    kAXSubroleAttribute as String,
                    from: candidate
                ) as? String

                if candidateSubrole == (kAXSecureTextFieldSubrole as String) {
                    foundSecureField = true
                    return .init(children: [], shouldPrune: true)
                }

                if let candidateRole,
                   isEditableTextElement(candidate, role: candidateRole) {
                    if candidateSubrole != (kAXSearchFieldSubrole as String) {
                        let candidateLabel = Self.semanticLabel(
                            description: attribute(
                                kAXDescriptionAttribute as String,
                                from: candidate
                            ) as? String,
                            title: attribute(
                                kAXTitleAttribute as String,
                                from: candidate
                            ) as? String,
                            help: attribute(
                                kAXHelpAttribute as String,
                                from: candidate
                            ) as? String
                        )
                        let candidatePlaceholder = Self.semanticPlaceholder(
                            accessibilityPlaceholder: attribute(
                                kAXPlaceholderValueAttribute as String,
                                from: candidate
                            ) as? String,
                            syntheticPlaceholder: nil
                        )
                        let shape: ActiveFieldShape = candidateRole
                            == (kAXTextFieldRole as String) ? .singleLine : .multiline
                        if !discovered.contains(where: { CFEqual($0.element, candidate) }) {
                            discovered.append(
                                RelatedEditableTopology(
                                    element: candidate,
                                    shape: shape,
                                    label: candidateLabel,
                                    placeholder: candidatePlaceholder
                                )
                            )
                        }
                    }
                    // Once an editable root is found, its text descendants are
                    // implementation detail rather than additional fields.
                    return .init(children: [], shouldPrune: true)
                }

                let children = attribute(
                    kAXChildrenAttribute as String,
                    from: candidate
                ) as? [AXUIElement] ?? []
                return .init(
                    children: children.map(AccessibilityTraversalNode.init(element:)),
                    shouldPrune: false
                )
            }
            state.traversal = traversal
            state.editables = discovered
            state.totalVisits += result.visitedNodes.count
            state.foundSecureField = foundSecureField
            state.isComplete = result.isComplete
                || state.totalVisits >= 1_024
                || foundSecureField
                || discovered.count >= 3
            state.expiresAt = now + (state.isComplete ? 2 : 0.5)
        }

        relatedFieldCacheLock.withLock {
            relatedFieldScanState = state
        }
        guard !state.foundSecureField else { return [] }

        return state.visibleEditables.compactMap { candidate in
            guard let text = boundedRelatedText(from: candidate.element) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return RelatedFieldContext(
                shape: candidate.shape,
                label: candidate.label,
                placeholder: candidate.placeholder,
                text: BoundedText.prefix(trimmed[...], maximumUTF16Units: 2_000)
            )
        }
        .prefix(3)
        .map { $0 }
    }

    private func relatedFieldSeeds(
        near focused: AXUIElement
    ) -> [EditableNeighborhoodTraversal<AccessibilityTraversalNode>.Seed] {
        let focusedFrame = rectangle(from: attribute("AXFrame", from: focused))
        var seeds: [EditableNeighborhoodTraversal<AccessibilityTraversalNode>.Seed] = []
        var branch = focused
        var ancestorRing = 0
        var visitedAncestors: Set<CFHashCode> = [CFHash(focused)]

        while let parentValue = attribute(kAXParentAttribute as String, from: branch),
              CFGetTypeID(parentValue) == AXUIElementGetTypeID() {
            let parent = unsafeDowncast(parentValue, to: AXUIElement.self)
            guard visitedAncestors.insert(CFHash(parent)).inserted else { break }
            let children = attribute(
                kAXChildrenAttribute as String,
                from: parent
            ) as? [AXUIElement] ?? []
            let branchIndex = children.firstIndex { CFEqual($0, branch) } ?? 0
            let siblings = children.enumerated()
                .filter { !CFEqual($0.element, branch) }
                .sorted { lhs, rhs in
                    isHigherPrioritySibling(
                        lhs.element,
                        index: lhs.offset,
                        than: rhs.element,
                        index: rhs.offset,
                        focusedFrame: focusedFrame,
                        branchIndex: branchIndex
                    )
                }
            seeds.append(contentsOf: siblings.enumerated().map { priority, sibling in
                .init(
                    node: AccessibilityTraversalNode(element: sibling.element),
                    ancestorRing: ancestorRing,
                    branchPriority: priority
                )
            })

            let parentRole = attribute(kAXRoleAttribute as String, from: parent) as? String
            if parentRole == "AXWebArea" || parentRole == (kAXWindowRole as String) {
                break
            }
            branch = parent
            ancestorRing += 1
        }
        return seeds
    }

    private func isHigherPrioritySibling(
        _ lhs: AXUIElement,
        index lhsIndex: Int,
        than rhs: AXUIElement,
        index rhsIndex: Int,
        focusedFrame: CGRect?,
        branchIndex: Int
    ) -> Bool {
        let lhsFrame = rectangle(from: attribute("AXFrame", from: lhs))
        let rhsFrame = rectangle(from: attribute("AXFrame", from: rhs))
        let lhsRank = siblingGeometryRank(lhsFrame, focusedFrame: focusedFrame)
        let rhsRank = siblingGeometryRank(rhsFrame, focusedFrame: focusedFrame)
        if lhsRank.category != rhsRank.category {
            return lhsRank.category < rhsRank.category
        }
        if lhsRank.distance != rhsRank.distance {
            return lhsRank.distance < rhsRank.distance
        }
        let lhsReadingOrder = lhsIndex >= branchIndex ? 0 : 1
        let rhsReadingOrder = rhsIndex >= branchIndex ? 0 : 1
        if lhsReadingOrder != rhsReadingOrder {
            return lhsReadingOrder < rhsReadingOrder
        }
        return abs(lhsIndex - branchIndex) < abs(rhsIndex - branchIndex)
    }

    private func siblingGeometryRank(
        _ frame: CGRect?,
        focusedFrame: CGRect?
    ) -> (category: Int, distance: CGFloat) {
        guard let frame, let focusedFrame else {
            return (2, .greatestFiniteMagnitude)
        }
        let overlapsHorizontally = frame.maxX >= focusedFrame.minX
            && frame.minX <= focusedFrame.maxX
        let dx = frame.midX - focusedFrame.midX
        let dy = frame.midY - focusedFrame.midY
        return (overlapsHorizontally ? 0 : 1, hypot(dx, dy))
    }

    private func isEditableTextElement(_ element: AXUIElement, role: String) -> Bool {
        if role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String) {
            return true
        }
        guard role == (kAXGroupRole as String) || role == "AXUnknown" else {
            return false
        }
        var valueIsSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &valueIsSettable
        ) == .success,
            valueIsSettable.boolValue
        else { return false }
        return attribute(kAXSelectedTextRangeAttribute as String, from: element) != nil
            || attribute("AXSelectedTextMarkerRange", from: element) != nil
    }

    private func boundedRelatedText(from element: AXUIElement) -> String? {
        if let value = attribute(kAXValueAttribute as String, from: element) {
            if let text = value as? String {
                return BoundedText.prefix(text[...], maximumUTF16Units: 2_000)
            }
            if let attributed = value as? NSAttributedString {
                return BoundedText.prefix(
                    attributed.string[...],
                    maximumUTF16Units: 2_000
                )
            }
        }
        guard let provider = webTextMarkerProvider(for: element) else { return nil }
        let markers = TextMarkerReader(webArea: provider)
        guard let range = markers.range(forElement: element) else { return nil }
        let start = AXTextMarkerRangeCopyStartMarker(range)
        let end = AXTextMarkerRangeCopyEndMarker(range)
        return markers.boundedString(
            from: start,
            to: end,
            maximumUTF16Units: 2_000,
            keeping: .prefix
        )?.text
    }

    static func isSyntheticWebPlaceholder(
        focusedText: FocusedEditableText,
        textBefore: String,
        selectedText: String,
        textAfter: String,
        textBeforeFullLength: Int,
        currentLineText: String?,
        zeroLengthBounds: CGRect?,
        lineBounds: CGRect?,
        elementFrame: CGRect?
    ) -> Bool {
        // Marker publication can lag behind AXValue and AXSelectedTextRange.
        // Never let stale or document-scoped markers erase authored field text.
        guard focusedText.selectionLocation == 0,
              focusedText.selectionLength == 0,
              focusedText.textBefore.isEmpty,
              focusedText.selectedText.isEmpty,
              focusedText.textAfter == textAfter,
              textBefore.isEmpty,
              selectedText.isEmpty,
              !textAfter.isEmpty,
              textBeforeFullLength == 0,
              currentLineText?.isEmpty == true,
              let zeroLengthBounds,
              let lineBounds,
              let elementFrame
        else { return false }
        return approximatelyEqual(zeroLengthBounds, lineBounds)
            && isEmptyLineBox(lineBounds, inside: elementFrame)
    }

    static func candidatesOnCurrentLine(
        _ candidates: [CaretGeometryCandidate],
        textBefore: String?,
        textAfter: String?,
        lineBounds: CGRect?
    ) -> [CaretGeometryCandidate] {
        // Only independent line/caret agreement can discard a glyph from a
        // different visual line. A preceding marker may still refer to the
        // previous wrapped line while the insertion range has already moved.
        guard textBefore != nil, let textAfter,
              let lineBounds, isUsableTextBounds(lineBounds),
              let caret = candidates.first(where: {
                  $0.source == .zeroLengthRange
                      && isUsableTextBounds($0.rect)
                      && $0.rect.width <= 1
                      && abs($0.rect.minY - lineBounds.minY) <= 1
                      && abs($0.rect.maxY - lineBounds.maxY) <= 1
              })
        else { return candidates }
        if textBefore?.isEmpty == true, textAfter.allSatisfy(\.isNewline),
           lineBounds.width <= 1, approximatelyEqual(caret.rect, lineBounds) {
            return [caret]
        }
        return candidates.filter {
            $0.rect.maxY > lineBounds.minY && $0.rect.minY < lineBounds.maxY
        }
    }

    /// AX attributed strings report the CSS font size, but browser zoom and
    /// transformed editor roots are represented only in screen-space marker
    /// bounds. Calibrate with one measured word so AppKit draws at the same
    /// effective size as the host without recognizing any particular app.
    static func webCalibratedTextStyle(
        _ style: ActiveFieldTextStyle?,
        sampleText: String?,
        sampleBounds: CGRect?,
        currentLineBounds: CGRect?,
        caretBounds: CGRect?,
        fieldBounds: CGRect?,
        diagnostic: ((String) -> Void)? = nil
    ) -> ActiveFieldTextStyle? {
        guard let basis = style else {
            diagnostic?("typography_default_font_unavailable")
            return nil
        }
        func unchanged(_ reason: String) -> ActiveFieldTextStyle? {
            diagnostic?("typography_attributed_\(reason)")
            return style
        }
        guard let sampleText,
              !sampleText.isEmpty,
              sampleText.utf16.count >= 2,
              sampleText.utf16.count <= 32,
              !sampleText.contains(where: \Character.isNewline),
              let sampleBounds,
              sampleBounds.width.isFinite,
              sampleBounds.width > 0
        else { return unchanged("sample_unavailable") }
        // Width alone cannot distinguish browser zoom from a soft-wrapped
        // range or a detached marker. Require an independently measured line
        // and narrow insertion edge, all in the focused field's coordinates.
        guard let currentLineBounds else { return unchanged("line_missing") }
        guard let caretBounds else { return unchanged("caret_missing") }
        guard let fieldBounds else { return unchanged("field_missing") }
        guard basis.fontSize.isFinite, basis.fontSize > 0,
              [sampleBounds, currentLineBounds, caretBounds, fieldBounds]
                .allSatisfy({ isUsableTextBounds($0) && !$0.isNull && !$0.isInfinite }),
              fieldBounds.width > 0, currentLineBounds.width > 0
        else { return unchanged("bounds_invalid") }
        guard caretBounds.width <= 1 else { return unchanged("caret_not_narrow") }
        guard fieldBounds.insetBy(dx: -1, dy: -1).contains(sampleBounds),
              fieldBounds.insetBy(dx: -1, dy: -1).contains(currentLineBounds),
              caretBounds.minX >= fieldBounds.minX - 1,
              caretBounds.maxX <= fieldBounds.maxX + 1
        else { return unchanged("outside_field") }
        guard abs(sampleBounds.minY - currentLineBounds.minY) <= 1,
              abs(sampleBounds.maxY - currentLineBounds.maxY) <= 1,
              sampleBounds.minX >= currentLineBounds.minX - 1,
              sampleBounds.maxX <= currentLineBounds.maxX + 1
        else { return unchanged("sample_not_single_line") }
        guard caretBounds.minY >= currentLineBounds.minY - 1,
              caretBounds.maxY <= currentLineBounds.maxY + 1
        else { return unchanged("caret_outside_line") }
        guard min(abs(sampleBounds.maxX - caretBounds.minX),
                  abs(sampleBounds.minX - caretBounds.maxX)) <= 1
        else { return unchanged("sample_not_adjacent") }
        let font = NSFont(name: basis.fontName, size: basis.fontSize)
            ?? (basis.fontName.hasPrefix(".")
                ? NSFont.systemFont(ofSize: basis.fontSize)
                : nil)
        guard let font else { return unchanged("font_unavailable") }
        let reportedWidth = (sampleText as NSString).size(
            withAttributes: [.font: font]
        ).width
        guard reportedWidth.isFinite, reportedWidth > 0 else { return unchanged("width_invalid") }
        let scale = sampleBounds.width / reportedWidth
        guard scale.isFinite, (0.75...2).contains(scale) else { return unchanged("scale_outside_bounds") }
        if abs(scale - 1) < 0.05 { return unchanged("attributed_width_verified") }
        let fittedSize = basis.fontSize * scale
        diagnostic?("typography_word_measurement")
        return ActiveFieldTextStyle(
            fontName: basis.fontName,
            fontSize: fittedSize,
            foregroundColor: basis.foregroundColor,
            isEstimated: basis.isEstimated
        )
    }

    private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1
            && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1
            && abs(lhs.height - rhs.height) <= 1
    }

    /// Chromium represents an empty editor inconsistently: depending on the
    /// editor layout, the collapsed and line marker ranges can be the
    /// full editor block or one full-width typographic line inside that block.
    /// Both are non-caret geometry and describe the same semantic state.
    private static func isEmptyLineBox(_ line: CGRect, inside frame: CGRect) -> Bool {
        line.width > 0
            && line.height > 0
            && abs(line.minX - frame.minX) <= 1
            && abs(line.minY - frame.minY) <= 1
            && abs(line.width - frame.width) <= 1
            && line.maxY <= frame.maxY + 1
    }

    private static func emptyWebCaret(
        in frame: CGRect,
        style: ActiveFieldTextStyle
    ) -> CGRect? {
        let font = NSFont(name: style.fontName, size: style.fontSize)
            ?? (style.fontName.hasPrefix(".") ? NSFont.systemFont(ofSize: style.fontSize) : nil)
        guard let font else { return nil }
        let height = ceil(font.ascender - font.descender + font.leading)
        guard height.isFinite, height > 0, height <= frame.height else { return nil }
        return CGRect(
            x: frame.minX,
            y: frame.midY - height / 2,
            width: 0,
            height: height
        )
    }

    private static func placeholderMaskBounds(
        for text: String,
        caret: CGRect,
        style: ActiveFieldTextStyle,
        inside frame: CGRect
    ) -> CGRect? {
        let firstLine = String(text.prefix { !$0.isNewline })
        guard !firstLine.isEmpty else { return nil }
        let font = NSFont(name: style.fontName, size: style.fontSize)
            ?? (style.fontName.hasPrefix(".") ? NSFont.systemFont(ofSize: style.fontSize) : nil)
        guard let font else { return nil }
        let measuredWidth = ceil(
            (firstLine as NSString).size(withAttributes: [.font: font]).width
        )
        guard measuredWidth.isFinite, measuredWidth > 0 else { return nil }
        let proposed = CGRect(
            x: caret.minX - 1,
            y: caret.minY - 1,
            width: measuredWidth + 2,
            height: caret.height + 2
        )
        let clipped = proposed.intersection(frame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }

    /// A single grapheme is never wider than a few line heights; Chromium
    /// answers character ranges with line or element boxes when it has no
    /// inline text boxes, and those must not pose as glyph geometry.
    static func isGraphemeBox(_ bounds: CGRect) -> Bool {
        isUsableTextBounds(bounds) && bounds.width > 0 && bounds.width <= bounds.height * 4
    }

    /// A line box that is wider than its text could possibly be is a block
    /// box, whose trailing edge says nothing about the caret.
    static func isPlausibleLineExtent(_ bounds: CGRect, characterCount: Int) -> Bool {
        guard isUsableTextBounds(bounds), characterCount > 0 else { return false }
        let maximumWidth = CGFloat(characterCount) * bounds.height * 1.2 + 8
        return bounds.width <= maximumWidth
    }

    /// Numeric AX ranges are an independent capability from marker bounds.
    /// Use them only on the owned text node and corroborate a visual line with
    /// its first/last grapheme. A wrapped block is never a line measurement.
    static func ownedVisualLineBounds(
        focusedText: FocusedEditableText, nodeRole: String?, nodeText: String?,
        lineTextBefore: String, lineTextAfter: String, inputFrame: CGRect?,
        readBounds: (NSRange) -> CGRect?
    ) -> CGRect? {
        let line = lineTextBefore + lineTextAfter
        guard nodeRole == kAXStaticTextRole as String,
              let nodeText, !nodeText.isEmpty,
              focusedText.selectionLength == 0, focusedText.selectedText.isEmpty,
              focusedText.textBefore.hasSuffix(lineTextBefore),
              focusedText.textAfter.hasPrefix(lineTextAfter),
              !line.isEmpty, line.utf16.count <= 2_000,
              !line.contains(where: \Character.isNewline),
              let first = line.first, let last = line.last,
              let inputFrame, isUsableTextBounds(inputFrame)
        else { return nil }
        // Numeric AX ranges belong to the selected text node, not its editor.
        // A wrapped final paragraph is a valid owned node even when earlier
        // paragraphs exist. Map the cursor to that node before reading bounds.
        let nodeSelection: Int
        if nodeText == focusedText.textBefore + focusedText.textAfter {
            nodeSelection = focusedText.selectionLocation
        } else if focusedText.textAfter.isEmpty,
                  !nodeText.contains(where: \Character.isNewline),
                  focusedText.textBefore.hasSuffix("\n" + nodeText) {
            nodeSelection = nodeText.utf16.count
        } else { return nil }
        let start = nodeSelection - lineTextBefore.utf16.count
        guard start >= 0, start <= nodeText.utf16.count,
              line.utf16.count <= nodeText.utf16.count - start else { return nil }
        let range = NSRange(location: start, length: line.utf16.count)
        guard let ownedRange = Range(range, in: nodeText),
              String(nodeText[ownedRange]) == line else { return nil }
        let lastLength = String(last).utf16.count
        guard let whole = readBounds(range),
              let leading = readBounds(NSRange(location: start, length: String(first).utf16.count)),
              let trailing = readBounds(NSRange(location: NSMaxRange(range) - lastLength, length: lastLength)),
              isUsableTextBounds(whole), isGraphemeBox(leading), isGraphemeBox(trailing),
              inputFrame.contains(whole), whole.insetBy(dx: -1, dy: -1).contains(leading),
              whole.insetBy(dx: -1, dy: -1).contains(trailing),
              abs(whole.minY - leading.minY) <= 1, abs(whole.minY - trailing.minY) <= 1,
              abs(whole.height - leading.height) <= 1, abs(whole.height - trailing.height) <= 1,
              abs(whole.minX - min(leading.minX, trailing.minX)) <= 1,
              abs(whole.maxX - max(leading.maxX, trailing.maxX)) <= 1
        else { return nil }
        return whole
    }

    static func measuredNodeTextStyle(
        focusedText: FocusedEditableText, nodeRole: String?, nodeText: String?,
        currentLineText: String?, nodeBounds: CGRect?, inputFrame: CGRect?
    ) -> ActiveFieldTextStyle? {
        guard let measured = markerNodeLineEdgeCandidate(
            focusedText: focusedText, nodeRole: nodeRole, nodeText: nodeText,
            currentLineText: currentLineText, nodeBounds: nodeBounds, inputFrame: inputFrame
        ), let text = nodeText, text.count >= 4 else { return nil }
        // This is an explicit approximation of the face, not a recovered host font.
        // Fit to the owned text's width. Editor/caret height never sets font size.
        func width(at size: CGFloat) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .regular)]).width
        }
        var lower: CGFloat = 6
        var upper: CGFloat = 72
        guard measured.rect.width >= width(at: lower),
              measured.rect.width <= width(at: upper) else { return nil }
        // SF changes optical metrics across point sizes: a linear width ratio
        // makes smaller text too large and larger text too small.
        for _ in 0..<12 {
            let middle = (lower + upper) / 2
            if width(at: middle) < measured.rect.width { lower = middle }
            else { upper = middle }
        }
        let size = (lower + upper) / 2
        let font = NSFont.systemFont(ofSize: size, weight: .regular)
        let fontHeight = ceil(font.ascender - font.descender + font.leading)
        let fittedWidth = (text as NSString).size(withAttributes: [.font: font]).width
        // Reject editor blocks, wrapped unions, and inconsistent measurements.
        // Height is only a rejection check, never a calibration input.
        guard fontHeight <= measured.rect.height + 2,
              fontHeight >= measured.rect.height * 0.65,
              abs(fittedWidth - measured.rect.width) <= max(1, measured.rect.width * 0.03)
        else { return nil }
        return ActiveFieldTextStyle(fontName: font.fontName, fontSize: size, isEstimated: true)
    }

    static func markerNodeLineEdgeCandidate(
        focusedText: FocusedEditableText,
        nodeRole: String?,
        nodeText: String?,
        currentLineText: String?,
        nodeBounds: CGRect?,
        inputFrame: CGRect?
    ) -> CaretGeometryCandidate? {
        // Some web AX trees map the selected text marker to an exact inline
        // text node while returning detached screen bounds for the marker
        // range itself. Ownership was checked through the selected marker's
        // ancestry. Its value must be the complete final paragraph and current
        // visual line, not necessarily the whole multi-paragraph editor.
        // Require the text node itself; editor/group boxes do not measure ink.
        // A one-line editor may have the same height as its text node.
        guard nodeRole == kAXStaticTextRole as String,
              focusedText.selectionLength == 0,
              focusedText.selectedText.isEmpty,
              focusedText.textAfter.isEmpty,
              let nodeText, !nodeText.isEmpty,
              !nodeText.contains(where: \Character.isNewline),
              (nodeText == focusedText.textBefore
                || focusedText.textBefore.hasSuffix("\n" + nodeText)),
              currentLineText == nodeText,
              let nodeBounds,
              let inputFrame,
              isUsableTextBounds(nodeBounds),
              isUsableTextBounds(inputFrame),
              isPlausibleLineExtent(
                  nodeBounds,
                  characterCount: nodeText.utf16.count
              ),
              inputFrame.insetBy(dx: -4, dy: -4).contains(nodeBounds)
        else { return nil }
        return CaretGeometryCandidate(rect: nodeBounds, source: .lineEnd)
    }

    static func terminalLineEdgeCandidate(
        lineBounds: CGRect,
        lineTextBefore: String,
        lineTextAfter: String,
        markerNodeCandidate: CaretGeometryCandidate?
    ) -> CaretGeometryCandidate? {
        let lineLength = lineTextBefore.utf16.count + lineTextAfter.utf16.count
        // The measured text node has already proved identity, a complete
        // visual line and field containment. Do not replace it with a marker
        // range merely because the opposite edge of that range fits.
        if let markerNodeCandidate { return markerNodeCandidate }
        if lineLength == 0 {
            return CaretGeometryCandidate(rect: lineBounds, source: .lineStart)
        }
        guard isPlausibleLineExtent(lineBounds, characterCount: lineLength) else {
            return nil
        }
        if lineTextAfter.isEmpty {
            return CaretGeometryCandidate(rect: lineBounds, source: .lineEnd)
        }
        if lineTextBefore.isEmpty {
            return CaretGeometryCandidate(rect: lineBounds, source: .lineStart)
        }
        return nil
    }

    static func effectiveTerminalLineBounds(
        reportedLineBounds: CGRect,
        selectedCandidate: CaretGeometryCandidate
    ) -> CGRect {
        selectedCandidate.rect == reportedLineBounds
            ? reportedLineBounds
            : selectedCandidate.rect
    }


}

/// Text-marker queries against one `AXWebArea`. Every call is a bounded IPC
/// round trip; results are only ever structural or bounded text.
private struct TextMarkerReader {
    enum Keep { case prefix, suffix }

    struct BoundedString {
        let text: String
        let fullLength: Int
    }

    let webArea: AXUIElement

    func selectedRange(fallback element: AXUIElement, failed: (WebTextReadStage) -> Void) -> AXTextMarkerRange? {
        var errors: [AXError] = []
        // The focused editor owns its selection. A document can retain a
        // selection elsewhere in the conversation even after focus moves.
        for provider in [element, webArea] {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(provider, "AXSelectedTextMarkerRange" as CFString, &value)
            if error == .success, let range = markerRange(value) { return range }
            errors.append(error)
        }
        // Preserve outcomes of the two existing reads; no extra AX queries or
        // text are collected for diagnostics. Mixed failures remain distinct
        // from a consistently absent or unsupported selection capability.
        if errors.contains(.cannotComplete) { failed(.selectionUnavailable) }
        else if errors.allSatisfy({ $0 == .noValue }) { failed(.selectionNoValue) }
        else if errors.allSatisfy({ $0 == .attributeUnsupported }) { failed(.selectionUnsupported) }
        else if errors.contains(.success) { failed(.selectionInvalidValue) }
        else { failed(.selection) }
        return nil
    }

    func range(forElement element: AXUIElement) -> AXTextMarkerRange? {
        for provider in [webArea, element] {
            if let range = markerRange(
                parameterized("AXTextMarkerRangeForUIElement", of: provider, parameter: element)
            ) {
                return range
            }
        }
        return nil
    }

    func element(
        for marker: AXTextMarker,
        within element: AXUIElement,
        failed: (WebTextReadStage) -> Void
    ) -> AXUIElement? {
        guard let node = parameterized("AXUIElementForTextMarker", of: webArea, parameter: marker),
              CFGetTypeID(node) == AXUIElementGetTypeID()
        else { failed(.selectionMapping); return nil }
        var current = unsafeDowncast(node, to: AXUIElement.self)
        for _ in 0..<32 {
            if CFEqual(current, element) {
                return unsafeDowncast(node, to: AXUIElement.self)
            }
            if let role = attribute(kAXRoleAttribute as String, of: current) as? String,
               ["AXWebArea", "AXWindow", "AXApplication"].contains(role) {
                failed(.selectionOutsideField)
                return nil
            }
            guard let parent = attribute(kAXParentAttribute as String, of: current),
                  CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { failed(.selectionAncestry); return nil }
            current = unsafeDowncast(parent, to: AXUIElement.self)
        }
        failed(.selectionAncestryLimit)
        return nil
    }

    func string(from start: AXTextMarker, to end: AXTextMarker) -> String? {
        parameterized(
            "AXStringForTextMarkerRange",
            of: webArea,
            parameter: AXTextMarkerRangeCreate(nil, start, end)
        ) as? String
    }

    func attributedString(from start: AXTextMarker, to end: AXTextMarker) -> NSAttributedString? {
        parameterized(
            "AXAttributedStringForTextMarkerRange",
            of: webArea,
            parameter: AXTextMarkerRangeCreate(nil, start, end)
        ) as? NSAttributedString
    }

    func length(from start: AXTextMarker, to end: AXTextMarker) -> Int? {
        (parameterized(
            "AXLengthForTextMarkerRange",
            of: webArea,
            parameter: AXTextMarkerRangeCreate(nil, start, end)
        ) as? NSNumber)?.intValue
    }

    func bounds(from start: AXTextMarker, to end: AXTextMarker) -> CGRect? {
        guard let raw = parameterized(
            "AXBoundsForTextMarkerRange",
            of: webArea,
            parameter: AXTextMarkerRangeCreate(nil, start, end)
        ), CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cgRect else { return nil }
        var rectangle = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rectangle) else { return nil }
        return rectangle
    }

    func previousMarker(of marker: AXTextMarker) -> AXTextMarker? {
        textMarker(parameterized("AXPreviousTextMarkerForTextMarker", of: webArea, parameter: marker))
    }

    func previousWordStartMarker(of marker: AXTextMarker) -> AXTextMarker? {
        textMarker(
            parameterized(
                "AXPreviousWordStartTextMarkerForTextMarker",
                of: webArea,
                parameter: marker
            )
        )
    }

    func nextMarker(of marker: AXTextMarker) -> AXTextMarker? {
        textMarker(parameterized("AXNextTextMarkerForTextMarker", of: webArea, parameter: marker))
    }

    func lineRange(at marker: AXTextMarker) -> AXTextMarkerRange? {
        markerRange(parameterized("AXLineTextMarkerRangeForTextMarker", of: webArea, parameter: marker))
    }

    func paragraphRange(at marker: AXTextMarker) -> AXTextMarkerRange? {
        markerRange(
            parameterized("AXParagraphTextMarkerRangeForTextMarker", of: webArea, parameter: marker)
        )
    }

    /// Reads at most `maximumUTF16Units` of text next to `keeping` end of the
    /// range without reading a whole long document on every poll. Long
    /// documents are walked paragraph by paragraph from the selection.
    func boundedString(
        from start: AXTextMarker,
        to end: AXTextMarker,
        maximumUTF16Units: Int,
        keeping: Keep
    ) -> BoundedString? {
        let fullLength = length(from: start, to: end)
        if let fullLength, fullLength > maximumUTF16Units * 3 {
            var cursor = keeping == .suffix ? end : start
            for _ in 0..<64 {
                let nextName = keeping == .suffix
                    ? "AXPreviousParagraphStartTextMarkerForTextMarker"
                    : "AXNextParagraphEndTextMarkerForTextMarker"
                guard let moved = textMarker(
                    parameterized(nextName, of: webArea, parameter: cursor)
                ), !CFEqual(moved, cursor) else { break }
                cursor = moved
                let covered = keeping == .suffix
                    ? length(from: cursor, to: end)
                    : length(from: start, to: cursor)
                if let covered, covered >= maximumUTF16Units { break }
            }
            let partial = keeping == .suffix
                ? string(from: cursor, to: end)
                : string(from: start, to: cursor)
            guard let partial else { return nil }
            return BoundedString(
                text: bounded(partial, maximumUTF16Units: maximumUTF16Units, keeping: keeping),
                fullLength: fullLength
            )
        }
        guard let text = string(from: start, to: end) else { return nil }
        return BoundedString(
            text: bounded(text, maximumUTF16Units: maximumUTF16Units, keeping: keeping),
            fullLength: fullLength ?? text.utf16.count
        )
    }

    private func bounded(_ text: String, maximumUTF16Units: Int, keeping: Keep) -> String {
        guard text.utf16.count > maximumUTF16Units else { return text }
        switch keeping {
        case .prefix:
            return BoundedText.prefix(
                text[...],
                maximumUTF16Units: maximumUTF16Units
            )
        case .suffix:
            return BoundedText.suffix(
                text[...],
                maximumUTF16Units: maximumUTF16Units
            )
        }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func parameterized(
        _ name: String,
        of element: AXUIElement,
        parameter: CFTypeRef
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            name as CFString,
            parameter,
            &value
        ) == .success else { return nil }
        return value
    }

    private func markerRange(_ value: CFTypeRef?) -> AXTextMarkerRange? {
        guard let value, CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXTextMarkerRange.self)
    }

    private func textMarker(_ value: CFTypeRef?) -> AXTextMarker? {
        guard let value, CFGetTypeID(value) == AXTextMarkerGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXTextMarker.self)
    }
}
