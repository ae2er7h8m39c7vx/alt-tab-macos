import AppKit
import ApplicationServices

/// Private CoreGraphics/AX bridge: maps an AXUIElement window to its CGWindowID.
/// This is the only way to correlate the Accessibility window tree (which gives us
/// titles and lets us raise windows) with the CGWindowList (which gives us the
/// system's true front-to-back z-order across every application).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowEntry {
    let axWindow: AXUIElement
    let pid: pid_t
    let title: String
    let appName: String
    let appIcon: NSImage?
    let isMinimized: Bool
}

enum WindowLister {

    /// Every switchable window, ordered most-recently-used first.
    ///
    /// macOS keeps no MRU list we can read, but the on-screen z-order is a faithful
    /// stand-in: the window you used last is the one in front. Minimized and
    /// off-screen windows have no z-order, so they land at the end.
    static func list() -> [WindowEntry] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var byID: [CGWindowID: WindowEntry] = [:]
        var unordered: [WindowEntry] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  !app.isTerminated,
                  app.processIdentifier != ownPID else { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = copyValue(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            let appName = app.localizedName ?? "Unknown"
            let icon = app.icon

            for window in windows {
                guard isStandardWindow(window) else { continue }

                let title = (copyValue(window, kAXTitleAttribute) as? String) ?? ""
                let minimized = (copyValue(window, kAXMinimizedAttribute) as? Bool) ?? false
                let entry = WindowEntry(
                    axWindow: window,
                    pid: app.processIdentifier,
                    title: title.isEmpty ? appName : title,
                    appName: appName,
                    appIcon: icon,
                    isMinimized: minimized
                )

                var windowID = CGWindowID(0)
                if !minimized, _AXUIElementGetWindow(window, &windowID) == .success {
                    byID[windowID] = entry
                } else {
                    unordered.append(entry)
                }
            }
        }

        var ordered: [WindowEntry] = []
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for info in infos {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let id = info[kCGWindowNumber as String] as? CGWindowID,
                      let entry = byID.removeValue(forKey: id) else { continue }
                ordered.append(entry)
            }
        }

        // Anything the z-order pass did not claim: on-screen windows we could not map,
        // then minimized ones. Stable-sorted by app so the tail is not arbitrary.
        let leftovers = (Array(byID.values) + unordered)
            .sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
        ordered.append(contentsOf: leftovers)

        return ordered
    }

    /// Bring a window forward and give it keyboard focus.
    static func focus(_ entry: WindowEntry) {
        if entry.isMinimized {
            AXUIElementSetAttributeValue(entry.axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(entry.axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(entry.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(entry.axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        // Raising alone does not move keyboard focus across applications; we are a
        // background agent, so activation has to ignore the current front app.
        NSRunningApplication(processIdentifier: entry.pid)?
            .activate(options: [.activateIgnoringOtherApps])
    }

    // MARK: - Helpers

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    /// Filters out sheets, popovers, palettes and other non-switchable AX windows.
    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        guard let subrole = copyValue(window, kAXSubroleAttribute) as? String else {
            // Some apps omit the subrole; fall back to the role.
            return (copyValue(window, kAXRoleAttribute) as? String) == kAXWindowRole
        }
        return subrole == kAXStandardWindowSubrole
    }
}
