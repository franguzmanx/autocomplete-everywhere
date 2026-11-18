# Inline assistance: decision matrix

Current implementation index, 2026-09-08. This document maps policy to its existing owner; it is not a new runtime rules engine. Product scope lives in [product intelligence](../product-intelligence/README.md). Real-app coverage lives in the [scenario atlas](../product-intelligence/scenario-atlas.md) and dated QA reports.

## Operating model

Capture evidence → schedule one request → generate a candidate → lay out a visible insertion → verify and commit that insertion.

Current source evidence reaches the model even in an automatically triggered empty field; structural proximity alone does not prove it is the reply target.

Generation answers what to write. Layout answers what can be displayed. Insertion answers whether the destination is still the verified field. A layout rejection is not model abstention. A cancelled request is not a rejected suggestion. “Ready” configuration is not evidence that a suggestion was displayed.

Use established text-system operations: attributed text, character/glyph ranges, native shaping and line breaking, measured containers, layout invalidation, and fresh validation before insertion. Autocomplete Everywhere already uses AppKit TextKit/NSLayoutManager and Core Text. Do not replace these with estimated character widths, per-app padding, font shrinking or a custom shaping engine. Unlike an editor that owns its text view, Autocomplete Everywhere observes another process: host text-container geometry and focus are additional evidence requirements that a text layout framework alone cannot supply.

## Rule priority

1. **Hard invariants:** secure/excluded fields, current destination identity, valid Unicode, exact visible insertion. Neither a manual request nor eagerness overrides these.
2. **Recoverable capability failures:** stale or missing geometry, space insufficient for the current candidate. Reacquire or fit within the same current identity; do not classify these as model uncertainty or teach them as rejection.
3. **Interaction policy:** pause, invocation mode and dismissal cooldown. Manual invocation overrides only the documented automatic scheduling gates.
4. **Semantic judgment:** usefulness, intent and source relevance belong to the model; they cannot override insertion invariants. There is no single numeric confidence slider spanning all four classes.

A new rule needs one owner, an input/evidence definition, a reason code or documented diagnostic gap, and a behavior test. Do not duplicate the same gate in capture, prompt and presenter without a separate invariant at each boundary.

## Rules and ownership

Paths below are relative to the repository root. Tests refer to `native/macos/Tests/AutocompleteHelperTests/` unless specified otherwise.

| ID | Decision / evidence | Owner | Expected action | Regression coverage |
|---|---|---|---|---|
| C1 | Paused, excluded app, secure field, permission unavailable | `SuggestionController`, `SystemAccessibilityReader`, configuration | Do not capture/request/insert; manual invocation does not override | Configuration, permission and controller tests |
| C2 | Field identity or content changed | `ActiveFieldMonitor`, `SuggestionSession` | Cancel obsolete work; capture the current field | `ActiveFieldMonitorTests`, `SuggestionSessionTests` |
| C3 | Read-only context | `SystemAccessibilityReader.sourceContexts`, `FieldSource` | Visible structural sources only; deduplicate, at most 24 fragments/12,000 UTF-16 units | `FieldContextTests`, `ReadOnlySourceTraversalTests`, `SourceVisibilityTests` |
| S1 | Automatic invocation has authored text, related editable context or current sources | `SuggestionRequestEligibility` in `Suggestions/FieldContext.swift` | Request; empty bare focus alone does not establish an authored task | `FieldContextTests` |
| S2 | Explicit invocation | `SuggestionController.beginSuggestion` | Bypass automatic-eligibility and dismissal cooldown; preserve C1/C2 and insertion gates | `SuggestionControllerTests` |
| S3 | Explicit dismissal | `SuggestionCooldown` | Wait for edit and 1 second, or 3 seconds after repeated dismissal within a minute; do not treat geometry failure or ordinary typing as negative feedback | `SuggestionCooldownTests` |
| G1 | Task, speaker, source authority and current language | `services/api/src/prompts/continuation.ts` | Prefer a useful grounded continuation; do not invent user beliefs or treat structural source order as chronology | API prompt/continuation tests; real conversation quality still needs app evidence |
| G2 | Invalid output, timeout, cancellation versus deliberate silence | `services/api/src/models/generate.ts`, `services/api/src/app.ts` | Distinct error or empty-success outcomes; do not hide invalid output as silence | API generator/route tests |
| G3 | Field shape | `deriveSuggestionOutputBudget` | Single-line formatting versus multiline allowance; not an estimate of currently visible space | API output-budget tests |
| L1 | Current caret, font, paragraph/container metrics, display | `GhostTextPresenter`, `ParagraphMirrorLayout` | Use measured geometry and native layout; font does not grow/shrink to fill space | `GhostTextPresenterTests`, `ParagraphMirrorLayoutTests` |
| L2 | Whole candidate fits | `GhostTextPresenter` | Display the exact final candidate | Presenter/session tests |
| L3 | Only a prefix fits on initial presentation | `GhostTextPresenter`, `VisibleSuggestionPrefix` | Prefer word boundary; when no whole word fits, native cluster measurement may offer a grapheme-safe prefix; re-layout and verify containment | `VisibleSuggestionPrefixTests`, narrow-line presenter tests |
| L4 | Link or exact artifact would be split | `VisibleSuggestionPrefix`, `SuggestionSession` | Keep that range indivisible; a preceding valid prefix may still appear | Prefix and presenter artifact tests |
| L5 | Already displayed text moves or geometry changes | `GhostTextPresenter.reanchor`, `SuggestionController` | Revalidate the same final text; never revive the discarded suffix or silently change the acceptance payload | Presenter/controller reanchor tests |
| L6 | No valid visible glyphs, unknown geometry, detached caret | Presenter/monitor/controller | Do not draw outside verified bounds; retain/reacquire only while content identity remains valid | Layout rejection and controller tests; real editor cases remain open |
| I1 | Tab/accept shortcut with a valid visible suggestion | `SuggestionController`, `SuggestionSession`, `NotesTextInserter` (shared inserter despite historical name) | Fresh focus/range validation; insert precisely the visible text once | Controller/session/inserter tests |
| I2 | No valid suggestion or insertion preparation fails | Keyboard/controller/inserter | Preserve host key behavior; no invisible insertion | Controller and keyboard tests |
| I3 | Accepted text changes or observation is lost | Interaction observation / personalization | Only verified edits support learning; lost observation is unknown | Observation/personalization tests |

