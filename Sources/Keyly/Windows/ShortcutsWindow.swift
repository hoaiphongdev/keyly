import Cocoa

class KeylyPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    override var acceptsFirstResponder: Bool {
        return true
    }
}

final class ShortcutsWindow: NSWindowController, NSWindowDelegate {
    private var containerView: NSView!
    private var scrollView: NSScrollView!
    private var gridContainer: NSView!
    private var settingsButton: NSButton!
    private var escLabel: NSTextField!
    private var updateBanner: NSView?
    private var scrollViewTopConstraint: NSLayoutConstraint!
    private var shortcuts: [ShortcutItem] = []
    private var allShortcuts: [ShortcutItem] = []
    private var categoryDescriptions: [String: String] = [:]
    private var groupDescriptions: [String: String] = [:]
    private var updateButton: NSButton?
    private var spinner: NSProgressIndicator?
    private var clickOutsideMonitor: Any?
    private var localClickMonitor: Any?
    private var searchField: NSSearchField!
    private var searchContainer: NSView!
    private var isSearchFocused = false
    private var isSearchActive = false
    private var keyboardMonitor: Any?
    private var searchTimer: Timer?

    private let columnWidth = WindowConstants.columnWidth
    private let columnSpacing = WindowConstants.columnSpacing
    private let rowSpacing = WindowConstants.rowSpacing
    private let padding = WindowConstants.padding
    private let footerHeight = WindowConstants.footerHeight
    private let bannerHeight = WindowConstants.bannerHeight
    private let shortcutRowGap: CGFloat = 10

    convenience init() {
        let initialWidth = WindowConstants.columnWidth + WindowConstants.padding * 2

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

        window.delegate = self

        setupUI()
        setupClickOutsideMonitoring()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    func displayShortcuts(_ shortcuts: [ShortcutItem], appName: String, categoryDescriptions: [String: String] = [:], groupDescriptions: [String: String] = [:]) {
        self.allShortcuts = shortcuts
        self.shortcuts = shortcuts
        self.categoryDescriptions = categoryDescriptions
        self.groupDescriptions = groupDescriptions

        searchField?.stringValue = ""

        rebuildContent()
        updateUpdateBanner()
        resizeWindowToFit()
        window?.center()
    }

    private func updateUpdateBanner() {
        updateBanner?.removeFromSuperview()
        updateBanner = nil
        updateButton = nil
        spinner = nil
        scrollViewTopConstraint.constant = 8

        let state = UpdateManager.shared.updateState
        switch state {
        case .none, .error:
            guard UpdateManager.shared.updateAvailable else { return }
        case .checking, .available, .downloading, .readyToInstall:
            break
        }

        let banner = NSView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.wantsLayer = true

        let isReady: Bool
        let isChecking: Bool
        let isDownloading: Bool

        switch state {
        case .readyToInstall:
            isReady = true
            isChecking = false
            isDownloading = false
        case .checking:
            isReady = false
            isChecking = true
            isDownloading = false
        case .downloading:
            isReady = false
            isChecking = false
            isDownloading = true
        default:
            isReady = false
            isChecking = false
            isDownloading = false
        }

        let bgColor = isReady ? NSColor.systemGreen.withAlphaComponent(0.2) : NSColor.systemBlue.withAlphaComponent(0.2)
        let accentColor = isReady ? NSColor.systemGreen : NSColor.systemBlue
        banner.layer?.backgroundColor = bgColor.cgColor
        banner.layer?.cornerRadius = 8

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        let iconName: String
        if isReady {
            iconName = "checkmark.circle.fill"
        } else if isChecking {
            iconName = "arrow.clockwise.circle.fill"
        } else {
            iconName = "arrow.down.circle.fill"
        }
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Update")
        icon.contentTintColor = accentColor

        let version = UpdateManager.shared.latestVersion ?? "new version"
        let labelText: String
        switch state {
        case .checking:
            labelText = "Checking for updates..."
        case .downloading:
            labelText = "Downloading v\(version)..."
        case .readyToInstall:
            labelText = "v\(version) ready to install!"
        default:
            labelText = "Update available: v\(version)"
        }

        let label = NSTextField(labelWithString: labelText)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = WindowConstants.Colors.primaryTextColor

        banner.addSubview(icon)
        banner.addSubview(label)

        if isReady {
            let relaunchBtn = NSButton(title: "Relaunch", target: self, action: #selector(doRelaunch))
            relaunchBtn.translatesAutoresizingMaskIntoConstraints = false
            relaunchBtn.bezelStyle = .rounded
            relaunchBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            relaunchBtn.contentTintColor = .systemGreen
            banner.addSubview(relaunchBtn)

            NSLayoutConstraint.activate([
                relaunchBtn.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -10),
                relaunchBtn.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
            ])
        } else if isChecking || isDownloading {
            let spinnerView = NSProgressIndicator()
            spinnerView.translatesAutoresizingMaskIntoConstraints = false
            spinnerView.style = .spinning
            spinnerView.controlSize = .small
            spinnerView.startAnimation(nil)
            banner.addSubview(spinnerView)
            spinner = spinnerView

            NSLayoutConstraint.activate([
                spinnerView.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
                spinnerView.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
                spinnerView.widthAnchor.constraint(equalToConstant: 16),
                spinnerView.heightAnchor.constraint(equalToConstant: 16)
            ])
        } else {
            let updateBtn = NSButton(title: "Update Now", target: self, action: #selector(doUpdate))
            updateBtn.translatesAutoresizingMaskIntoConstraints = false
            updateBtn.bezelStyle = .rounded
            updateBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            self.updateButton = updateBtn

            let laterBtn = NSButton(title: "Later", target: self, action: #selector(dismissBanner))
            laterBtn.translatesAutoresizingMaskIntoConstraints = false
            laterBtn.bezelStyle = .inline
            laterBtn.font = NSFont.systemFont(ofSize: 11)

            banner.addSubview(updateBtn)
            banner.addSubview(laterBtn)

            NSLayoutConstraint.activate([
                laterBtn.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -10),
                laterBtn.centerYAnchor.constraint(equalTo: banner.centerYAnchor),

                updateBtn.trailingAnchor.constraint(equalTo: laterBtn.leadingAnchor, constant: -8),
                updateBtn.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
            ])
        }

        containerView.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            banner.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            banner.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            banner.heightAnchor.constraint(equalToConstant: bannerHeight - padding),

            icon.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])

        updateBanner = banner
        scrollViewTopConstraint.constant = 8 + bannerHeight

        UpdateManager.shared.onUpdateStateChanged = { [weak self] newState in
            self?.updateUpdateBanner()
        }
    }

