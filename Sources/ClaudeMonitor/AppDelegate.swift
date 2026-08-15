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
