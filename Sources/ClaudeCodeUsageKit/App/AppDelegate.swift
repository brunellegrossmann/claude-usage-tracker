import AppKit
import ServiceManagement
import SwiftUI

// MARK: - App delegate (the view: status item + popover, backed by AppCoordinator)

/// Public entry point for the executable target. A factory (not a public
/// class) so `AppDelegate` and its delegate methods stay internal: a public
/// `NSApplicationDelegate` would force every @objc protocol method to be public.
public func makeAppDelegate() -> any NSApplicationDelegate { AppDelegate() }

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let coordinator = AppCoordinator()
    private let model = UsageModel()
    private let popover = NSPopover()
    private lazy var settingsWindow = SettingsWindowController(onChange: { [weak self] in self?.coordinator.refresh() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Claude $…"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        model.onRefresh = { [weak self] in self?.coordinator.refresh() }
        model.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        coordinator.onSnapshot = { [weak self] snapshot in self?.render(snapshot) }

        popover.behavior = .transient
        let host = NSHostingController(rootView: UsageView(model: model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        enableLaunchAtLoginOnFirstRun()
        coordinator.start()
    }

    /// Register as a login item once, so the app launches at every login by
    /// default. A later manual toggle is respected (we only auto-enable once).
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didAutoEnableLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            coordinator.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func render(_ snapshot: Snapshot) {
        model.snapshot = snapshot
        let tier = Tiers.current(forSpend: snapshot.todayCost, in: Config.activeTierTheme)
        let prefix = tier.icon.isEmpty ? "" : "\(tier.icon) "
        statusItem.button?.title = "\(prefix)\(formatMoney(snapshot.todayCost))"
        statusItem.button?.toolTip = "Claude Code spend today — \(tier.name) tier · \(Config.planTier.displayName) plan"
    }
}
