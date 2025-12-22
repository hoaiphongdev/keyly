import Cocoa

final class ShortcutsWindow: NSWindowController {
    private var containerView: NSView!
    private var scrollView: NSScrollView!
    private var gridContainer: NSView!
    private var settingsButton: NSButton!
    private var shortcuts: [ShortcutItem] = []
    
    private let columnWidth: CGFloat = 200
    private let columnSpacing: CGFloat = 20
    private let rowSpacing: CGFloat = 12
    private let padding: CGFloat = 16
    private let footerHeight: CGFloat = 32
    
    convenience init() {
        let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        let windowWidth = screenSize.width * 0.8
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 400),
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
        
        setupUI()
    }
    
    func displayShortcuts(_ shortcuts: [ShortcutItem], appName: String) {
        self.shortcuts = shortcuts
        rebuildContent()
        resizeWindowToFit()
        window?.center()
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
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -padding - footerHeight)
        ])
        
        setupSettingsButton()
    }
    
    private func setupSettingsButton() {
        settingsButton = NSButton(frame: .zero)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        settingsButton.contentTintColor = .tertiaryLabelColor
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
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Keyly", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        let location = NSPoint(x: settingsButton.frame.minX, y: settingsButton.frame.minY)
        menu.popUp(positioning: nil, at: location, in: containerView)
    }
    
    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
        
        guard let window = window else { return }
        
        let availableWidth = window.frame.width - padding * 2
        let numColumns = max(1, Int(availableWidth / (columnWidth + columnSpacing)))
        
        let grouped = Dictionary(grouping: shortcuts) { $0.category }
        let sortedCategories = grouped.keys.sorted()
        
        var categoryViews: [NSView] = []
        for category in sortedCategories {
            guard let items = grouped[category] else { continue }
            let view = createCategoryColumn(title: category, items: items)
            view.layoutSubtreeIfNeeded()
            categoryViews.append(view)
        }
        
        var currentColumn = 0
        var columnYPositions = [CGFloat](repeating: 0, count: numColumns)
        
        for view in categoryViews {
            let height = view.fittingSize.height
            let x = CGFloat(currentColumn) * (columnWidth + columnSpacing)
            let y = columnYPositions[currentColumn]
            
            view.frame = NSRect(x: x, y: y, width: columnWidth, height: height)
            gridContainer.addSubview(view)
            
            columnYPositions[currentColumn] += height + rowSpacing
            currentColumn = (currentColumn + 1) % numColumns
        }
        
        let maxHeight = columnYPositions.max() ?? 0
        let totalWidth = CGFloat(numColumns) * columnWidth + CGFloat(numColumns - 1) * columnSpacing
        
        gridContainer.frame = NSRect(x: 0, y: 0, width: totalWidth, height: maxHeight)
    }
    
    private func resizeWindowToFit() {
        guard let window = window else { return }
        
        let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        let maxHeight = screenSize.height * 0.75
        
        let contentHeight = gridContainer.frame.height + padding * 2
        let newHeight = min(contentHeight, maxHeight)
        
        let currentWidth = window.frame.width
        window.setContentSize(NSSize(width: currentWidth, height: max(200, newHeight)))
    }
    
    private func createCategoryColumn(title: String, items: [ShortcutItem]) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 5
        column.translatesAutoresizingMaskIntoConstraints = false
        
        let header = NSTextField(labelWithString: title)
        header.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        header.textColor = .labelColor
        column.addArrangedSubview(header)
        
        for item in items {
            let row = createShortcutRow(item)
            column.addArrangedSubview(row)
        }
        
        NSLayoutConstraint.activate([
            column.widthAnchor.constraint(equalToConstant: columnWidth)
        ])
        
        return column
    }
    
    private func createShortcutRow(_ item: ShortcutItem) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        
        let (modifiers, key) = parseShortcut(item.shortcut)
        
        let modifiersLabel = NSTextField(labelWithString: modifiers)
        modifiersLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        modifiersLabel.textColor = .tertiaryLabelColor
        modifiersLabel.alignment = .right
        modifiersLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        keyLabel.textColor = NSColor(calibratedRed: 0.45, green: 0.55, blue: 0.95, alpha: 1.0)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let actionLabel = NSTextField(wrappingLabelWithString: item.action)
        actionLabel.font = NSFont.systemFont(ofSize: 11)
        actionLabel.textColor = .secondaryLabelColor
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        actionLabel.maximumNumberOfLines = 2
        actionLabel.preferredMaxLayoutWidth = columnWidth - 95
        
        row.addSubview(modifiersLabel)
        row.addSubview(keyLabel)
        row.addSubview(actionLabel)
        
        let modifiersWidth: CGFloat = 40
        let keyWidth: CGFloat = 45
        
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: columnWidth - 4),
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
