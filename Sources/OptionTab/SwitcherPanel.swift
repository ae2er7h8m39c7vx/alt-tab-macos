import AppKit

/// The heads-up overlay listing candidate windows.
///
/// A non-activating panel: it must never take key focus, because taking focus
/// would itself change the window order we are trying to let the user navigate.
final class SwitcherPanel {

    var onPick: ((Int) -> Void)?

    private enum Metrics {
        static let cellWidth: CGFloat = 118
        static let cellHeight: CGFloat = 126
        static let iconSize: CGFloat = 64
        static let spacing: CGFloat = 6
        static let padding: CGFloat = 16
        static let cornerRadius: CGFloat = 16
        static let cellCornerRadius: CGFloat = 10
        static let borderWidth: CGFloat = 1
    }

    private let panel: NSPanel
    private let stack = NSStackView()
    private let scrollView = NSScrollView()
    private var cells: [CellView] = []

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // A clear, non-opaque panel is what lets the blur's rounded corners show;
        // an opaque one would draw square edges behind them.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let effect = GlassView()
        // `.behindWindow` is what makes the blur sample the desktop rather than
        // the panel's own contents, and `.active` keeps it alive even though this
        // panel never becomes key -- the default `.followsWindowActiveState`
        // renders flat and grey for a switcher that is never focused.
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Metrics.cornerRadius
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = Metrics.borderWidth
        effect.updateRim()

        stack.orientation = .horizontal
        stack.spacing = Metrics.spacing
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = stack
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: Metrics.padding),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -Metrics.padding),
            scrollView.topAnchor.constraint(equalTo: effect.topAnchor, constant: Metrics.padding),
            scrollView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -Metrics.padding),
            stack.heightAnchor.constraint(equalToConstant: Metrics.cellHeight),

            // An NSStackView used as a document view needs pinning to the clip view;
            // its intrinsic width is what makes the content scrollable.
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])

        panel.contentView = effect
    }

    func show(entries: [WindowEntry], selected: Int) {
        cells.forEach { $0.removeFromSuperview() }
        cells = entries.enumerated().map { index, entry in
            let cell = CellView(entry: entry, size: NSSize(width: Metrics.cellWidth, height: Metrics.cellHeight),
                                iconSize: Metrics.iconSize, cornerRadius: Metrics.cellCornerRadius)
            cell.onClick = { [weak self] in self?.onPick?(index) }
            stack.addArrangedSubview(cell)
            return cell
        }

        let screen = currentScreen()
        let count = CGFloat(entries.count)
        let contentWidth = count * Metrics.cellWidth + max(0, count - 1) * Metrics.spacing
        let maxWidth = screen.visibleFrame.width - 120
        let width = min(contentWidth, maxWidth) + Metrics.padding * 2
        let height = Metrics.cellHeight + Metrics.padding * 2

        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.midY - height / 2,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        select(selected)
        panel.orderFrontRegardless()
    }

    func select(_ index: Int) {
        for (i, cell) in cells.enumerated() {
            cell.isSelected = (i == index)
        }
        guard cells.indices.contains(index) else { return }
        cells[index].scrollToVisible(cells[index].bounds.insetBy(dx: -Metrics.spacing, dy: 0))
    }

    func hide() {
        panel.orderOut(nil)
        cells.forEach { $0.removeFromSuperview() }
        cells = []
    }

    /// The screen under the pointer, so the overlay appears where the user is looking.
    private func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

// MARK: - Background

/// The frosted slab behind the tiles.
///
/// Subclassed for the hairline rim. `rimColor` resolves differently per
/// appearance, and `CGColor` has no such notion -- it is whatever the appearance
/// was when `.cgColor` was read -- so the layer's border has to be re-resolved
/// each time the system flips between light and dark.
private final class GlassView: NSVisualEffectView {

    /// The rim is what separates the blur from the desktop; without it the panel's
    /// edge dissolves into whatever is behind it. A light lift works over the dark
    /// HUD material, but on a light desktop only a darker line is visible.
    static let rimColor = NSColor(name: "switcherRim") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor.white.withAlphaComponent(0.18)
                      : NSColor.black.withAlphaComponent(0.12)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateRim()
    }

    func updateRim() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = Self.rimColor.cgColor
        }
    }
}

// MARK: - Cell

private final class CellView: NSView {

    var onClick: (() -> Void)?

    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    private let cornerRadius: CGFloat

    init(entry: WindowEntry, size: NSSize, iconSize: CGFloat, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: NSRect(origin: .zero, size: size))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height),
        ])

        let icon = NSImageView()
        icon.image = entry.appIcon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.alphaValue = entry.isMinimized ? 0.5 : 1.0
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = Self.label(entry.title, size: 11, color: .labelColor)
        let subtitle = Self.label(entry.appName, size: 10, color: .secondaryLabelColor)

        addSubview(icon)
        addSubview(title)
        addSubview(subtitle)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),

            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),

            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        // Translucent, so the frosted slab still reads through the highlight; an
        // opaque fill would sit on the glass as a card rather than tint it.
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.55).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    private static func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.alignment = .center
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}
