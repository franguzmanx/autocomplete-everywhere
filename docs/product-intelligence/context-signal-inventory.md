# Context signal inventory

**Current contract — 2026-09-04**

The model receives evidence. No local language/intent classifier or application allowlist decides what that evidence means.

| Signal | Meaning | Lifetime and boundary |
|---|---|---|
| Secure-field capability | Processing must stop | Checked before content reads |
| Text before/selected/after cursor | Current writing and insertion boundary | Bounded request snapshot |
| Physical field shape | Whether line breaks are supported | Current field |
| Associated label/placeholder | Evidence about destination purpose | Bounded; never authored content |
| Read-only visible fragments | Message text, author labels and other structural evidence; never automatically a reply target | Up to 24 fragments, 2,000 UTF-16 units each and 12,000 total; current window/document boundaries |
| Nearby editable fields | Potentially related source text | Up to three, read through generic AX relationships |
| Recent selection | Explicitly highlighted material | One artifact, 60 seconds |
| Clipboard | Current selected/copied source | Opt-in, version-bound, ten-minute maximum |
| Recent writing | Observed user edits in a non-secure field | RAM only, five minutes, up to three fragments / 4,000 UTF-16 units total |
| Accepted completion | Verified inserted text | Same recent window; never a merely visible ghost |
| Source surface and timestamp | Generic observed provenance and recency | Does not assert recipient, organization or truth |
| Manual personal/company context | User-provided background | Existing authenticated context store |

## Acquisition and retention

Observing a key is not enough to retain it. The keyboard path signals editing without storing its characters in the context system; Accessibility must expose a corresponding change in the same field. Focus changes and secure or unsupported fields break attribution. A transient AX read failure preserves the safe baseline for less than one second; recovery still requires the same field and a recent edit signal. Longer failures break attribution. Programmatic replacements without observed user editing are not stored as authored text.

Typing, deletion, cut/paste and undo can alter the current authored fragment. Its latest observed version replaces the old version; an erased fragment disappears. Bounded capture may omit material outside the active window. It must never fabricate the missing text.

When returning to a source field, restore authorship only if the retained fragment still matches its original document range in the new capture. This keeps a corrected date together with its sentence after an application switch. If the fragment changed while unobserved or cannot be validated, discard its stale entry. Reopening a field does not renew the five-minute lifetime. Only the bounded fragment and range are retained, not a second copy of the source document.

## Missing evidence

The present layer does not read complete Slack/Gmail histories, passive reading, screenshots or application databases. It does not reliably identify every destination's recipient, account or organization. A generic AX route cannot infer facts an application does not expose.

Selected/copied material or future explicit integrations can supply additional evidence, but those integrations are outside this layer. Do not promise cross-recipient isolation based only on model relevance or surface names.

## Request construction

Keep current draft, neighboring fields, manual background and artifacts distinguishable. Include request time alongside artifact timestamps. Deduplicate artifacts without changing their exact content. The model chooses relevance within the bounded window; unrelated recent content must not influence the new task.

## September 8: fragmented conversation capture

The source-count ceiling is 24 rather than six, while the total text ceiling remains 12,000 UTF-16 units. The cooperative source scan budget is 120 ms rather than 50 ms. The existing node, ancestry, window, hidden-field and secure-field boundaries remain. This is a synchronous bounded scan with short-lived topology reuse, not a new background history index. Source text is reread rather than treated as fresh from the topology cache.

Fragments retain source and container identities. Their array order reflects structural proximity, not chronology; the model is instructed to reconstruct turns only from available content and relationships. This does not certify reliable authorship or complete chat history on every app. Screenshots/OCR and retention of previously visible read-only turns remain unimplemented.
