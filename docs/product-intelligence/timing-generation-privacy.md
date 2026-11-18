# Timing, generation and privacy

**Current contract — 2026-09-04**

For the proposed separation of preparation, generation start and display timing, see the [complete product design](invisible-intelligence-product-design.md#4-velocidad-y-momento-de-intervención). Its adaptive timing and background learning are not part of the implementation described below.

A suggestion is useful only while it belongs to the current field and writing opportunity. Generation and safe presentation are separate responsibilities.

## Final-only lifecycle

Observe eligible field → allow host publication and a quiet interval → capture bounded evidence → one request → one complete response → validate current identity and geometry → one ghost or silence.

There is no visible or hidden streaming transport in the product request path, no partial suggestion protocol and no model/provider fallback. Incompatible text or focus invalidates the result. Scroll hides the ghost while its anchor is reacquired. Tab and direct click insert only when the native session is current and accept-ready.

## Browsing alternatives

While a valid ghost is visible, hold Option and tap Down to select the next version. At the newest version, Down explicitly requests one new alternative from the same Qwen/Cerebras engine. Option + Up returns to a previous version without a model request and stops at the first retained version. Releasing Option leaves the selected ghost visible; it inserts nothing. Tab accepts that version, Option + Tab accepts its next word, and Escape dismisses the suggestion and its history. Option + Left/Right retain their native editing behavior.

The current ghost stays usable while an alternative is pending. Repeated presses do not queue generations. Returning to a cached version cancels pending generation; late replies cannot replace that selection. Failed, empty, or duplicate responses keep the current version. History retains at most five versions in process memory, dropping the oldest when necessary. Each alternative has its own request identity and passes the same native validity, geometry and insertion checks as the first suggestion.

Typing, caret/selection or target changes, dismissal, exclusions, disabling, and acceptance clear this history and cancel pending alternatives. After word acceptance, new alternatives apply only to the remaining continuation at the new cursor. Merely browsing or showing a version does not establish authorship or feed recent writing or preference learning. Request-scoped `alternativeTo` contains prior candidates solely to ask for different wording; it is separate from authored artifacts and never logged or persisted. Original capture timestamps govern selection (one minute), recent writing and accepted completions (five minutes), and clipboard (ten minutes). Requesting another version after its evidence expires retires the old ghost/history and takes a fresh capture. A response whose evidence expires during generation is discarded; neither a new request ID nor a clock rollback renews old evidence.

## Generation contract

Qwen/Cerebras decides useful length, language, tone and structure from the current writing and evidence. A multiline field permits paragraphs regardless of whether it already contains text. A short continuation remains valid. A single-line field permits one line.

The current generation implementation uses plain final text for artifact-free single-line requests, and final structured composition for multiline or artifact-bearing requests. Multiline uses `low` reasoning; single-line uses `none`, including single-line requests with artifacts. This is the actual physical-shape policy, not an assertion that all complex tasks receive extra reasoning. Any adjustment requires recording the exact pair/settings and checking product quality and latency.

Current line/block deadlines are upper bounds, not expected latency. Do not describe a route as faster without measuring time to a valid visible ghost on the corresponding package and backend.

## Ephemeral context

Recent observed writing and verified accepted insertions live only in bounded memory and expire after five minutes. Selection and opt-in clipboard keep their separate lifetimes. Disabling the effective product configuration clears recent writing; quitting ends the process and its memory. Secure fields never enter the capture or storage path.

No draft, suggestion, clipboard, screenshot or context bodies belong in routine diagnostics. Field identity used for deduplication stays local. Generic source surface and timestamps may accompany artifacts; they do not establish factual authority or that a message was sent.

## Verification

Measure source relevance, factual fidelity, useful length, preserved structure, valid-ghost latency and exactly-once insertion. Test irrelevant, corrected, deleted, expired and rejected context as well as successful transfer. Empty fields without usable context should remain silent. Empty fields with context still require real geometry before displaying or accepting.

Report intentional silence, format failure, timeout, stale response and geometry rejection distinctly wherever instrumentation permits. An absent ghost alone cannot diagnose model quality. Packaged native Tab/click testing remains necessary; browser DOM events bypass the native event tap.


### Request snapshots and surrounding updates

A generation uses the scene captured at the draft's quiet deadline. Text updates to the same read-only source or populated multiline companion field do not cancel an in-flight suggestion. Draft/selection/focus changes, field metadata changes, changes to source/container identity, and changes to single-line companion controls still invalidate it. The next draft request or explicit request captures updated scene bodies. Context freshness is therefore tied to request dispatch, not continuous revalidation of every on-screen text update; this prevents streaming replies and status counters from starving generation. The helper still validates the current editor, draft, target identity and geometry before Tab insertion.

## Shortcut and typing authority

Option + Tab, Option + Up/Down, and Option + 1–9 are reserved for fixed Autocomplete Everywhere actions. Configurable request, accept and dismiss bindings cannot use them; adding another modifier remains possible. Desktop preferences, the helper protocol and both native executables enforce the reservation. A conflicting saved shortcut requires an explicit user choice to reset shortcuts; other preferences are preserved.

A printable edit from a known keyboard layout may establish an edit opportunity even when its non-ASCII text cannot predict the ghost. Subsequent Accessibility capture must still verify the actual change. IME/unknown sources and Option dead keys remain conservative; this is not proof of real-layout composition behavior.

## Usage upload lifecycle

Content-free usage uploads retain at most 200 pending events and one active batch of at most 20. Oldest pending events are dropped when full. A ten-second deadline covers token acquisition, HTTP and response cleanup. Account invalidation and disposal clear pending events and abort the active upload; old work cannot obtain a replacement account's credentials. Events already received by the server under the original account cannot be recalled. Quitting drops pending usage events.
