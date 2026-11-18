# Autocomplete Everywhere product thesis: useful writing from current intent

**Current product direction — 2026-09-04**

This document describes the bounded current layer. The [complete product proposal](invisible-intelligence-product-design.md) expands the vision to current-task perception, durable knowledge and memory, user voice, timing and the full product experience. Those capabilities are proposed, not already implemented.

Autocomplete Everywhere should save the effort of remembering, composing and transferring an idea while the user writes in an ordinary Mac field. It should offer the amount of text that advances the evident task: sometimes a few words, sometimes a list, email or complete block. The user accepts with Tab or a direct ghost click, keeps typing, or dismisses. Nothing sends or submits automatically.

## One global route

Accessibility supplies bounded field text and observable context through one capability-based path. Application names are provenance and acceptance surfaces, never routing rules, allowlists or semantic classifiers. An unsupported control stays silent when its actual capabilities cannot support safe capture, geometry or insertion.

Gemini 3.5 Flash-Lite through Vercel AI Gateway interprets the writing task, relevant evidence, language, tone, structure and useful length. There is no local intent/language classifier, model cascade, provider race or fallback. Astra is the development agent, not the autocomplete engine.

The helper owns secure-field exclusion, current focus, stale-state rejection, geometry and exactly-once insertion. Model intelligence cannot replace those guarantees.

## What the model can know

A request can carry text before and after the cursor, selection, field shape, useful label/placeholder, nearby editable fields, selected/copied artifacts, manual background and bounded recent writing. A recent fragment is evidence of what the user wrote or accepted, not evidence that it was sent, approved or objectively true.

Recent writing is captured from changes observed in a focused non-secure editable after user editing activity, plus verified accepted insertions. Focusing a preexisting document does not make its whole contents authored history. Rejected ghosts are never memory. Corrections replace the retained version; deleted writing is removed. No application conversation history or passive read-only screen history is collected by this layer.

A message the user only read in Slack may therefore be unavailable. The product must not promise to know an unseen source. Selected/copied material and future explicitly authorized integrations are separate ways to supply evidence.

## Context operations

- Continue or generate when the task calls for new writing.
- Derive a subject or title from actual source content.
- Adapt when the destination and audience support the transformation.
- Transport an exact selected artifact when that is the intended operation.

These are decisions for the same model, not separate classifiers or code paths per application. Exact artifact references preserve original bytes. The current field and explicit task take priority over incidental recent context; unrelated context should be ignored.

## Product boundaries

- Secure fields fail before content capture and request construction.
- Context has an explicit resource budget, provenance and expiry; no durable draft journal or content telemetry.
- Recency does not establish a recipient, account, authority or permission. Unknown boundaries remain unknown.
- One complete validated response produces one ghost. No streaming, growing partial text or replacement UI.
- A multiline field permits multiline output even after writing has started. Physical single-line controls remain single-line.
- The model may remain silent when evidence cannot support useful writing.
- A shown completion is not an acceptance; acceptance is not sending; a passed test is not product proof.

## Acceptance

The first cross-field proof uses an authored fact that cannot be guessed: write a delivery detail in Notes, start a related message elsewhere, and observe a faithful useful continuation. Then change the topic and verify that the same detail is ignored. Correct the source and verify that the old version does not return. Expire or disable memory and verify that it disappears.

Measure relevance, factual fidelity, useful extent, valid-ghost latency and real insertion separately. Keep CJK, RTL, empty fields, secure fields, Tab and click in the native acceptance matrix. This vision does not claim those outcomes have already been observed for the current package.
