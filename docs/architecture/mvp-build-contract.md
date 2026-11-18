# Autocomplete Everywhere Mac MVP — Build Contract

**Status:** Ready for implementation
**Date:** 2026-08-29
**Architecture:** [architecture-v2.md](./architecture-v2.md)

## TL;DR

The first downloadable product completes text and AI prompts in Notes, Slack, and one Chromium browser surface on macOS. The user grants permissions, signs in, adds a short personal or company profile, starts writing, sees grounded ghost text, and accepts it with Tab.

The MVP is successful only when that journey works in the real applications. A backend demo, fake input field, or overlay prototype is not the product.

## User journey

1. The user opens the Mac app.
2. The app explains and requests Accessibility and Input Monitoring permissions.
3. The user signs in with Clerk.
4. The user adds optional personal context and company context as plain text.
5. The user enables autocomplete.
6. In Notes, Slack, or the selected browser prompt surface, the user starts writing.
7. After a natural pause, a useful continuation appears beside the cursor without moving focus.
8. Tab accepts the full suggestion. Escape dismisses it. Matching typing consumes the matching prefix. Incompatible typing or focus change cancels it.
9. Nothing sends, submits, publishes, or clicks automatically.

## What the first suggestions must do

The MVP must prove two audiences with the same interaction:

- **Human writing:** complete a message using the user's voice and grounded personal or company facts.
- **Agent input:** complete a prompt with missing objective, context, constraints, or expected output.

The initial frozen demos are:

1. Start a Slack reply to a prospect; receive a grounded sales continuation using the manual company profile.
2. Start a note or email-style update; receive a continuation in the user's current language and tone.
3. Start a prompt in a browser; receive the missing company or task context rather than generic prompt advice.
4. Change language mid-document; receive the continuation in the active language without translating the existing text.

## Included

- Electron account, permissions, settings, and manual-context UI.
- Swift/AppKit helper for focus, field text, caret geometry, keyboard events, overlay, insertion, and stale cancellation.
- One accessibility-capability path for eligible native and web text fields; Notes, Slack, and Chromium are acceptance surfaces, not app-specific adapters.
- Clerk desktop authentication with browser-based Authorization Code and PKCE.
- New Supabase project and checked-in schema, RLS, hybrid retrieval, and pgTAP access tests.
- SQLCipher device store for prepared context capsules.
- `google/gemini-embedding-2` retrieval implementation.
- One fixed `google/gemini-3.5-flash-lite` generation path through Vercel AI Gateway; offline comparisons cannot change production routing or client code.
- Content-free latency and interaction telemetry.
- English and Spanish evaluation plus structural tests for the initial twelve certified languages.
- Local `.dmg` or zipped `.app` artifact.

## Excluded

- Windows, iOS, and Android clients.
- Voice dictation or transcription.
- External Slack, Gmail, Notion, Drive, meeting, CRM, Figma, or repository connectors.
- Screenshot OCR.
- Automatic memory extraction from a person's activity stream.
- Supermemory as a production dependency.
- Billing, teams administration, public landing page, or domain work.
- Automatic sending, submitting, committing, or publishing.

## Quality gates

- Pause-to-visible-ghost p50 at or below 700 ms and p95 at or below 1,400 ms on the supported path.
- No stale ghost text after focus or content changes.
- Tab always reaches the host application when no valid suggestion is visible.
- No secure field reaches request construction.
- At least 99.5% verified insertion success in the supported application matrix.
- At least 25% acceptance after initial calibration, measured separately from the distraction rate.
- Zero personal-to-company, company-to-personal, cross-organization, or cross-recipient leakage in the frozen corpus.
- No field text, suggestion text, screenshots, clipboard contents, or retrieved documents in default telemetry.

## Downloadable proof levels

1. **Developer artifact:** local `.app`, `.dmg`, or zip produced without production credentials. Gatekeeper treatment depends on the local signing state.
2. **Signed test artifact:** Developer ID signed build after Apple credentials are supplied.
3. **Public artifact:** signed and notarized build with a verified update path.

Only the third level is suitable for unrestricted public download. The first level is enough for the founder's direct Mac test.

## External access required during execution

- New Clerk application identifiers and allowed callback URL.
- New Supabase project URL and publishable/server credentials.
- Vercel project with AI Gateway access through OIDC; non-Vercel environments can use the server-only `AI_GATEWAY_API_KEY`.
- Apple Developer ID and notarization credentials for public distribution.

The implementation begins locally before these credentials exist. Credentials configure finished boundaries; they do not change the architecture.
