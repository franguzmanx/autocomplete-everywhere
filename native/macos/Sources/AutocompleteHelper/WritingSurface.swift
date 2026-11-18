import Foundation

/// The host family is a capability classification, not an application
/// allowlist. Native text controls answer index-based Accessibility text
/// queries; web content (WebKit, Chromium, Electron) answers text-marker
/// queries under an `AXWebArea`.
enum WritingSurface: String, Equatable, Hashable, Sendable {
    case native
    case web

    var isWebContent: Bool { self == .web }

    /// Coarse capability class sent to the backend. Application identity is
    /// separate context and never changes capture or rendering behavior.
    var protocolValue: String {
        isWebContent ? "web_textarea" : "text_editor"
    }

    static func classify(isWebContent: Bool) -> WritingSurface {
        isWebContent ? .web : .native
    }
}