    @objc private func doUpdate() {
        let mockUpdate = ProcessInfo.processInfo.environment["KEYLY_MOCK_UPDATE"] == "1"

        if mockUpdate {
            UpdateManager.shared.simulateDownload { [weak self] in
                self?.updateUpdateBanner()
            }
            updateUpdateBanner()
        } else {
            UpdateManager.shared.performUpdate()
        }
    }

    @objc private func doRelaunch() {
        UpdateManager.shared.relaunchApp()
    }

    @objc private func dismissBanner() {
        updateBanner?.removeFromSuperview()
        updateBanner = nil
        scrollViewTopConstraint.constant = 8
        containerView.layoutSubtreeIfNeeded()
    }

    private func setupUI() {
        guard let window = window else { return }

        let solidView = NSView(frame: window.contentView!.bounds)
        solidView.wantsLayer = true
        solidView.layer?.backgroundColor = NSColor.black.cgColor
        solidView.layer?.cornerRadius = 12
        solidView.layer?.masksToBounds = true
        solidView.autoresizingMask = [.width, .height]

        containerView = solidView
        window.contentView?.addSubview(containerView)

        scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        containerView.addSubview(scrollView)

        gridContainer = FlippedView()
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = gridContainer

        setupSearchBar()

        scrollViewTopConstraint = scrollView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8)

