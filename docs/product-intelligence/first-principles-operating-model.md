# First-principles operating model

**Current contract — 2026-09-04**

The objective is useful work saved after interruption, errors, latency and cost. Generated volume and raw acceptance alone are insufficient measures.

## Responsibilities

1. **Capture:** Accessibility reads only eligible focused fields and bounded related editable context. Secure fields fail closed before reads.
2. **Attribute recent writing:** a content-free editing signal plus an observed field change can establish a recent edit. Verified insertion establishes accepted text. Focus alone establishes neither.
3. **Store:** a RAM-only rolling window limits age, fragment size, aggregate size and duplicates. Revising or deleting observed writing updates its source. Disable/sign-out clears the store through effective configuration.
4. **Assemble:** include current field evidence and a bounded set of artifacts with real provenance and timestamps. Exclude the current field's own recent fragment to avoid repeating its draft as background.
5. **Understand:** one Qwen/Cerebras call decides relevance, intended writing, language, tone and length. No local semantic classifier or model fallback.
6. **Present and accept:** wait for the complete response; corroborate current identity and geometry; show one inline ghost or silence; insert once only after acceptance and verify.

## Visible candidate — September 6 revision

A complete model response and an offered insertion are distinct. Before its first display, the native helper may select an exact prefix ending at a native word/token boundary when the complete response exceeds the measured vertical viewport. TextKit measures the original line fragments, then lays out and validates the selected prefix again with the same font. Links, email addresses and exact artifact occurrences are indivisible. Horizontal, top-edge, unknown-geometry and focus failures still reject presentation.

The session replaces its insertion text with the visible candidate before enabling acceptance. The unoffered suffix is discarded, never accepted, revived by resizing, or used for type-through. After first display, geometry changes can hide and reanchor the same candidate; they cannot select a different prefix. A fully fitting response is unchanged. This remains one final foreground generation and final-only display.

This replaces the earlier all-or-nothing display assumption following the user's approval. Generation currently retains its existing resource budget; no token or latency saving is claimed. Sending measured capacity before generation is a separate controlled optimization, not a prerequisite for deterministic native fitting.

## Limits serve resources, not meaning

A real single-line field cannot receive paragraphs. A multiline field may receive a short continuation or a full block, including after the user starts the draft. Character/token limits are ceilings, not targets and not predictions of how much the user wants.

Debounce, cancellation, TTL and field identity are deterministic mechanics. They do not require a classifier of the user's objective. Context cannot override secure-field or insertion safety.

## Recent window

The current implementation uses up to three recent fragments, up to 2,000 UTF-16 units each, at most 4,000 in aggregate, expiring after five minutes. Selection remains a separate 60-second artifact; clipboard remains the current opt-in version with a ten-minute ceiling. The combined request admits up to five artifacts and 12,000 UTF-16 units of artifact content.

Those values are resource bounds for this layer, not universal cognitive constants. Tune only when an observed useful journey or measured latency justifies it. Do not add episode ontologies, transition-learning systems, multiple providers or connectors to compensate for an unfinished current path.

## Proof

Use paired scenarios: relevant source / irrelevant source; original / corrected source; shown / accepted output; fresh / expired context. Record generation failure separately from intentional silence, and source tests separately from packaged observation. The current generator still needs a clearer failure-versus-silence result contract; do not infer model judgment from an absent ghost alone.
