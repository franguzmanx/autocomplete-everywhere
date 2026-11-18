import AppKit

// App-local hover timing; keep AppKit's standard tooltip rendering.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 350])

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
