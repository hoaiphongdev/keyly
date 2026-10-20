import Cocoa

class KeylyPanel: NSPanel {
    /// Called for key presses nobody else handled; return true to consume the event
    var onUnhandledKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        if onUnhandledKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}

final class ShortcutsWindow: NSWindowController, NSWindowDelegate {
    private var containerView: NSVisualEffectView!
    private var appIconView: NSImageView!
    private var appNameLabel: NSTextField!
    private var countLabel: NSTextField!
    private var searchField: NSSearchField!
    private var scrollView: NSScrollView!
    private var gridContainer: NSView!
    private var emptyStateLabel: NSTextField!
    private var typeToSearchHint: NSTextField!
    private var escHintLabel: NSTextField!
    private var settingsButton: NSButton!

    private var blocks: [MasonryBlock] = []
    private var rowViews: [ShortcutRowView] = []
    private var categoryDescriptions: [String: String] = [:]
    private var groupDescriptions: [String: String] = [:]

    // Grid geometry, fixed for as long as the popup shows one app
    private var numColumns = 1
    private var gridColumnWidth = WindowConstants.columnWidth
    private var contentWidth: CGFloat = 0

    private var clickOutsideMonitor: Any?
    private var localClickMonitor: Any?
    private var firstResponderObservation: NSKeyValueObservation?
    private var isSearchFocused = false

    private let columnSpacing = WindowConstants.columnSpacing
    private let rowSpacing = WindowConstants.rowSpacing
    private let padding = WindowConstants.padding

    convenience init() {
        let initialWidth = WindowConstants.minWindowWidth

        let window = KeylyPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: WindowConstants.defaultWindowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .darkAqua)

        window.delegate = self
        window.onUnhandledKeyDown = { [weak self] event in
            self?.beginSearch(with: event) ?? false
        }

        setupUI()

        firstResponderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            self?.updateSearchFocus()
        }
    }

    override func showWindow(_ sender: Any?) {
        guard let window = window else { return }
        let wasVisible = window.isVisible

        startClickOutsideMonitoring()

        if !wasVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.alphaValue = 0
        }

        super.showWindow(sender)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)

        if window.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = WindowConstants.showAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }

        // The panel may grab the search field as first responder on show; keep it unfocused until typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.searchField.stringValue.isEmpty else { return }
            self.window?.makeFirstResponder(nil)
        }
    }

    func displayShortcuts(_ shortcuts: [ShortcutItem], appName: String, appIcon: NSImage? = nil, categoryDescriptions: [String: String] = [:], groupDescriptions: [String: String] = [:]) {
        self.categoryDescriptions = categoryDescriptions
        self.groupDescriptions = groupDescriptions

        appNameLabel.stringValue = appName
        appIconView.image = appIcon
        appIconView.isHidden = appIcon == nil
        searchField.stringValue = ""
        searchField.placeholderString = "Search in \(appName)…"

        buildBlocks(from: shortcuts)
        sizeWindow(on: targetScreen())
        scrollToTop()
        updateStatus(query: "", visibleCount: rowViews.count)
    }

    // MARK: - UI setup

    private func setupUI() {
        guard let window = window else { return }

        let effectView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: WindowConstants.cornerRadius)
        effectView.autoresizingMask = [.width, .height]
        window.contentView = effectView
        containerView = effectView

        setupHeader()
        setupSearchBar()
        setupScrollView()
        setupFooter()
        setupBorder()
    }

    private func setupHeader() {
        appIconView = NSImageView()
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        containerView.addSubview(appIconView)

        appNameLabel = NSTextField(labelWithString: "")
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        appNameLabel.font = NSFont.systemFont(ofSize: WindowConstants.FontSizes.appName, weight: .semibold)
        appNameLabel.textColor = WindowConstants.Colors.appNameTextColor
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        containerView.addSubview(appNameLabel)

        countLabel = NSTextField(labelWithString: "")
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: WindowConstants.FontSizes.footer, weight: .regular)
        countLabel.textColor = WindowConstants.Colors.countTextColor
        countLabel.alignment = .right
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        containerView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            appIconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding + 2),
            appIconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding + 4),
            appIconView.widthAnchor.constraint(equalToConstant: 20),
            appIconView.heightAnchor.constraint(equalToConstant: 20),

            appNameLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 8),
            appNameLabel.centerYAnchor.constraint(equalTo: appIconView.centerYAnchor),

            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: appNameLabel.trailingAnchor, constant: 12),
            countLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding - 2),
            countLabel.centerYAnchor.constraint(equalTo: appIconView.centerYAnchor)
        ])
    }

    private func setupSearchBar() {
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search shortcuts…"
        searchField.font = NSFont.systemFont(ofSize: WindowConstants.FontSizes.search)
        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .exterior
        containerView.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding + WindowConstants.headerHeight + WindowConstants.searchTopGap),
            searchField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            searchField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            searchField.heightAnchor.constraint(equalToConstant: WindowConstants.searchBarHeight)
        ])
    }

    private func setupScrollView() {
        scrollView = OverlayScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        containerView.addSubview(scrollView)

        gridContainer = FlippedView()
        scrollView.documentView = gridContainer

        emptyStateLabel = NSTextField(labelWithString: "")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.lineBreakMode = .byTruncatingTail
        emptyStateLabel.isHidden = true
        containerView.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: WindowConstants.gridTopGap),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -WindowConstants.footerHeight - WindowConstants.gridBottomGap),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 32),
            emptyStateLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -32)
        ])
    }

    private func setupFooter() {
        escHintLabel = makeFooterLabel("Close")
        let escHint = NSStackView(views: [KeycapView(KeySymbol.escape), escHintLabel])
        escHint.orientation = .horizontal
        escHint.spacing = 6

        typeToSearchHint = makeFooterLabel("Type to search")

        let hints = NSStackView(views: [escHint, typeToSearchHint])
        hints.translatesAutoresizingMaskIntoConstraints = false
        hints.orientation = .horizontal
        hints.spacing = 14
        containerView.addSubview(hints)

        settingsButton = NSButton(frame: .zero)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.contentTintColor = WindowConstants.Colors.settingsButtonTint
        settingsButton.toolTip = "Settings"
        settingsButton.target = self
        settingsButton.action = #selector(showSettingsMenu)
        containerView.addSubview(settingsButton)

        let footerCenterY = WindowConstants.footerHeight / 2

        NSLayoutConstraint.activate([
            hints.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding + 2),
            hints.centerYAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -footerCenterY),

            settingsButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding + 2),
            settingsButton.centerYAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -footerCenterY),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func makeFooterLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: WindowConstants.FontSizes.footer)
        label.textColor = WindowConstants.Colors.footerTextColor
        return label
    }

    /// Hairline on top of the blur so the edge stays crisp on any wallpaper
    private func setupBorder() {
        let border = PassthroughView(frame: containerView.bounds)
        border.autoresizingMask = [.width, .height]
        border.wantsLayer = true
        border.layer?.cornerRadius = WindowConstants.cornerRadius
        border.layer?.borderWidth = 0.5
        border.layer?.borderColor = WindowConstants.Colors.windowBorderColor.cgColor
        containerView.addSubview(border)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Content

    private enum Chunk {
        case group(name: String, shortcuts: [ShortcutItem])
        case ungroupedCategory(name: String, shortcuts: [ShortcutItem])
    }

    /// Splits shortcuts into named groups and loose categories, keeping first-seen order.
    /// Items of a group that reappears later are merged into its first occurrence.
    private func makeChunks(from shortcuts: [ShortcutItem]) -> [Chunk] {
        var chunks: [Chunk] = []
        var pendingGroupName: String?
        var pendingGroupItems: [ShortcutItem] = []

        func flushPendingGroup() {
            defer {
                pendingGroupName = nil
                pendingGroupItems = []
            }
            guard let name = pendingGroupName, !pendingGroupItems.isEmpty else { return }

            if let index = chunks.firstIndex(where: {
                if case .group(let n, _) = $0 { return n == name }
                return false
            }), case .group(_, let existing) = chunks[index] {
                chunks[index] = .group(name: name, shortcuts: existing + pendingGroupItems)
            } else {
                chunks.append(.group(name: name, shortcuts: pendingGroupItems))
            }
        }

        for shortcut in shortcuts {
            let group = shortcut.group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !group.isEmpty {
                if group != pendingGroupName {
                    flushPendingGroup()
                    pendingGroupName = group
                }
                pendingGroupItems.append(shortcut)
                continue
            }

            flushPendingGroup()

            let category = shortcut.category
            if let index = chunks.lastIndex(where: {
                if case .ungroupedCategory(let n, _) = $0 { return n == category }
                return false
            }), case .ungroupedCategory(_, let existing) = chunks[index] {
                chunks[index] = .ungroupedCategory(name: category, shortcuts: existing + [shortcut])
            } else {
                chunks.append(.ungroupedCategory(name: category, shortcuts: [shortcut]))
            }
        }
        flushPendingGroup()

        return chunks
    }

    /// Builds every view once per popup; searching only hides rows and re-places blocks.
    private func buildBlocks(from shortcuts: [ShortcutItem]) {
        gridContainer.subviews.forEach { $0.removeFromSuperview() }
        blocks = []
        rowViews = []

        for chunk in makeChunks(from: shortcuts) {
            switch chunk {
            case .group(let name, let items):
                var categoryOrder: [String] = []
                var itemsByCategory: [String: [ShortcutItem]] = [:]
                for item in items {
                    if itemsByCategory[item.category] == nil { categoryOrder.append(item.category) }
                    itemsByCategory[item.category, default: []].append(item)
                }
                let sections = categoryOrder.map { makeSection(title: $0, items: itemsByCategory[$0] ?? []) }
                blocks.append(GroupCardView(title: name, description: groupDescriptions[name], sections: sections))

            case .ungroupedCategory(let name, let items):
                blocks.append(makeSection(title: name, items: items))
            }
        }

        blocks.forEach { gridContainer.addSubview($0) }
    }

    private func makeSection(title: String, items: [ShortcutItem]) -> CategorySectionView {
        let rows = items.map { item in
            ShortcutRowView(model: ShortcutRowModel(
                item: item,
                categoryDescription: categoryDescriptions[item.category],
                groupDescription: item.group.flatMap { groupDescriptions[$0] }
            ))
        }
        rowViews.append(contentsOf: rows)
        return CategorySectionView(title: title, description: categoryDescriptions[title], rows: rows)
    }

    // MARK: - Layout

    /// The screen the user is looking at: the one under the mouse pointer
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Picks columns and window size for the full list. Searching never resizes the window.
    private func sizeWindow(on screen: NSScreen?) {
        guard let window = window else { return }

        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: WindowConstants.defaultScreenSize)
        let settings = SettingsManager.shared.getSettings()
        let maxWindowWidth = visibleFrame.width * CGFloat(settings.ui.screenWidthRatio)
        let maxGridWidth = maxWindowWidth - padding * 2

        let minColumnWidth = visibleFrame.width < WindowConstants.compactScreenWidth
            ? WindowConstants.compactColumnWidth
            : WindowConstants.columnWidth
        let maxPossibleColumns = max(1, Int((maxGridWidth + columnSpacing) / (minColumnWidth + columnSpacing)))
        let wantedColumns = max(blocks.map(\.columnSpan).max() ?? 1, blocks.count)
        numColumns = max(1, min(wantedColumns, maxPossibleColumns))

        // Rows inside a group card lose the card's padding on both sides
        let widestRow = rowViews.map { row in
            row.model.requiredWidth + (row.model.item.group != nil ? WindowConstants.Group.padding * 2 : 0)
        }.max() ?? minColumnWidth
        let fittingColumnWidth = (maxGridWidth - CGFloat(numColumns - 1) * columnSpacing) / CGFloat(numColumns)
        // `min` last: on very small screens fitting wins over the preferred minimum, so nothing overflows
        gridColumnWidth = floor(min(max(widestRow, minColumnWidth), fittingColumnWidth))

        let gridWidth = CGFloat(numColumns) * gridColumnWidth + CGFloat(numColumns - 1) * columnSpacing
        let windowWidth = max(gridWidth + padding * 2, min(WindowConstants.minWindowWidth, visibleFrame.width - 40))
        contentWidth = windowWidth - padding * 2

        let gridHeight = layoutGrid()
        let maxWindowHeight = visibleFrame.height * WindowConstants.maxScreenHeightRatio
        let windowHeight = min(max(WindowConstants.chromeHeight + gridHeight, WindowConstants.minWindowHeight), maxWindowHeight)

        let frame = NSRect(
            x: round(visibleFrame.midX - windowWidth / 2),
            y: round(visibleFrame.midY - windowHeight / 2),
            width: windowWidth,
            height: windowHeight
        )
        window.setFrame(frame, display: true)
        window.invalidateShadow()
    }

    /// Masonry placement of the visible blocks into the fixed columns. Returns the grid height.
    @discardableResult
    private func layoutGrid() -> CGFloat {
        let gridWidth = CGFloat(numColumns) * gridColumnWidth + CGFloat(numColumns - 1) * columnSpacing
        let gridOffset = max(0, floor((contentWidth - gridWidth) / 2))
        var columnHeights = [CGFloat](repeating: 0, count: numColumns)

        for block in blocks {
            let span = min(block.columnSpan, numColumns)
            let width = CGFloat(span) * gridColumnWidth + CGFloat(span - 1) * columnSpacing
            let height = block.arrange(width: width)
            guard height > 0 else { continue }

            var bestStart = 0
            var bestY = CGFloat.greatestFiniteMagnitude
            for start in 0...(numColumns - span) {
                let y = columnHeights[start..<(start + span)].max() ?? 0
                if y < bestY {
                    bestY = y
                    bestStart = start
                }
            }

            let x = gridOffset + CGFloat(bestStart) * (gridColumnWidth + columnSpacing)
            block.frame = NSRect(x: x, y: bestY, width: width, height: height)
            for column in bestStart..<(bestStart + span) {
                columnHeights[column] = bestY + height + rowSpacing
            }
        }

        let height = max(0, (columnHeights.max() ?? 0) - rowSpacing)
        gridContainer.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
        return height
    }

    // MARK: - Search

    /// Clears an active search. Returns false when there was nothing to clear.
    func clearSearch() -> Bool {
        guard !searchField.stringValue.isEmpty else { return false }
        searchField.stringValue = ""
        applyFilter("")
        return true
    }

    @objc private func searchTextChanged() {
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSearching = !query.isEmpty

        var visibleCount = 0
        for row in rowViews {
            let matches = !isSearching || row.model.searchText.contains(query)
            if row.isHidden == matches { row.isHidden = !matches }
            row.setHighlight(matches && isSearching ? query : nil)
            if matches { visibleCount += 1 }
        }

        layoutGrid()
        scrollToTop()
        updateStatus(query: text.trimmingCharacters(in: .whitespacesAndNewlines), visibleCount: visibleCount)
    }

    private func scrollToTop() {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Count in the header, footer hint and empty state for the current query
    private func updateStatus(query: String, visibleCount: Int) {
        let total = rowViews.count
        countLabel.stringValue = query.isEmpty
            ? "\(total) shortcut\(total == 1 ? "" : "s")"
            : "\(visibleCount) of \(total)"
        typeToSearchHint.isHidden = !query.isEmpty || total == 0
        escHintLabel.stringValue = query.isEmpty ? "Close" : "Clear search"

        emptyStateLabel.isHidden = visibleCount > 0
        guard visibleCount == 0 else { return }

        let title = query.isEmpty ? "No shortcuts found for this app" : "No shortcuts match “\(query)”"
        let hint = query.isEmpty ? "Add your own in the config folder (⚙︎ → Open Config Folder)" : "Try an action name, a menu, or a key like ⌘K"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        let text = NSMutableAttributedString(string: title + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: WindowConstants.Colors.emptyStateTextColor,
            .paragraphStyle: paragraph
        ])
        text.append(NSAttributedString(string: hint, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: WindowConstants.Colors.emptyStateHintColor,
            .paragraphStyle: paragraph
        ]))
        emptyStateLabel.attributedStringValue = text
    }

    /// Type-to-search: a printable key pressed while the popup has focus goes into the search field.
    private func beginSearch(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.characters,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !(0xF700...0xF8FF).contains(scalar.value) // arrow / function keys
        else { return false }

        guard window?.makeFirstResponder(searchField) == true,
              let editor = searchField.currentEditor() else { return false }
        // Replay the key through the field editor so input methods and dead keys still apply
        editor.keyDown(with: event)
        return true
    }

    private func updateSearchFocus() {
        let editor = window?.firstResponder as? NSText
        isSearchFocused = editor?.delegate === searchField
    }

    // MARK: - Click outside

    private func startClickOutsideMonitoring() {
        if clickOutsideMonitor == nil {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self, let window = self.window, window.isVisible else { return }

                if !window.frame.contains(NSEvent.mouseLocation) {
                    DispatchQueue.main.async {
                        self.close()
                    }
                }
            }
        }

        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self, let window = self.window, window.isVisible else { return event }

                if let eventWindow = event.window, eventWindow != window {
                    DispatchQueue.main.async {
                        self.close()
                    }
                }
                return event
            }
        }
    }

    private func stopClickOutsideMonitoring() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }

        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    override func close() {
        stopClickOutsideMonitoring()
        super.close()
    }

    deinit {
        stopClickOutsideMonitoring()
    }

    // MARK: - Settings menu

    @objc private func showSettingsMenu() {
        let menu = NSMenu()

        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let openFolderItem = NSMenuItem(title: "Open Config Folder", action: #selector(openConfigFolder), keyEquivalent: "")
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(NSMenuItem.separator())

        let accessibilityItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Keyly", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let menuWidth = menu.size.width
        let location = NSPoint(x: settingsButton.frame.maxX - menuWidth, y: settingsButton.frame.minY)
        menu.popUp(positioning: nil, at: location, in: containerView)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        self.close()
    }

    @objc private func checkForUpdates() {
        self.close()
        Updater.shared.checkForUpdates()
    }

    @objc private func reloadConfig() {
        ConfigManager.shared.reload()
    }

    @objc private func openConfigFolder() {
        ConfigManager.shared.openConfigFolder()
        self.close()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Overlay scrollers never take width from the grid. NSScrollView re-applies the system
/// scroller style when the "Show scroll bars" setting changes, so the style is pinned here.
final class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}

/// Decoration that never intercepts clicks
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - NSWindowDelegate
extension ShortcutsWindow {
    func windowDidResignKey(_ notification: Notification) {
        if !isSearchFocused {
            close()
        }
    }
}

// MARK: - NSSearchFieldDelegate
extension ShortcutsWindow: NSSearchFieldDelegate {
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        applyFilter("")
    }
}
