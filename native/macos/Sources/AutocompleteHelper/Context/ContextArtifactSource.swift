import Foundation

@MainActor
final class ContextArtifactSource {
    typealias Artifact = SuggestionRequestMessage.Payload.Artifact

    private static let maximumArtifactCharacters = 4_000

    private let clipboardChangeCount: () -> Int
    private let clipboardText: () -> String?
    private var configuration = CaptureConfiguration.disabled
    private var clipboardVersion: Int?
    private var clipboardArtifact: Artifact?
    private var selectionArtifact: Artifact?

    init(
        clipboardChangeCount: @escaping () -> Int,
        clipboardText: @escaping () -> String?
    ) {
        self.clipboardChangeCount = clipboardChangeCount
        self.clipboardText = clipboardText
    }

    func updateConfiguration(_ configuration: CaptureConfiguration) {
        let exclusionsChanged = self.configuration.excludedApplications != configuration.excludedApplications
        self.configuration = configuration
        if !configuration.isEnabled || exclusionsChanged {
            clipboardVersion = nil
            clipboardArtifact = nil
            selectionArtifact = nil
        } else if !configuration.clipboardContextEnabled {
            clipboardVersion = nil
            clipboardArtifact = nil
        }
    }

    func artifacts(selectedText: String, timestampMs: Int64) -> [Artifact] {
        observeSelection(selectedText, timestampMs: timestampMs)
        observeClipboard(timestampMs: timestampMs)
        expireArtifacts(timestampMs: timestampMs)
        return [selectionArtifact, clipboardArtifact].compactMap { $0 }
    }

    private func observeSelection(_ selectedText: String, timestampMs: Int64) {
        guard configuration.isEnabled,
              !selectedText.isEmpty,
              selectedText.utf16.count <= Self.maximumArtifactCharacters
        else {
            return
        }
        selectionArtifact = Artifact(
            id: "selection-recent",
            kind: "selection",
            text: selectedText,
            capturedAtMs: timestampMs
        )
    }

    private func observeClipboard(timestampMs: Int64) {
        guard configuration.isEnabled, configuration.clipboardContextEnabled else {
            return
        }
        let version = clipboardChangeCount()
        guard version != clipboardVersion else { return }
        clipboardVersion = version
        guard let text = clipboardText(),
              !text.isEmpty,
              text.utf16.count <= Self.maximumArtifactCharacters
        else {
            clipboardArtifact = nil
            return
        }
        clipboardArtifact = Artifact(
            id: "clipboard-current",
            kind: "clipboard",
            text: text,
            capturedAtMs: timestampMs
        )
    }

    private func expireArtifacts(timestampMs: Int64) {
        if let artifact = selectionArtifact,
           !ContextArtifactFreshness.isFresh(artifact, at: timestampMs)
        {
            selectionArtifact = nil
        }
        if let artifact = clipboardArtifact,
           !ContextArtifactFreshness.isFresh(artifact, at: timestampMs)
        {
            clipboardArtifact = nil
        }
    }
}
