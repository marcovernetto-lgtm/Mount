import AppKit
import ServiceManagement
import SwiftUI

@main
struct MountApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let diskManager = DiskManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = item

        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: "Mount")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarView(manager: diskManager))
        self.popover = popover

        if SMAppService.mainApp.status == .notRegistered {
            try? SMAppService.mainApp.register()
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            diskManager.refreshAll()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
