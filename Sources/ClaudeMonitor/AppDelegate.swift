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
    private var farmWindow: NSWindow?
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
        popover.contentViewController = NSHostingController(
            rootView: DropdownView(
                viewModel: viewModel,
                settings: viewModel.settings,
                onOpenFarm: { [weak self] in self?.showFarmWindow() }
            )
        )
    }

    /// Shows the farm window, reusing the existing one if it's already open.
    ///
    /// Hand-rolled rather than a SwiftUI `WindowGroup` + `openWindow`: `WindowGroup` is
    /// multi-instance (every click spawned another window), auto-opens an unwanted window
    /// at launch, and `openWindow` doesn't activate an `LSUIElement` app — so the window
    /// appeared behind the frontmost app and the click looked like it did nothing.
    /// Owning the `NSWindow` here makes single-instance and bring-to-front explicit, and
    /// matches how this class already owns the status item and popover.
    private func showFarmWindow() {
        popover.performClose(nil)

        if farmWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Farm"
            window.contentViewController = NSHostingController(rootView: FarmView(viewModel: viewModel))
            window.center()
            window.setFrameAutosaveName("FarmWindow")
            // Without this the window is deallocated on close and `farmWindow` is left
            // dangling; we manage its lifetime ourselves via `windowWillClose`.
            window.isReleasedWhenClosed = false
            window.delegate = self
            farmWindow = window
        }

        farmWindow?.makeKeyAndOrderFront(nil)
        // An accessory app isn't activated by ordering a window front, so without this
        // the window opens behind whatever the user is currently looking at.
        NSApp.activate(ignoringOtherApps: true)
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

extension AppDelegate: NSWindowDelegate {
    /// `isReleasedWhenClosed` is off so the window survives being closed; drop our
    /// reference here so the next "Open Farm" builds a fresh one rather than
    /// re-showing a window the user already dismissed.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === farmWindow {
            farmWindow = nil
        }
    }
}
