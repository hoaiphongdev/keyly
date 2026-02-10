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
    private var groupSizes: [String: Int] = [:]
    private var updateButton: NSButton?
    private var spinner: NSProgressIndicator?
    private var clickOutsideMonitor: Any?
    private var localClickMonitor: Any?
    private var searchField: NSSearchField!
    private var searchContainer: NSView!
    private var isSearchFocused = false
    private var keyboardMonitor: Any?
    private var searchTimer: Timer?

    private let columnWidth = WindowConstants.columnWidth
    private let columnSpacing = WindowConstants.columnSpacing
    private let rowSpacing = WindowConstants.rowSpacing
    private let padding = WindowConstants.padding
    private let footerHeight = WindowConstants.footerHeight
    private let bannerHeight = WindowConstants.bannerHeight

    convenience init() {
        // Start with minimum width, will be resized dynamically based on content
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

    func displayShortcuts(_ shortcuts: [ShortcutItem], appName: String, categoryDescriptions: [String: String] = [:], groupDescriptions: [String: String] = [:], groupSizes: [String: Int] = [:]) {
        self.allShortcuts = shortcuts
        self.shortcuts = shortcuts
        self.categoryDescriptions = categoryDescriptions
        self.groupDescriptions = groupDescriptions
        self.groupSizes = groupSizes

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
        label.textColor = .white

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

        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.autoresizingMask = [.width, .height]

        // Removed gradient overlay to eliminate flash animation

        containerView = visualEffect
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
        } else {
            let lowercaseSearch = searchText.lowercased()
            shortcuts = allShortcuts.filter { shortcut in
                matchesSearch(shortcut: shortcut, searchText: lowercaseSearch)
            }
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
        settingsButton.contentTintColor = NSColor.white.withAlphaComponent(0.6)
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
        escLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        escLabel.alignment = .left

        containerView.addSubview(escLabel)

        NSLayoutConstraint.activate([
            escLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            escLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
    }

    private func setupClickOutsideMonitoring() {
        // Global monitor for clicks outside the app
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

        // Local monitor for clicks in other windows of the same app
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.window, window.isVisible else { return event }

            // If click is in a different window, close our panel
            if let eventWindow = event.window, eventWindow != window {
                DispatchQueue.main.async {
                    self.close()
                }
                return event // Don't consume the event
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

        let groupedByGroup = Dictionary(grouping: shortcuts) { shortcut in
            return shortcut.group?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? shortcut.group! : "default"
        }

        var totalColumns = 0
        for (groupName, groupShortcuts) in groupedByGroup {
            if groupName != "default" {
                totalColumns += 1
            } else {
                let categories = Set(groupShortcuts.map { $0.category })
                totalColumns += categories.count
            }
        }

        let screenSize = NSScreen.main?.visibleFrame.size ?? WindowConstants.defaultScreenSize
        let settings = SettingsManager.shared.getSettings()
        let maxScreenWidth = screenSize.width * CGFloat(settings.ui.screenWidthRatio)
        let maxPossibleColumns = max(1, Int(maxScreenWidth / (columnWidth + columnSpacing)))

        let numColumns = min(totalColumns, maxPossibleColumns)

        let actualTotalWidth = CGFloat(numColumns) * columnWidth + CGFloat(max(0, numColumns - 1)) * columnSpacing
        let newWindowWidth = actualTotalWidth + padding * 2

        window.setContentSize(NSSize(width: newWindowWidth, height: window.frame.height))

        let availableWidth = newWindowWidth - padding * 2

        let sortedGroups = groupedByGroup.keys.sorted { group1, group2 in
            if group1 == "default" { return false }
            if group2 == "default" { return true }
            return group1 < group2
        }

        var currentColumn = 0
        var columnYPositions = [CGFloat](repeating: 0, count: numColumns)

        let gridOffset = (availableWidth - actualTotalWidth) / 2

        for groupName in sortedGroups {
            guard let groupShortcuts = groupedByGroup[groupName] else { continue }

            if groupName != "default" {
                let requestedSize = groupSizes[groupName] ?? 1
                let groupSize = min(max(1, requestedSize), numColumns)

                var bestStartColumn = 0
                var lowestMaxHeight = CGFloat.greatestFiniteMagnitude

                for startCol in 0...(numColumns - groupSize) {
                    let maxHeightInRange = (startCol..<(startCol + groupSize)).map { columnYPositions[$0] }.max() ?? 0
                    if maxHeightInRange < lowestMaxHeight {
                        lowestMaxHeight = maxHeightInRange
                        bestStartColumn = startCol
                    }
                }

                let groupWidth = CGFloat(groupSize) * columnWidth + CGFloat(max(0, groupSize - 1)) * columnSpacing
                let groupView = createGroupContainer(groupName: groupName, shortcuts: groupShortcuts, containerWidth: groupWidth)
                groupView.layoutSubtreeIfNeeded()

                let height = groupView.fittingSize.height
                let x = gridOffset + CGFloat(bestStartColumn) * (columnWidth + columnSpacing)
                let y = lowestMaxHeight

                groupView.frame = NSRect(x: x, y: y, width: groupWidth, height: height)
                gridContainer.addSubview(groupView)

                for col in bestStartColumn..<(bestStartColumn + groupSize) {
                    columnYPositions[col] = y + height + rowSpacing
                }

                currentColumn = (bestStartColumn + groupSize) % numColumns
            } else {
                let grouped = Dictionary(grouping: groupShortcuts) { $0.category }
                let sortedCategories = grouped.keys.sorted()

                for category in sortedCategories {
                    guard let items = grouped[category] else { continue }
                    let description = categoryDescriptions[category]
                    let view = createCategoryColumn(title: category, description: description, items: items)
                    view.layoutSubtreeIfNeeded()

                    let height = view.fittingSize.height
                    let x = gridOffset + CGFloat(currentColumn) * (columnWidth + columnSpacing)
                    let y = columnYPositions[currentColumn]

                    view.frame = NSRect(x: x, y: y, width: columnWidth, height: height)
                    gridContainer.addSubview(view)

                    columnYPositions[currentColumn] += height + rowSpacing
                    currentColumn = (currentColumn + 1) % numColumns
                }
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

        let newHeight = max(calculatedHeight, WindowConstants.minWindowHeight)

        window.setContentSize(NSSize(width: window.frame.width, height: newHeight))
    }

    private func createCategoryColumn(title: String, description: String?, items: [ShortcutItem]) -> NSView {
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
        header.textColor = .white
        column.addArrangedSubview(header)

        if let desc = description, !desc.isEmpty {
            let descLabel = NSTextField()
            descLabel.stringValue = desc
            descLabel.font = NSFont.systemFont(ofSize: 10)
            descLabel.textColor = NSColor.white.withAlphaComponent(0.5)
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

    private func createGroupContainer(groupName: String, shortcuts: [ShortcutItem], containerWidth: CGFloat = 0) -> NSView {
        guard !groupName.isEmpty && !shortcuts.isEmpty else {
            print("[Keyly] Warning: Empty group name or shortcuts for group container")
            return NSView()
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true

        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let groupHeader = NSTextField(labelWithString: groupName)
        groupHeader.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        groupHeader.textColor = .white
        stackView.addArrangedSubview(groupHeader)

        if let groupDesc = groupDescriptions[groupName], !groupDesc.isEmpty {
            let descLabel = NSTextField()
            descLabel.stringValue = groupDesc
            descLabel.font = NSFont.systemFont(ofSize: 10)
            descLabel.textColor = NSColor.white.withAlphaComponent(0.6)
            descLabel.backgroundColor = .clear
            descLabel.isBordered = false
            descLabel.isEditable = false
            descLabel.isSelectable = false
            descLabel.lineBreakMode = .byWordWrapping
            descLabel.usesSingleLineMode = false
            descLabel.maximumNumberOfLines = 0
            descLabel.translatesAutoresizingMaskIntoConstraints = false

            stackView.addArrangedSubview(descLabel)

            NSLayoutConstraint.activate([
                descLabel.widthAnchor.constraint(equalToConstant: max(columnWidth - 16, containerWidth - 16)) // Use actual container width
            ])
        }

        let grouped = Dictionary(grouping: shortcuts) { $0.category }
        let sortedCategories = grouped.keys.sorted()

        for category in sortedCategories {
            guard let items = grouped[category] else { continue }

            if sortedCategories.count > 1 {
                let categoryHeader = NSTextField(labelWithString: category)
                categoryHeader.font = NSFont.systemFont(ofSize: 11, weight: .medium)
                categoryHeader.textColor = NSColor.white.withAlphaComponent(0.8)
                stackView.addArrangedSubview(categoryHeader)

                if let desc = categoryDescriptions[category], !desc.isEmpty {
                    let descLabel = NSTextField()
                    descLabel.stringValue = desc
                    descLabel.font = NSFont.systemFont(ofSize: 9)
                    descLabel.textColor = NSColor.white.withAlphaComponent(0.5)
                    descLabel.backgroundColor = .clear
                    descLabel.isBordered = false
                    descLabel.isEditable = false
                    descLabel.isSelectable = false
                    descLabel.lineBreakMode = .byWordWrapping
                    descLabel.usesSingleLineMode = false
                    descLabel.maximumNumberOfLines = 0
                    descLabel.translatesAutoresizingMaskIntoConstraints = false
                    
                    stackView.addArrangedSubview(descLabel)
                    
                    NSLayoutConstraint.activate([
                        descLabel.widthAnchor.constraint(equalToConstant: max(columnWidth - 16, containerWidth - 16))
                    ])
                }
            }

            for item in items {
                let row = createShortcutRow(item, availableWidth: max(columnWidth, containerWidth))
                stackView.addArrangedSubview(row)
            }
        }

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: containerWidth > 0 ? containerWidth : columnWidth),
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func createShortcutRow(_ item: ShortcutItem, availableWidth: CGFloat = 200) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let (modifiers, key) = parseShortcut(item.shortcut)

        let modifiersLabel = NSTextField(labelWithString: modifiers)
        modifiersLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        modifiersLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        modifiersLabel.alignment = .right
        modifiersLabel.translatesAutoresizingMaskIntoConstraints = false

        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        keyLabel.textColor = NSColor(calibratedRed: 0.4, green: 0.85, blue: 1.0, alpha: 1.0)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        let actionLabel = NSTextField(wrappingLabelWithString: item.action)
        actionLabel.font = NSFont.systemFont(ofSize: 11)
        actionLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        actionLabel.maximumNumberOfLines = 2
        actionLabel.preferredMaxLayoutWidth = availableWidth - 95

        row.addSubview(modifiersLabel)
        row.addSubview(keyLabel)
        row.addSubview(actionLabel)

        let modifiersWidth: CGFloat = 40
        let keyWidth: CGFloat = 45

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: availableWidth - 4),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),

            modifiersLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            modifiersLabel.widthAnchor.constraint(equalToConstant: modifiersWidth),
            modifiersLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),

            keyLabel.leadingAnchor.constraint(equalTo: modifiersLabel.trailingAnchor, constant: 2),
            keyLabel.widthAnchor.constraint(equalToConstant: keyWidth),
            keyLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),

            actionLabel.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 1),
            actionLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            actionLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            actionLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2)
        ])

        return row
    }

    private func parseShortcut(_ shortcut: String) -> (modifiers: String, key: String) {
        let modifierChars = Modifier.allCharacters
        var modifiers = ""
        var key = ""

        for char in shortcut {
            if modifierChars.contains(char) {
                modifiers.append(char)
            } else {
                key.append(char)
            }
        }

        return (modifiers, key)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}


// MARK: - NSWindowDelegate
extension ShortcutsWindow {
    func windowDidResignKey(_ notification: Notification) {
        // Close when window loses focus (user clicked elsewhere)
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
            // Update border color when focused
            searchField.layer?.borderColor = NSColor.controlAccentColor.cgColor
            searchField.layer?.borderWidth = 1.5
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSSearchField == searchField {
            isSearchFocused = false
            // Reset border color when unfocused
            searchField.layer?.borderColor = NSColor.separatorColor.cgColor
            searchField.layer?.borderWidth = 1
        }
    }
}
