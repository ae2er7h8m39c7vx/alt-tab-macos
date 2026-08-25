import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let switcher = Switcher()
    private let tap = HotKeyTap()
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        tap.isSessionActive = { [weak switcher] in switcher?.isActive ?? false }
        tap.onCycle = { [weak switcher] backwards in switcher?.cycle(backwards: backwards) }
        tap.onCommit = { [weak switcher] in switcher?.commit() }
        tap.onCancel = { [weak switcher] in switcher?.cancel() }

        startWhenTrusted()
    }

    /// Both the event tap and the window list require Accessibility. Prompt once,
    /// then wait for the user to flip the switch in System Settings — the grant
    /// does not restart us or fire a notification, so we poll.
    private func startWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if AXIsProcessTrustedWithOptions(options as CFDictionary) {
            startTap()
            return
        }
        statusItem?.button?.appearsDisabled = true
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.statusItem?.button?.appearsDisabled = false
            self?.startTap()
        }
    }

    private func startTap() {
        guard tap.start() else {
            let alert = NSAlert()
            alert.messageText = "Could not listen for ⌥Tab"
            alert.informativeText = """
                OptionTab needs Accessibility access to capture the keyboard shortcut.

                Open System Settings ▸ Privacy & Security ▸ Accessibility, enable \
                OptionTab, then launch it again.
                """
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                     accessibilityDescription: "OptionTab")

        let menu = NSMenu()
        let header = NSMenuItem(title: "⌥Tab switches windows", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OptionTab",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
