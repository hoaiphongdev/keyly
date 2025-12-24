import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var commandKeyHoldTimer: Timer?
    private var shortcutsWindow: ShortcutsWindow?
    private var isCommandKeyPressed = false
    private var holdCancelled = false
    
    private let shortcutExtractor = ShortcutExtractor()
    private let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        requestAccessibilityPermissions()
        setupConfigManager()
        
        if isDevMode {
            setupDevMode()
        } else {
            startMonitoringKeyboard()
        }
    }
    
    private func setupConfigManager() {
        ConfigManager.shared.loadAllSheets()
        ConfigManager.shared.startWatching()
        ConfigManager.shared.onConfigReloaded = { [weak self] in
            if self?.shortcutsWindow?.window?.isVisible == true {
                self?.showShortcutsForCurrentApp()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ConfigManager.shared.stopWatching()
    }
    
    private func setupDevMode() {
        showShortcutsForCurrentApp()
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func activeAppDidChange(_ notification: Notification) {
        guard isDevMode else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showShortcutsForCurrentApp()
        }
    }
    
    private func showShortcutsForCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        
        let shortcuts = shortcutExtractor.getShortcuts(for: app)
        
        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindow()
        }
        
        shortcutsWindow?.displayShortcuts(shortcuts, appName: app.localizedName ?? "Unknown")
        shortcutsWindow?.showWindow(nil)
        shortcutsWindow?.window?.orderFrontRegardless()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Keyly")
            button.action = #selector(statusBarClicked)
            button.target = self
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Keyly", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("Accessibility permissions not granted. Please enable in System Preferences.")
        }
    }
    
    private func startMonitoringKeyboard() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) {
                self?.cancelHoldIfNeeded()
            }
            return event
        }
        
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) {
                self?.cancelHoldIfNeeded()
            }
        }
    }

    private func cancelHoldIfNeeded() {
        holdCancelled = true
        stopHoldTimer()
        hideShortcuts()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let isCommandDown = flags.contains(.command)
        
        let modifierMask: NSEvent.ModifierFlags = [.shift, .control, .option, .function, .capsLock]
        
        if isCommandKeyPressed && isCommandDown {
            if flags.intersection(modifierMask).isEmpty == false {
                cancelHoldIfNeeded()
                return
            }
        }
        
        if isCommandDown && !isCommandKeyPressed {
            isCommandKeyPressed = true
            holdCancelled = false
            startHoldTimer()
        } else if !isCommandDown && isCommandKeyPressed {
            isCommandKeyPressed = false
            stopHoldTimer()
            hideShortcuts()
        }
    }

    private func startHoldTimer() {
        commandKeyHoldTimer?.invalidate()
        commandKeyHoldTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.isCommandKeyPressed, !self.holdCancelled else { return }
            self.showShortcuts()
        }
    }
    
    private func stopHoldTimer() {
        commandKeyHoldTimer?.invalidate()
        commandKeyHoldTimer = nil
    }
    
    private func showShortcuts() {
        guard isCommandKeyPressed, !holdCancelled else { return }
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let shortcuts = shortcutExtractor.getShortcuts(for: frontmostApp)
        
        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindow()
        }
        
        shortcutsWindow?.displayShortcuts(shortcuts, appName: frontmostApp.localizedName ?? "Unknown App")
        shortcutsWindow?.showWindow(nil)
        shortcutsWindow?.window?.orderFrontRegardless()
    }
    
    private func hideShortcuts() {
        shortcutsWindow?.close()
    }
    
    @objc private func statusBarClicked() {}
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Keyly"
        alert.informativeText = "Hold ⌘ (Command) key for 1.7 seconds to show shortcuts\n\nVersion 1.1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        if let logoURL = Bundle.module.url(forResource: "keyly", withExtension: "svg"),
           let logoImage = NSImage(contentsOf: logoURL) {
            logoImage.size = NSSize(width: 64, height: 64)
            alert.icon = logoImage
        }
        
        alert.runModal()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
