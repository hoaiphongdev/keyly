import Cocoa

// MARK: - Keycaps

/// Splits a shortcut string into chords of keycaps and draws them.
/// "⇧⌘P" → [["⇧", "⌘", "P"]], "⌘K⌘S" → [["⌘", "K"], ["⌘", "S"]], "⌘1-9" → [["⌘", "1-9"]]
enum Keycaps {
    typealias Chords = [[String]]

    private static let font = NSFont.systemFont(ofSize: WindowConstants.FontSizes.keycap, weight: .medium)
    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: WindowConstants.Colors.keycapTextColor
    ]

    static func tokenize(_ shortcut: String) -> Chords {
        var chords: Chords = []
        var current: [String] = []
        var key = ""

        func closeChord() {
            // "⌥+click" → ⌥ click, but a lone "+" is a real key (⌘+)
            if key.count > 1 && key.hasPrefix("+") && !current.isEmpty {
                key.removeFirst()
            }
            if !key.isEmpty {
                current.append(key)
                key = ""
            }
            if !current.isEmpty {
                chords.append(current)
                current = []
            }
        }

        for character in shortcut {
            if character == " " {
                closeChord()
            } else if Modifier.allCharacters.contains(character) {
                // A modifier after a key starts the next chord (e.g. ⌘K⌘S)
                if !key.isEmpty { closeChord() }
                current.append(String(character))
            } else {
                key.append(character)
            }
        }
        closeChord()

        return chords
    }

    static func capWidth(_ label: String) -> CGFloat {
        let textWidth = ceil((label as NSString).size(withAttributes: textAttributes).width)
        return max(WindowConstants.Keycap.minWidth, textWidth + WindowConstants.Keycap.horizontalPadding * 2)
    }

    static func width(of chords: Chords) -> CGFloat {
        var total: CGFloat = 0
        for (chordIndex, chord) in chords.enumerated() {
            if chordIndex > 0 { total += WindowConstants.Keycap.chordSpacing }
            for (capIndex, cap) in chord.enumerated() {
                if capIndex > 0 { total += WindowConstants.Keycap.spacing }
                total += capWidth(cap)
            }
        }
        return total
    }

    /// Draws chords left-to-right starting at `origin.x`, vertically centred on `midY`.
    static func draw(_ chords: Chords, originX: CGFloat, midY: CGFloat) {
        let height = WindowConstants.Keycap.height
        let radius = WindowConstants.Keycap.cornerRadius
        var x = originX

        for (chordIndex, chord) in chords.enumerated() {
            if chordIndex > 0 { x += WindowConstants.Keycap.chordSpacing }
            for (capIndex, cap) in chord.enumerated() {
                if capIndex > 0 { x += WindowConstants.Keycap.spacing }

                let width = capWidth(cap)
                let rect = NSRect(x: x, y: midY - height / 2, width: width, height: height)
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
                WindowConstants.Colors.keycapFillColor.setFill()
                path.fill()
                WindowConstants.Colors.keycapBorderColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()

                let textSize = (cap as NSString).size(withAttributes: textAttributes)
                let textOrigin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2)
                (cap as NSString).draw(at: textOrigin, withAttributes: textAttributes)

                x += width
            }
        }
    }
}

/// Static keycaps, used in the footer hints.
final class KeycapView: NSView {
    private let chords: Keycaps.Chords

    init(_ shortcut: String) {
        chords = Keycaps.tokenize(shortcut)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Keycaps.width(of: chords), height: WindowConstants.Keycap.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Keycaps.draw(chords, originX: 0, midY: bounds.midY)
    }
}

// MARK: - Row model

/// Everything a row needs that does not change while searching, computed once per popup.
struct ShortcutRowModel {
    let item: ShortcutItem
    let chords: Keycaps.Chords
    let keysWidth: CGFloat
    let actionWidth: CGFloat
    /// Lowercased text the search query is matched against
    let searchText: String

    static let actionFont = NSFont.systemFont(ofSize: WindowConstants.FontSizes.action)

    init(item: ShortcutItem, categoryDescription: String?, groupDescription: String?) {
        self.item = item
        chords = Keycaps.tokenize(item.shortcut)
        keysWidth = Keycaps.width(of: chords)
        actionWidth = ceil((item.action as NSString).size(withAttributes: [.font: Self.actionFont]).width)
        searchText = [item.action, item.category, item.group, categoryDescription, groupDescription, item.shortcut]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
    }

    /// Width a row needs to show the action without truncation
    var requiredWidth: CGFloat {
        actionWidth + WindowConstants.Row.actionToKeysGap + keysWidth + WindowConstants.Row.horizontalPadding * 2
    }
}

// MARK: - Row view

/// One shortcut row drawn in a single pass: no subviews, no Auto Layout, no text views.
final class ShortcutRowView: NSView {
    let model: ShortcutRowModel
    private var highlightRange: NSRange?
    private var hoverTrackingArea: NSTrackingArea?

    init(model: ShortcutRowModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = WindowConstants.Row.cornerRadius
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        toolTip = "\(model.item.action)  \(model.item.shortcut)"

        // Drawn rows have no text subviews, so describe them for VoiceOver
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(model.item.action), \(model.item.shortcut)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// Highlights the part of the action that matches `query` (already lowercased); nil clears it.
    func setHighlight(_ query: String?) {
        var range: NSRange?
        if let query = query {
            let found = (model.item.action as NSString).range(of: query, options: .caseInsensitive)
            if found.location != NSNotFound { range = found }
        }
        guard range != highlightRange else { return }
        highlightRange = range
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func viewDidHide() {
        super.viewDidHide()
        setHovered(false, animated: false)
    }

    private func setHovered(_ hovered: Bool, animated: Bool = true) {
        guard let layer = layer else { return }
        let color = hovered ? WindowConstants.Colors.rowHoverColor.cgColor : NSColor.clear.cgColor
        if animated {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            fade.duration = 0.12
            layer.add(fade, forKey: "hover")
        }
        layer.backgroundColor = color
    }

    override func draw(_ dirtyRect: NSRect) {
        let padding = WindowConstants.Row.horizontalPadding
        let keysX = bounds.maxX - padding - model.keysWidth
        Keycaps.draw(model.chords, originX: keysX, midY: bounds.midY)

        let actionMaxX = keysX - WindowConstants.Row.actionToKeysGap
        guard actionMaxX > padding else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let action = NSMutableAttributedString(string: model.item.action, attributes: [
            .font: ShortcutRowModel.actionFont,
            .foregroundColor: WindowConstants.Colors.actionTextColor,
            .paragraphStyle: paragraph
        ])
        if let range = highlightRange {
            action.addAttributes([
                .font: NSFont.systemFont(ofSize: WindowConstants.FontSizes.action, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor
            ], range: range)
        }

        let lineHeight = ceil(ShortcutRowModel.actionFont.ascender - ShortcutRowModel.actionFont.descender)
        let actionRect = NSRect(x: padding, y: bounds.midY - lineHeight / 2, width: actionMaxX - padding, height: lineHeight)
        action.draw(with: actionRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
