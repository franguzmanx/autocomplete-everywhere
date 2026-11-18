# Autocomplete Everywhere Scene Lab

Run `./build.sh` to build the standalone AppKit fixture into `build/Autocomplete Everywhere Scene Lab.app` (ad-hoc signed, bundle `com.autocompletion.SceneLab`). Launch the built app normally. The app contains only visible source labels, an editable reply draft and two scenario buttons; it does not call Autocomplete Everywhere, generate suggestions or send messages.

Use Autocomplete Everywhere's actual packaged application to test the full pipeline. Type a partial reply, observe a ghost, then click **Change source** or **Other thread**. Both preserve the draft and restore composer focus. Verify that any new suggestion uses the currently visible source and that a stale ghost cannot be accepted. The source sits inside a nested sibling group, rather than being an editable field or a direct composer label.

Fixture build success alone does not prove Accessibility exposure or packaged generation behavior. Record actual app observations separately.
