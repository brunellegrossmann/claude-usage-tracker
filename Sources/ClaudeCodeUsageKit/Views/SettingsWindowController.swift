import AppKit
import SwiftUI

// MARK: - Settings window controller

/// Hosts `SettingsView` in its own window, created once and reused across
/// opens (so the window's edit state — and macOS's remembered position —
/// survive close/reopen).
final class SettingsWindowController {
    private var window: NSWindow?
    private let onChange: () -> Void
    private let pricingFeed: PricingFeed

    init(onChange: @escaping () -> Void, pricingFeed: PricingFeed) {
        self.onChange = onChange
        self.pricingFeed = pricingFeed
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsView(onChange: onChange, pricingFeed: pricingFeed))
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