        NSLayoutConstraint.activate([
            scrollViewTopConstraint,
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -padding - footerHeight)
        ])

        setupSettingsButton()
        setupEscLabel()
    }

    private func setupSearchBar() {
        searchContainer = NSView()
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(searchContainer)

        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search shortcuts..."
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        searchField.delegate = self
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.refusesFirstResponder = false

        // Custom appearance for better border
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 6
        searchField.layer?.borderWidth = 1
        searchField.layer?.borderColor = NSColor.separatorColor.cgColor
        searchField.focusRingType = .none

        searchContainer.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            searchContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            searchContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            searchContainer.heightAnchor.constraint(equalToConstant: WindowConstants.searchBarHeight),

            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])
    }

    @objc private func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    @objc private func searchTextChanged() {
        searchTimer?.invalidate()

        let searchText = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.filterShortcuts(with: searchText)
        }
    }

    private func filterShortcuts(with searchText: String) {
        if searchText.isEmpty {
            shortcuts = allShortcuts
            isSearchActive = false
        } else {
            let lowercaseSearch = searchText.lowercased()
            shortcuts = allShortcuts.filter { shortcut in
                matchesSearch(shortcut: shortcut, searchText: lowercaseSearch)
            }
            isSearchActive = true
        }

        DispatchQueue.main.async { [weak self] in
            self?.rebuildContent()
            self?.resizeWindowToFit()
        }
    }

    private func matchesSearch(shortcut: ShortcutItem, searchText: String) -> Bool {
        if shortcut.action.lowercased().contains(searchText) {
            return true
        }

        if shortcut.category.lowercased().contains(searchText) {
            return true
        }

        if let group = shortcut.group, group.lowercased().contains(searchText) {
            return true
        }

        if let categoryDesc = categoryDescriptions[shortcut.category],
           categoryDesc.lowercased().contains(searchText) {
            return true
        }

        if let group = shortcut.group,
           let groupDesc = groupDescriptions[group],
           groupDesc.lowercased().contains(searchText) {
            return true
        }

        if shortcut.shortcut.lowercased().contains(searchText) {
            return true
        }

        return false
    }

    private func setupSettingsButton() {
        settingsButton = NSButton(frame: .zero)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        settingsButton.contentTintColor = WindowConstants.Colors.settingsButtonTint
        settingsButton.target = self
        settingsButton.action = #selector(showSettingsMenu)

        containerView.addSubview(settingsButton)

        NSLayoutConstraint.activate([
            settingsButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            settingsButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func setupEscLabel() {
        escLabel = NSTextField(labelWithString: "Press ESC to close")
        escLabel.translatesAutoresizingMaskIntoConstraints = false
        escLabel.font = NSFont.systemFont(ofSize: 11)
        escLabel.textColor = WindowConstants.Colors.escLabelColor
        escLabel.alignment = .left

        containerView.addSubview(escLabel)

        NSLayoutConstraint.activate([
            escLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            escLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
    }

    private func setupClickOutsideMonitoring() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.window, window.isVisible else { return }

            let screenClickLocation = NSEvent.mouseLocation
            let windowFrame = window.frame

            if !windowFrame.contains(screenClickLocation) {
                DispatchQueue.main.async {
                    self.close()
                }
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.window, window.isVisible else { return event }

            if let eventWindow = event.window, eventWindow != window {
                DispatchQueue.main.async {
                    self.close()
                }
                return event
            }

            return event
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
        searchTimer?.invalidate()
        searchTimer = nil
        super.close()
    }

    deinit {
        stopClickOutsideMonitoring()
        searchTimer?.invalidate()
    }

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

        // MARK: - Update feature temporarily disabled
        // let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        // checkUpdatesItem.target = self
        // menu.addItem(checkUpdatesItem)

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
        UpdateManager.shared.checkForUpdates()
        self.close()
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

    private func rebuildContent() {
        gridContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let window = window else {
            print("[Keyly] Warning: No window available for content rebuild")
            return
        }

        guard !shortcuts.isEmpty else {
            print("[Keyly] Warning: No shortcuts to display")
            return
        }

        enum LayoutChunk {
            case group(name: String, shortcuts: [ShortcutItem])
            case ungroupedCategory(name: String, shortcuts: [ShortcutItem])
        }

        var chunks: [LayoutChunk] = []
        var currentGroupName: String? = nil
        var currentGroupItems: [ShortcutItem] = []
        var seenGroups = Set<String>()

        for shortcut in shortcuts {
            let group = shortcut.group?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasGroup = group != nil && !group!.isEmpty

            if hasGroup {
                if group! != (currentGroupName ?? "") {
                    if let prevGroup = currentGroupName, !currentGroupItems.isEmpty {
                        if seenGroups.contains(prevGroup) {
                            if let idx = chunks.firstIndex(where: {
                                if case .group(let n, _) = $0 { return n == prevGroup }
                                return false
                            }) {
                                if case .group(let n, let existing) = chunks[idx] {
                                    chunks[idx] = .group(name: n, shortcuts: existing + currentGroupItems)
                                }
                            }
                        } else {
                            chunks.append(.group(name: prevGroup, shortcuts: currentGroupItems))
                            seenGroups.insert(prevGroup)
                        }
                    }
                    currentGroupName = group!
                    currentGroupItems = [shortcut]
                } else {
                    currentGroupItems.append(shortcut)
                }
            } else {
                // Flush pending group
                if let prevGroup = currentGroupName, !currentGroupItems.isEmpty {
                    if seenGroups.contains(prevGroup) {
                        if let idx = chunks.firstIndex(where: {
                            if case .group(let n, _) = $0 { return n == prevGroup }
                            return false
                        }) {
                            if case .group(let n, let existing) = chunks[idx] {
                                chunks[idx] = .group(name: n, shortcuts: existing + currentGroupItems)
                            }
                        }
                    } else {
                        chunks.append(.group(name: prevGroup, shortcuts: currentGroupItems))
                        seenGroups.insert(prevGroup)
                    }
                    currentGroupName = nil
                    currentGroupItems = []
                }

                let cat = shortcut.category
                if let lastIdx = chunks.lastIndex(where: {
                    if case .ungroupedCategory(let n, _) = $0 { return n == cat }
                    return false
                }) {
                    if case .ungroupedCategory(let n, let existing) = chunks[lastIdx] {
                        chunks[lastIdx] = .ungroupedCategory(name: n, shortcuts: existing + [shortcut])
                    }
                } else {
                    chunks.append(.ungroupedCategory(name: cat, shortcuts: [shortcut]))
                }
            }
        }

        if let prevGroup = currentGroupName, !currentGroupItems.isEmpty {
            if seenGroups.contains(prevGroup) {
                if let idx = chunks.firstIndex(where: {
                    if case .group(let n, _) = $0 { return n == prevGroup }
                    return false
                }) {
                    if case .group(let n, let existing) = chunks[idx] {
                        chunks[idx] = .group(name: n, shortcuts: existing + currentGroupItems)
                    }
                }
            } else {
                chunks.append(.group(name: prevGroup, shortcuts: currentGroupItems))
            }
        }

        var maxGroupSpan = 1
        var ungroupedCount = 0
        for chunk in chunks {
            switch chunk {
            case .group(_, let groupShortcuts):
                let itemCount = groupShortcuts.count
                let categoryCount = Set(groupShortcuts.map { $0.category }).count
                let span: Int
                if itemCount <= 10 {
                    span = 1
                } else {
                    span = min(categoryCount, 4)
                }
                maxGroupSpan = max(maxGroupSpan, span)
            case .ungroupedCategory:
                ungroupedCount += 1
            }
        }
        let totalItems = max(maxGroupSpan, ungroupedCount)

        let screenSize = NSScreen.main?.visibleFrame.size ?? WindowConstants.defaultScreenSize
        let settings = SettingsManager.shared.getSettings()
        let maxScreenWidth = screenSize.width * CGFloat(settings.ui.screenWidthRatio)
        let maxPossibleColumns = max(1, Int(maxScreenWidth / (columnWidth + columnSpacing)))

        let numColumns = min(totalItems, maxPossibleColumns)
        let maxColumnWidthForLayout = max(
            columnWidth,
            (maxScreenWidth - padding * 2 - CGFloat(max(0, numColumns - 1)) * columnSpacing) / CGFloat(max(1, numColumns))
        )
        let dynamicColumnWidth = calculateDynamicColumnWidth(
            shortcuts: shortcuts,
            maxColumnWidth: maxColumnWidthForLayout
        )

        let actualTotalWidth = CGFloat(numColumns) * dynamicColumnWidth + CGFloat(max(0, numColumns - 1)) * columnSpacing
        var newWindowWidth = actualTotalWidth + padding * 2

        if isSearchActive {
            newWindowWidth = max(newWindowWidth, WindowConstants.minSearchWindowWidth)
        }
        newWindowWidth = min(newWindowWidth, maxScreenWidth)

        window.setContentSize(NSSize(width: newWindowWidth, height: window.frame.height))

        let availableWidth = newWindowWidth - padding * 2
        var columnYPositions = [CGFloat](repeating: 0, count: numColumns)
        let gridOffset = (availableWidth - actualTotalWidth) / 2

        for chunk in chunks {
            switch chunk {
            case .group(let groupName, let groupShortcuts):
                let itemCount = groupShortcuts.count
                let categoryCount = Set(groupShortcuts.map { $0.category }).count
                let innerColumnsNeeded: Int
                if itemCount <= 10 {
                    innerColumnsNeeded = 1
                } else {
                    innerColumnsNeeded = min(categoryCount, 4)
                }
                let gridColumnsNeeded = min(innerColumnsNeeded, numColumns)

                let placedWidth = CGFloat(gridColumnsNeeded) * dynamicColumnWidth + CGFloat(max(0, gridColumnsNeeded - 1)) * columnSpacing

                let groupView = createGroupContainer(groupName: groupName, shortcuts: groupShortcuts, fixedWidth: placedWidth, singleColumnWidth: dynamicColumnWidth)
                groupView.layoutSubtreeIfNeeded()

                let height = groupView.fittingSize.height

                var bestStart = 0
                var bestY: CGFloat = .greatestFiniteMagnitude
                for start in 0...(numColumns - gridColumnsNeeded) {
                    let maxY = (start..<(start + gridColumnsNeeded)).map { columnYPositions[$0] }.max() ?? 0
                    if maxY < bestY {
                        bestY = maxY
                        bestStart = start
                    }
                }

                let x = gridOffset + CGFloat(bestStart) * (dynamicColumnWidth + columnSpacing)
                groupView.frame = NSRect(x: x, y: bestY, width: placedWidth, height: height)
                gridContainer.addSubview(groupView)

                let newY = bestY + height + rowSpacing
                for col in bestStart..<(bestStart + gridColumnsNeeded) {
                    columnYPositions[col] = newY
                }

            case .ungroupedCategory(let category, let items):
                let description = categoryDescriptions[category]
                let view = createCategoryColumn(title: category, description: description, items: items, columnWidth: dynamicColumnWidth)
                view.layoutSubtreeIfNeeded()

                let height = view.fittingSize.height
                let targetColumn = columnYPositions.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
                let x = gridOffset + CGFloat(targetColumn) * (dynamicColumnWidth + columnSpacing)
                let y = columnYPositions[targetColumn]

                view.frame = NSRect(x: x, y: y, width: dynamicColumnWidth, height: height)
                gridContainer.addSubview(view)

                columnYPositions[targetColumn] += height + rowSpacing
            }
        }

        let maxHeight = columnYPositions.max() ?? 0

        gridContainer.frame = NSRect(x: 0, y: 0, width: availableWidth, height: maxHeight)
    }

    private func resizeWindowToFit() {
        guard let window = window else { return }

        let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        let maxHeight = screenSize.height * WindowConstants.maxScreenHeightRatio

        let contentHeight = gridContainer.frame.height + padding * 2 + footerHeight + WindowConstants.searchBarHeight + 8
        let calculatedHeight = min(contentHeight, maxHeight)

        let minHeight = isSearchActive ? WindowConstants.minSearchWindowHeight : WindowConstants.minWindowHeight
        let newHeight = max(calculatedHeight, minHeight)

        window.setContentSize(NSSize(width: window.frame.width, height: newHeight))
    }

    private func calculateDynamicColumnWidth(shortcuts: [ShortcutItem], maxColumnWidth: CGFloat) -> CGFloat {
        guard !shortcuts.isEmpty else { return columnWidth }

        let leftFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let rightFont = NSFont.systemFont(ofSize: 11)
        var widestRequired: CGFloat = columnWidth

        for item in shortcuts {
            let leftWidth = (item.shortcut as NSString).size(withAttributes: [.font: leftFont]).width
            let rightWidth = (item.action as NSString).size(withAttributes: [.font: rightFont]).width
            let rowRequired = leftWidth + shortcutRowGap + rightWidth + 12
            widestRequired = max(widestRequired, rowRequired)
        }

        return min(max(widestRequired, columnWidth), maxColumnWidth)
    }

    private func createCategoryColumn(title: String, description: String?, items: [ShortcutItem], columnWidth: CGFloat) -> NSView {
        guard !title.isEmpty && !items.isEmpty else {
            print("[Keyly] Warning: Empty title or items for category column")
            return NSView()
        }

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 5
        column.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title)
        header.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        header.textColor = WindowConstants.Colors.primaryTextColor
        column.addArrangedSubview(header)

        if let desc = description, !desc.isEmpty {
            let descLabel = NSTextField()
            descLabel.stringValue = desc
            descLabel.font = NSFont.systemFont(ofSize: 10)
            descLabel.textColor = WindowConstants.Colors.categoryDescriptionTextColor
            descLabel.backgroundColor = .clear
            descLabel.isBordered = false
            descLabel.isEditable = false
            descLabel.isSelectable = false
            descLabel.lineBreakMode = .byWordWrapping
            descLabel.usesSingleLineMode = false
            descLabel.maximumNumberOfLines = 0
            descLabel.translatesAutoresizingMaskIntoConstraints = false

            column.addArrangedSubview(descLabel)

            NSLayoutConstraint.activate([
                descLabel.widthAnchor.constraint(equalToConstant: columnWidth - 8)
            ])
        }

        for item in items {
            let row = createShortcutRow(item, availableWidth: columnWidth)
            column.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            column.widthAnchor.constraint(equalToConstant: columnWidth)
        ])

        return column
    }

    private func createGroupContainer(groupName: String, shortcuts: [ShortcutItem], fixedWidth: CGFloat, singleColumnWidth: CGFloat) -> NSView {
        guard !groupName.isEmpty && !shortcuts.isEmpty else {
            print("[Keyly] Warning: Empty group name or shortcuts for group container")
            return NSView()
        }

        let containerPadding: CGFloat = 12
        let innerSpacing: CGFloat = 16
        let totalInnerWidth = fixedWidth - containerPadding * 2

        // Determine inner columns count
        let totalItemCount = shortcuts.count
        let categoryCount = Set(shortcuts.map { $0.category }).count
        let innerColumns: Int
        if totalItemCount <= 10 {
            innerColumns = 1
        } else {
            innerColumns = min(categoryCount, 4)
        }

        // Calculate inner column width to fill available space evenly
        let innerColumnWidth = max(100, (totalInnerWidth - CGFloat(max(0, innerColumns - 1)) * innerSpacing) / CGFloat(innerColumns))

        // Build & measure category views
        let grouped = Dictionary(grouping: shortcuts) { $0.category }
        let sortedCategories = grouped.keys.sorted { cat1, cat2 in
            let idx1 = shortcuts.firstIndex { $0.category == cat1 } ?? Int.max
            let idx2 = shortcuts.firstIndex { $0.category == cat2 } ?? Int.max
            return idx1 < idx2
        }

        var categoryViews: [(view: NSView, height: CGFloat)] = []
        for category in sortedCategories {
            guard let items = grouped[category] else { continue }
            let desc = categoryDescriptions[category]
            let view = createCategoryColumn(title: category, description: desc, items: items, columnWidth: innerColumnWidth)
            view.layoutSubtreeIfNeeded()
            categoryViews.append((view: view, height: view.fittingSize.height))
        }

        // Place categories using shortest-column-first
        var colYPositions = [CGFloat](repeating: 0, count: innerColumns)
        for item in categoryViews {
            let targetCol = colYPositions.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let x = CGFloat(targetCol) * (innerColumnWidth + innerSpacing)
            let y = colYPositions[targetCol]
            item.view.frame = NSRect(x: x, y: y, width: innerColumnWidth, height: item.height)
            colYPositions[targetCol] += item.height + rowSpacing
        }

        let innerContentHeight = colYPositions.max() ?? 0

        // Build container with auto layout
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = WindowConstants.Colors.containerBackgroundColor.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = WindowConstants.Colors.containerBorderColor.cgColor

        // Header
        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let groupHeader = NSTextField(labelWithString: groupName)
        groupHeader.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        groupHeader.textColor = WindowConstants.Colors.groupHeaderTextColor
        headerStack.addArrangedSubview(groupHeader)

        if let groupDesc = groupDescriptions[groupName], !groupDesc.isEmpty {
            let descLabel = NSTextField()
            descLabel.stringValue = groupDesc
            descLabel.font = NSFont.systemFont(ofSize: 10)
            descLabel.textColor = WindowConstants.Colors.groupDescriptionTextColor
            descLabel.backgroundColor = .clear
            descLabel.isBordered = false
            descLabel.isEditable = false
            descLabel.isSelectable = false
            descLabel.lineBreakMode = .byWordWrapping
            descLabel.usesSingleLineMode = false
            descLabel.maximumNumberOfLines = 0
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            headerStack.addArrangedSubview(descLabel)
            NSLayoutConstraint.activate([
                descLabel.widthAnchor.constraint(equalToConstant: totalInnerWidth)
            ])
        }

        container.addSubview(headerStack)

        // Content area
        let contentArea = FlippedView()
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        for item in categoryViews {
            contentArea.addSubview(item.view)
        }
        container.addSubview(contentArea)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: fixedWidth),

            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: containerPadding),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: containerPadding),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -containerPadding),

            contentArea.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            contentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: containerPadding),
            contentArea.widthAnchor.constraint(equalToConstant: totalInnerWidth),
            contentArea.heightAnchor.constraint(equalToConstant: innerContentHeight),
            contentArea.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -containerPadding),
        ])

        return container
    }

    private func wrapInBorderedContainer(_ innerView: NSView, padding: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = WindowConstants.Colors.containerBackgroundColor.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = WindowConstants.Colors.containerBorderColor.cgColor

        innerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(innerView)

        NSLayoutConstraint.activate([
            innerView.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            innerView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            innerView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            innerView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        return container
    }

    private func measureTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let lm = NSLayoutManager()
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        lm.ensureLayout(for: container)
        return ceil(lm.usedRect(for: container).height)
    }

    private func makeTextView(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment, width: CGFloat) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        tv.string = text
        tv.font = font
        tv.textColor = color
        tv.alignment = alignment
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }

    private func createShortcutRow(_ item: ShortcutItem, availableWidth: CGFloat = 200) -> NSView {
        let contentWidth = max(120, availableWidth - 4)
        let leftColumnWidth = max(50, floor((contentWidth - shortcutRowGap) * 0.45))
        let rightColumnWidth = max(50, contentWidth - leftColumnWidth - shortcutRowGap)

        let leftFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let rightFont = NSFont.systemFont(ofSize: 11)

        let leftHeight = measureTextHeight(item.shortcut, font: leftFont, width: leftColumnWidth)
        let rightHeight = measureTextHeight(item.action, font: rightFont, width: rightColumnWidth)
        let rowHeight = max(leftHeight, rightHeight)

        let leftView = makeTextView(item.shortcut, font: leftFont, color: WindowConstants.Colors.keyTextColor, alignment: .left, width: leftColumnWidth)
        let rightView = makeTextView(item.action, font: rightFont, color: WindowConstants.Colors.actionTextColor, alignment: .right, width: rightColumnWidth)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(leftView)
        row.addSubview(rightView)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: contentWidth),
            row.heightAnchor.constraint(equalToConstant: rowHeight),

            leftView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            leftView.topAnchor.constraint(equalTo: row.topAnchor),
            leftView.widthAnchor.constraint(equalToConstant: leftColumnWidth),
            leftView.heightAnchor.constraint(equalToConstant: leftHeight),

            rightView.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            rightView.topAnchor.constraint(equalTo: row.topAnchor),
            rightView.widthAnchor.constraint(equalToConstant: rightColumnWidth),
            rightView.heightAnchor.constraint(equalToConstant: rightHeight),
        ])

        return row
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
        sender.stringValue = ""
        filterShortcuts(with: "")
        isSearchFocused = false
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if obj.object as? NSSearchField == searchField {
            isSearchFocused = true
            searchField.layer?.borderColor = NSColor.controlAccentColor.cgColor
            searchField.layer?.borderWidth = 1.5
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSSearchField == searchField {
            isSearchFocused = false
            searchField.layer?.borderColor = NSColor.separatorColor.cgColor
            searchField.layer?.borderWidth = 1
        }
    }
}
