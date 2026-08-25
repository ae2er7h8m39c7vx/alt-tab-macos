import AppKit

/// Owns one switching session: the snapshot of windows, the cursor into it,
/// and the overlay showing both.
final class Switcher {

    private(set) var isActive = false

    private var entries: [WindowEntry] = []
    private var index = 0
    private let panel = SwitcherPanel()

    init() {
        panel.onPick = { [weak self] picked in
            guard let self, self.isActive else { return }
            self.index = picked
            self.commit()
        }
    }

    /// ⌥Tab pressed. Opens a session on the first press, moves the cursor after that.
    func cycle(backwards: Bool) {
        guard isActive else {
            begin(backwards: backwards)
            return
        }
        let count = entries.count
        index = ((index + (backwards ? -1 : 1)) % count + count) % count
        panel.select(index)
    }

    /// ⌥ released. Focus whatever is under the cursor.
    func commit() {
        guard isActive else { return }
        let entry = entries[index]
        end()
        WindowLister.focus(entry)
    }

    /// Escape. Leave the window order untouched.
    func cancel() {
        guard isActive else { return }
        end()
    }

    // MARK: -

    private func begin(backwards: Bool) {
        // Snapshot once, at the start: the list must not shuffle underneath the
        // user while they are tabbing through it.
        entries = WindowLister.list()

        switch entries.count {
        case 0:
            return
        case 1:
            // Nothing to choose between, but honour the intent to focus a window.
            WindowLister.focus(entries[0])
            entries = []
            return
        default:
            break
        }

        // A single ⌥Tab tap should land on the previous window, the way ⌘Tab does.
        index = backwards ? entries.count - 1 : 1
        isActive = true
        panel.show(entries: entries, selected: index)
    }

    private func end() {
        isActive = false
        panel.hide()
        entries = []
        index = 0
    }
}
