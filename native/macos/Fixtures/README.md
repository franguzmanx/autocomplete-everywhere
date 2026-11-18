# Native reply-context fixture

Build with `sh native/macos/Fixtures/build-reply-context-lab.sh`. It prints a fresh temporary app bundle. Open that app and bring it to the foreground before observing Autocomplete Everywhere.

The fixture contains a read-only `qa-source-message` and a separate editable `qa-reply-editor` inside one structural group. Investigation and Recipe replace the source while retaining the editor. No context hides the source. Scenario changes reset the draft to `si`; edit it after switching to exercise the normal authored-edit path. Nothing sends text, injects input events, captures another application, or talks to a server; the installed Autocomplete Everywhere must independently capture and process the field.

Validate source acquisition, correct user-voice continuation, visible text, and physical Tab acceptance separately. Count invented assistant turns or unsupported facts as failures even if the suggestion appears. The same editor identity across scenarios tests stale-source invalidation, but does not establish isolation across real application conversations.

Compilation and accessibility structure were verified on September 6. Installed Autocomplete Everywhere captured one separate source and generated text for Investigation; visible acceptance and response quality are still unverified for this fixture.

Read-only integration checks against this exact application are available with:

```sh
AUTOCOMPLETION_REPLY_CONTEXT_LAB=1 AUTOCOMPLETION_REPLY_CONTEXT_SCENARIO=recipe swift test --package-path native/macos --filter LiveReplyContextLabTests
```

Set the scenario in the fixture UI first; accepted values are `investigation`, `recipe`, `none`, and `history` (scroll to the middle of Long history first). The test uses the real SystemAccessibilityReader with the fixture's focused-application provider, without moving global focus or synthesizing input. All three scenarios passed. Each invocation creates a fresh reader, so these checks do not establish cache invalidation within a single long-lived reader or full foreground generation/acceptance.

## Long history and nested composer regression (September 6)

Long history adds 120 older messages before the current source. The reply editor is nested in eight additional structural groups. With the old traversal, the current source at child index 120 was never reached and the live test returned zero sources. Viewport hit candidates now enter the same bounded traversal before offscreen children; secure/editable/document boundaries and whole-value visibility checks still apply.

Investigation, Recipe, and middle-history checks passed on the expanded fixture. Middle-history checks exclude the offscreen latest message. This is native AX evidence, not proof of browser/Electron coverage.

For a single-reader transition check, start at Recipe with Long history enabled and scrolled to the bottom:

```sh
AUTOCOMPLETION_REPLY_CONTEXT_TRANSITIONS=1 swift test --package-path native/macos --filter LiveReplyContextLabTests/testLiveSourceChangesWithOneReader
```

Within 45 seconds, choose Investigation, then No context. The test polls one reader and one editor identity, verifies the replacement source excludes Recipe, and observes an empty result after hiding. It passed. Like the standalone check, initialization allows up to three reads: an earlier run returned no source on the first read. This does not prove first-attempt reliability or measure the exact invalidation latency. The next release gate remains cold-read acquisition and real foreground generation/acceptance.

## First-read timing follow-up

`AUTOCOMPLETION_REPLY_CONTEXT_COLD=1 swift test --package-path native/macos --filter LiveReplyContextLabTests/testColdSourceAcquisition` measures 20 fresh readers, one source call each, without retries. Start Investigation with Long history on and scroll at the bottom. Display initialization is measured separately, matching HelperRuntime.start.

Before per-capture structural reuse, the first call returned no source at the 50 ms deadline and the following 19 calls also reached the deadline. Structural reuse removed repeated role/parent/frame/hidden queries but did not alone solve process-first AppKit display initialization. A temporary timing probe attributed about 45 ms to display setup; the probe was removed. Runtime startup now prepares displays on the main thread before capture starts. The final live run found the source in all 20 first attempts (17–36 ms), with AppKit setup separately taking 70 ms. These are single-machine samples, not a product latency SLA. The single-reader change/hide test passed again with the cache. No source text is retained by the per-call structural cache.
