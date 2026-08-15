import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and its dropdown directly via AppKit, rather than SwiftUI's
/// `MenuBarExtra`. `MenuBarExtra` (particularly `.menuBarExtraStyle(.window)`) is known to
/// lose the status item across Space switches and render detached from the menu bar during
/// Mission Control's redraw of all status items — a plain `NSStatusItem` doesn't have that
/// problem, since it's the same mechanism every other menu bar item (Wi-Fi, Control Center,
/// third-party apps) relies on.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let viewModel = MonitorViewModel()
    private var usageResultSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.startPolling()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Claude Monitor")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }
        updateStatusItemTitle()

        usageResultSubscription = viewModel.$usageResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItemTitle() }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: DropdownView(viewModel: viewModel, overloadSettings: viewModel.overloadSettings))

        // WindowGroup(id: "farm") auto-opens a window at launch by default — there's
        // no launch-suppression API for WindowGroup pre-macOS 15. This app is a
        // menu-bar-only utility (LSUIElement, no Dock icon); the farm window must
        // only appear when the user explicitly opens it via "Open Farm 🌾". Close
        // whatever SwiftUI auto-opened, right after launch, before the user can see
        // it — filtered to windows whose identifier starts with "farm" specifically,
        // since closing ALL windows here would also hide the status bar item.
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.identifier?.rawValue.hasPrefix("farm") == true }
                .forEach { $0.close() }
        }
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        if case .active(let block) = viewModel.usageResult {
            button.title = " \(block.pct)%"
        } else {
            button.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