Timing is selectable: Instant (0 ms), Quick (150 ms), Balanced (300 ms), Deliberate (700 ms). Instant permits first-capture generation; it does not bypass current geometry or insertion validation. See [Instant verification](../qa/2026-09-08-instant-timing.md).

## Rendering decision table

| Situation | Initial presentation | Geometry refresh / acceptance |
|---|---|---|
| Complete candidate is inside the measured visible region | Show complete text | Keep exact text; verify destination |
| Whole words fit, remaining text overflows below | Select exact visible prefix, lay it out again | Discarded suffix stays discarded |
| First word wraps away, but some characters fit at the caret | Core Text cluster break proposes a prefix; Unicode/artifact checks and paragraph layout validate it | Same exact visible-prefix authority |
| Only whitespace fits | Do not display whitespace as a suggestion | Wait for usable geometry/authored edit |
| Only part of a grapheme, link or exact artifact fits | Do not split that unit | No hidden accepted remainder |
| Caret/font/container evidence is missing or inconsistent | Reject with a layout/capture reason | Reacquire current evidence; never guess app offsets |
| Candidate begins with a newline that has no visible text space below it | Still an open physical constraint | Do not flatten exact content or expand a foreign editor behind the user's back |

## Observable outcomes and gaps

Existing timeline: `request_received`, `context_prepared`, `http_end`, `helper_write` (`text`/`silence`), `final_received`, `presentation_overflow`, `present_rejected`, `presented`, interaction outcomes. Correlate by request identity; log categories and counts only, never drafts or suggestions.

Do not call the current diagnostics complete: some pre-request scheduling gates only mark a snapshot handled and do not emit their own categorical suppression reason. Instrument those before claiming every silent attempt has a fully explained outcome. The explicit flag is recorded only once a request reaches desktop.

Observed in the current package window starting 2026-09-08 23:26:52 UTC, before the narrow-line correction: 22 requests; 15 cancelled; 7 completed (5 text, 2 silence); 3 presented and 2 rejected for vertical overflow/no safe prefix. No explicit request reached desktop in that sample. These are local diagnostic counts, not app-specific attribution, acceptance rates or a controlled model-quality benchmark.

## Open work, in order

1. Validate the narrow-line correction in packaged real surfaces; native tests are not Codex proof.
2. Give each pre-request stop an explicit categorical reason and test manual invocation from key handling to request creation.
3. Reproduce missing/late geometry and leading-newline cases without changing typography to conceal insufficient space.
4. Consider feeding verified display capacity into generation only after defining that capability independently of field shape. Do not assume every multiline editor has room for a block.
5. Evaluate model silence against owned conversation fixtures. Do not increase generation frequency to hide layout loss or count typing cancellation as model reluctance.

## Primary references

- [Apple Text Layout Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextLayout/Concepts/LayoutManager.html): character/glyph conversion, layout and invalidation.
- [Apple Core Text cluster line breaking](https://developer.apple.com/documentation/coretext/cttypesettersuggestclusterbreak(_:_:_:)): native cluster measurement.
- [Apple typography concepts](https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/TypoFeatures/TextSystemFeatures.html): glyphs versus characters, line breaking, baselines and font metrics.

These support the text-system techniques, not a claim that Accessibility guarantees equivalent geometry in every application.
