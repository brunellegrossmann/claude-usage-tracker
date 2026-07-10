import AppKit
import ClaudeCodeUsageKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = makeAppDelegate()
app.delegate = delegate
app.run()
