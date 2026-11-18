# Selected-text transforms

Transforms use the same `google/gemini-3.5-flash-lite` AI Gateway route as completion,
with low reasoning effort and no retries.
A rewrite must finish normally before it can be applied. Model latency has not
been measured by this implementation's Linux verification.

## Product flow

1. In Settings → Writing, enable rewrite shortcuts. The switch saves immediately.
2. Select editable text and press the action's Option + number shortcut.
3. The completed rewrite replaces only that selection. There is no review panel or
   second acceptance key. Nothing submits the host form.
4. Typing, changing selection or switching fields before replacement cancels the request.
   Escape cancels pending work. Failure leaves the selection unchanged when no write
   has occurred and uses the native alert sound.

The main settings section is a compact action list. Edit opens a native sheet;
Save applies its changes and Cancel leaves the saved action untouched.

The helper only transforms an explicitly selected, completely captured range.
The existing capture contract bounds selections at 2,000 UTF-16 units; a longer
selection is rejected, never silently shortened. Output is bounded at 8,000
UTF-16 units. Some characters, including many emoji, occupy two or more units.
Unsupported/secure fields and empty selections do not make a transform request.

## Runtime and privacy

- Protocol v4 ships with desktop and helper together; v3 is rejected.
- `transform_configure` sends names, identities and shortcut numbers to the
  helper. Instructions and writing examples stay in the desktop until needed.
- `transform_request` includes the selected text and an immutable work identity.
- Desktop resolves the chosen transform and calls authenticated
  `POST /v1/transforms`; credentials never reach the renderer.
- Settings are saved in a separate OS-encrypted `secure/transforms.bin` file.
  Saves are serialized. Restore defaults asks for confirmation, then saves while preserving the enable switch.
- No draft, result or example text is logged. Source text and output are kept in
  memory for the current request; explicitly saved examples are retained.
- Requests send only the selection, rules and examples. They do not fetch the
  grounding profile or surrounding fields.
- Typing, pointer changes, Escape, disablement, settings changes and superseding
  requests invalidate work. The helper polls focus/content while waiting and
  revalidates immediately before presenting and writing. Queued insertion checks
  cancellation again before writing. Autocomplete is suspended during a transform.
- The API rejects empty, oversized, invalid-control-character and inappropriate
  multiline results; the generator rejects non-`stop` finishes. No partial text
  is applied after provider/network failure. Desktop waits at most 16 seconds;
  helper waits 17 seconds.
- Native AX selected-text replacement is used where supported; editable web
  surfaces use the existing Unicode insertion route. Both verify the resulting
  selection and surrounding captured text. A failed write is never retried.
  Host undo support and rich-text formatting preservation are not guaranteed.

## Verification

The earlier Electron settings prototype had a Playwright check of editing,
preview, save and reload with a synthetic bridge. The current implementation
uses native settings; that historical browser evidence does not validate this
UI, Keychain storage, real model performance, or native replacement. Linux
verification covers TypeScript and Swift syntax, not AppKit execution.

Before shipping, on macOS run:

```sh
swift test --package-path native/macos
bun run --cwd apps/desktop build:mac-helper
```

Then test the packaged app against the matching API in Notes, TextEdit, and
Chrome/Safari editable fields:

- Polish, Improve prompt and custom instructions; compare
  selected text and final host text, including prefix and suffix.
- Multiple paragraphs, Spanish, RTL text and emoji; 2,000-unit boundary and
  selections exceeding it; empty/whitespace selections and no selection.
- Direct replacement, Escape, typing while waiting, pointer focus changes, Cmd+Tab,
  repeated shortcuts, rapid re-trigger, disablement and permission revocation.
- Cancellation while insertion is queued; field changes between
  generation and insertion. No write may target another field.
- Secure fields, unavailable AX capabilities, single-line inputs, network loss,
  expired authentication, incomplete model output and request timeout.
- Check host undo and formatting behavior explicitly; do not infer them from
  plain-text replacement success. Replacement must not take keyboard focus.

No deployment, signed/notarized build, native test run, or physical-Mac proof is
claimed by the Linux results.

## Punctuation

The generator is instructed not to introduce em dashes when the selected input
has none. A model output violating that rule is rejected before replacement;
there is no retry or second generation. Existing em dashes remain permitted.

## Replacement boundaries

Rewrites preserve the selection's surrounding whitespace. A selection with no
internal line breaks stays one paragraph; a selection without blank lines does
not acquire them. Surrounding source text is not rewrite input, so live changes
to that text do not cancel an unchanged selection. A changed source/thread
identity, field, selection or draft still cancels.

Autocomplete Everywhere tags its own synthesized Unicode events with a process-local marker. The
keyboard monitor passes those events through without feeding them back as user
typing. The marker grants no insertion authority; fresh target checks still
control replacement. Physical typing and Escape continue to cancel pending work.
