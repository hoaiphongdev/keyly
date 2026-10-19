import Cocoa

/// A block placed by the window's masonry grid. `arrange(width:)` lays out the visible
/// content with plain frames and returns the height; it hides itself and returns 0 when empty.
protocol MasonryBlock: NSView {
    var columnSpan: Int { get }
    func arrange(width: CGFloat) -> CGFloat
}

private func makeDescriptionLabel(_ text: String, color: NSColor) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = NSFont.systemFont(ofSize: WindowConstants.FontSizes.description)
    label.textColor = color
    label.isSelectable = false
    return label
}

private func wrappedHeight(of label: NSTextField, width: CGFloat) -> CGFloat {
    guard let cell = label.cell else { return 0 }
    return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height)
}

// MARK: - Category

/// A category title (small caps), optional description and its shortcut rows.
final class CategorySectionView: NSView, MasonryBlock {
    let rows: [ShortcutRowView]
    private let header: NSTextField
    private let descriptionLabel: NSTextField?

    private static let headerHeight: CGFloat = 16

    init(title: String, description: String?, rows: [ShortcutRowView]) {
        self.rows = rows

        header = NSTextField(labelWithAttributedString: NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: WindowConstants.FontSizes.categoryHeader, weight: .semibold),
            .foregroundColor: WindowConstants.Colors.categoryHeaderTextColor,
            .kern: 0.6
        ]))
        header.lineBreakMode = .byTruncatingTail

        if let description = description, !description.isEmpty {
            descriptionLabel = makeDescriptionLabel(description, color: WindowConstants.Colors.categoryDescriptionTextColor)
        } else {
            descriptionLabel = nil
        }

        super.init(frame: .zero)

        addSubview(header)
        if let descriptionLabel = descriptionLabel { addSubview(descriptionLabel) }
        rows.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    var columnSpan: Int { 1 }

    var visibleRowCount: Int { rows.reduce(0) { $0 + ($1.isHidden ? 0 : 1) } }

    func arrange(width: CGFloat) -> CGFloat {
        let visibleRows = rows.filter { !$0.isHidden }
        isHidden = visibleRows.isEmpty
        guard !visibleRows.isEmpty else { return 0 }

        // Align titles with the row text, which is inset by the row padding
        let inset = WindowConstants.Row.horizontalPadding
        let textWidth = max(0, width - inset * 2)

        header.frame = NSRect(x: inset, y: 0, width: textWidth, height: Self.headerHeight)
        var y = Self.headerHeight + 4

        if let descriptionLabel = descriptionLabel {
            let height = wrappedHeight(of: descriptionLabel, width: textWidth)
            descriptionLabel.frame = NSRect(x: inset, y: y, width: textWidth, height: height)
            y += height + 4
        }

        for row in visibleRows {
            row.frame = NSRect(x: 0, y: y, width: width, height: WindowConstants.Row.height)
            y += WindowConstants.Row.height
        }

        return y
    }
}

// MARK: - Group

/// A card holding a named group of categories, spread over inner columns when it is large.
final class GroupCardView: NSView, MasonryBlock {
    let sections: [CategorySectionView]
    private let titleLabel: NSTextField
    private let accentBar = NSView()
    private let descriptionLabel: NSTextField?

    private static let titleHeight: CGFloat = 18

    init(title: String, description: String?, sections: [CategorySectionView]) {
        self.sections = sections

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: WindowConstants.FontSizes.groupHeader, weight: .semibold)
        titleLabel.textColor = WindowConstants.Colors.groupHeaderTextColor
        titleLabel.lineBreakMode = .byTruncatingTail

        if let description = description, !description.isEmpty {
            descriptionLabel = makeDescriptionLabel(description, color: WindowConstants.Colors.groupDescriptionTextColor)
        } else {
            descriptionLabel = nil
        }

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = WindowConstants.Colors.containerBackgroundColor.cgColor
        layer?.borderColor = WindowConstants.Colors.containerBorderColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = WindowConstants.Group.cornerRadius

        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        accentBar.layer?.cornerRadius = WindowConstants.Group.accentBarWidth / 2

        addSubview(accentBar)
        addSubview(titleLabel)
        if let descriptionLabel = descriptionLabel { addSubview(descriptionLabel) }
        sections.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private var visibleSections: [CategorySectionView] {
        sections.filter { $0.visibleRowCount > 0 }
    }

    private var visibleItemCount: Int {
        sections.reduce(0) { $0 + $1.visibleRowCount }
    }

    var columnSpan: Int {
        guard visibleItemCount > WindowConstants.Group.singleColumnItemLimit else { return 1 }
        return max(1, min(visibleSections.count, WindowConstants.Group.maxInnerColumns))
    }

    func arrange(width: CGFloat) -> CGFloat {
        let visible = visibleSections
        isHidden = visible.isEmpty
        guard !visible.isEmpty else {
            sections.forEach { _ = $0.arrange(width: 0) }
            return 0
        }

        let padding = WindowConstants.Group.padding
        let spacing = WindowConstants.Group.innerSpacing
        let innerWidth = max(0, width - padding * 2)
        let titleX = padding + WindowConstants.Group.accentBarWidth + 8

        accentBar.frame = NSRect(x: padding, y: padding + 2, width: WindowConstants.Group.accentBarWidth, height: Self.titleHeight - 4)
        titleLabel.frame = NSRect(x: titleX, y: padding, width: max(0, width - titleX - padding), height: Self.titleHeight)
        var y = padding + Self.titleHeight

        if let descriptionLabel = descriptionLabel {
            let height = wrappedHeight(of: descriptionLabel, width: innerWidth)
            descriptionLabel.frame = NSRect(x: padding, y: y + 4, width: innerWidth, height: height)
            y += 4 + height
        }
        y += 10

        // Never use more inner columns than actually fit, so content can't spill out of the card
        let fittingColumns = max(1, Int((innerWidth + spacing) / (WindowConstants.Group.minInnerColumnWidth + spacing)))
        let innerColumns = min(columnSpan, fittingColumns)
        let innerColumnWidth = (innerWidth - CGFloat(innerColumns - 1) * spacing) / CGFloat(innerColumns)

        var columnHeights = [CGFloat](repeating: 0, count: innerColumns)
        for section in sections {
            let height = section.arrange(width: innerColumnWidth)
            guard height > 0 else { continue }

            let column = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = padding + CGFloat(column) * (innerColumnWidth + spacing)
            section.frame = NSRect(x: x, y: y + columnHeights[column], width: innerColumnWidth, height: height)
            columnHeights[column] += height + WindowConstants.rowSpacing
        }

        let contentHeight = max(0, (columnHeights.max() ?? 0) - WindowConstants.rowSpacing)
        return y + contentHeight + padding
    }
}
