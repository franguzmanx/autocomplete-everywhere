import AppKit
import SwiftUI

/// Isolated practice field. The reply is a real NSTextView (accessibility identifier `autocompletion-exercise`)
/// so the capture helper handles it exactly like any other application field.
struct ExerciseSheet: View {
    static let sourceText = "Can you send the deck by Friday?"
    static let settingsBundleIdentifier = "com.autocompletion.settings"

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n[.exerciseTitle])
                .font(.title2.weight(.semibold))

            // The source and composer form one AX group, like a conversation.
            // Changing practice feedback outside this group must not revise the reply source.
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n[.exerciseSourceLabel])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Self.sourceText)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        )
                        .accessibilityIdentifier("autocompletion-exercise-source")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n[.exerciseReplyLabel])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ExerciseTextView(text: $reply, accessibilityLabel: l10n[.exerciseReplyLabel])
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("autocompletion-practice-conversation")

            Text(l10n[store.effectiveAutomatic ? .exerciseIdleAutomatic : .exerciseIdleOnRequest])
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            if let error = store.exerciseError {
                Text(l10n.format(.exerciseActivationFailed, error))
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 8) {
                Text(l10n[.exerciseKeys])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l10n[.requestSuggestion]) {
                    NSApp.activate(ignoringOtherApps: true)
                    store.requestExerciseSuggestion()
                }
                .disabled(store.isBusy(.requestExerciseSuggestion) || store.exerciseStarting)
                Button(l10n[.done]) { store.closeExercise() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 544)
    }

}

/// Plain-text NSTextView bound to SwiftUI state. Automatic substitutions are off so the field
/// behaves like a predictable message composer.
private struct ExerciseTextView: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.setAccessibilityIdentifier("autocompletion-exercise")
        textView.setAccessibilityLabel(accessibilityLabel)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.setAccessibilityLabel(accessibilityLabel)
        if textView.string != text {
            textView.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
