import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var superKeyHoldTimer: Timer?
    private var shortcutsWindow: ShortcutsWindow?
    private var isSuperKeyPressed = false
    private var holdCancelled = false
    private var waitingForModifierRelease = false
    private var superKeyPressCount = 0
    private var lastSuperKeyPressTime: TimeInterval = 0
    private var isCapsLockOn = NSEvent.modifierFlags.contains(.capsLock)

    private let shortcutExtractor = ShortcutExtractor()
    private let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    private var trigger = KeylySettings.defaults.trigger

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        requestAccessibilityPermissions()
        setupConfigManager()

        setupUpdater()

        if isDevMode {
            setupDevMode()
        }
        startMonitoringKeyboard()
    }

    private func setupConfigManager() {
        ConfigManager.shared.loadInitial()
        trigger = ConfigManager.shared.settings.trigger
        ConfigManager.shared.startWatching()
        ConfigManager.shared.onConfigReloaded = { [weak self] in
            if self?.shortcutsWindow?.window?.isVisible == true {
                self?.showShortcutsForCurrentApp()
            }
        }
        ConfigManager.shared.onSettingsReloaded = { [weak self] in
            guard let self else { return }
            self.trigger = ConfigManager.shared.settings.trigger
            self.resetTriggerState()
            if self.isDevMode { self.printTrigger() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConfigManager.shared.stopWatching()
    }

    private func setupDevMode() {
        print("[Keyly] Dev mode enabled - use configured key combination to show shortcuts")
        printTrigger()
    }

    private func printTrigger() {
        switch trigger.kind {
        case .press(let count):
            print("[Keyly] Trigger: \(trigger.label) pressed \(count)×")
        case .hold(let seconds):
            print("[Keyly] Trigger: \(trigger.label) held \(seconds)s")
        }
    }

    @objc private func activeAppDidChange(_ notification: Notification) {
    }

    private func showShortcutsForCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }

        let shortcuts = shortcutExtractor.getShortcuts(for: app)
        let categoryDescriptions = shortcutExtractor.getCategoryDescriptions(for: app)
        let groupDescriptions = shortcutExtractor.getGroupDescriptions(for: app)

        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindow()
        }

        shortcutsWindow?.displayShortcuts(shortcuts, appName: app.localizedName ?? "Unknown", appIcon: app.icon, categoryDescriptions: categoryDescriptions, groupDescriptions: groupDescriptions)
        shortcutsWindow?.showWindow(nil)
        shortcutsWindow?.window?.orderFrontRegardless()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = statusBarIcon()
            button.action = #selector(statusBarClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Keyly", action: #selector(showAbout), keyEquivalent: ""))

        let updateItem = NSMenuItem(title: "", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        updateMenuItem = updateItem

        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupUpdater() {
        Updater.shared.onPendingUpdateChanged = { [weak self] version in
            self?.showPendingUpdate(version)
        }
        Updater.shared.start()
    }

    private func showPendingUpdate(_ version: String?) {
        updateMenuItem?.title = "Update to \(version ?? "")…"
        updateMenuItem?.isHidden = version == nil
        statusItem?.button?.image = version == nil ? statusBarIcon() : statusBarIconWithBadge()
    }

    private func statusBarIcon() -> NSImage? {
        NSImage(systemSymbolName: "k.square.fill", accessibilityDescription: "Keyly")
    }

    private func statusBarIconWithBadge() -> NSImage? {
        guard let base = statusBarIcon() else { return nil }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            let dot = size.width * 0.42
            let dotRect = NSRect(x: rect.maxX - dot, y: rect.maxY - dot, width: dot, height: dot)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.accessibilityDescription = "Keyly — update available"
        return image
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
            if event.keyCode == AppConstants.escapeKeyCode && self?.shortcutsWindow?.window?.isVisible == true {
                // First ESC clears an active search, the next one closes
                if self?.shortcutsWindow?.clearSearch() == true {
                    return nil
                }
                if self?.isDevMode == true {
                    print("[Keyly] ESC key pressed, closing shortcuts window")
                }
                self?.hideShortcuts()
                return nil
            }
            self?.handleKeyDown(event)
            return event
        }

        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == AppConstants.escapeKeyCode && self?.shortcutsWindow?.window?.isVisible == true {
                if self?.isDevMode == true {
                    print("[Keyly] ESC key pressed (global), closing shortcuts window")
                }
                self?.hideShortcuts()
                return
            }
            self?.handleKeyDown(event)
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
            return event
        }

        NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags

        if isDevMode {
            let flagsDebug = [
                flags.contains(.command) ? "cmd" : nil,
                flags.contains(.control) ? "ctrl" : nil,
                flags.contains(.option) ? "alt" : nil,
                flags.contains(.shift) ? "shift" : nil,
                flags.contains(.function) ? "fn" : nil,
                flags.contains(.capsLock) ? "caps" : nil
            ].compactMap { $0 }
            print("[Keyly] Flags changed: \(flagsDebug)")
        }

        if trigger.isCapsLock {
            guard event.keyCode == AppConstants.KeyCodes.capsLock else { return }

            // Count only real toggles so a release event (if any) is not a second tap
            let capsLockOn = flags.contains(.capsLock)
            guard capsLockOn != isCapsLockOn else { return }
            isCapsLockOn = capsLockOn
            registerPress()
            return
        }

        // Only handle modifier-only combinations here
        if trigger.isModifierOnly {
            let pressed = trigger.relevantModifiers(flags)
            if pressed.isEmpty { waitingForModifierRelease = false }

            if !pressed.subtracting(trigger.modifiers).isEmpty {
                interruptModifierTrigger(flags)
            } else if waitingForModifierRelease {
                return
            } else if pressed == trigger.modifiers && !isSuperKeyPressed {
                triggerWentDown()
            } else if pressed != trigger.modifiers && isSuperKeyPressed {
                triggerWentUp()
            }
        } else if isSuperKeyPressed && !trigger.matchesModifiers(flags) {
            triggerWentUp()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if trigger.keyCode != nil && trigger.matchesKey(event.keyCode, flags: event.modifierFlags) {
            guard !event.isARepeat else { return }
            if isSuperKeyPressed { triggerWentUp() }
            triggerWentDown()
            return
        }

        if trigger.isModifierOnly {
            interruptModifierTrigger(event.modifierFlags)
        } else {
            superKeyPressCount = 0
            if isSuperKeyPressed { cancelHold() }
        }
    }

    private func interruptModifierTrigger(_ flags: NSEvent.ModifierFlags) {
        superKeyPressCount = 0
        if isSuperKeyPressed {
            cancelHold()
            triggerWentUp()
        }
        if !trigger.relevantModifiers(flags).isEmpty {
            waitingForModifierRelease = true
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        if isSuperKeyPressed && event.keyCode == trigger.keyCode {
            triggerWentUp()
        }
    }

    private func triggerWentDown() {
        isSuperKeyPressed = true
        holdCancelled = false

        switch trigger.kind {
        case .hold(let seconds):
            startHoldTimer(seconds)
        case .press:
            registerPress()
        }
    }

    private func triggerWentUp() {
        isSuperKeyPressed = false
        stopHoldTimer()
    }

    private func registerPress() {
        guard case .press(let count) = trigger.kind else { return }

        let currentTime = CACurrentMediaTime()
        if currentTime - lastSuperKeyPressTime < AppConstants.doubleClickTimeInterval {
            superKeyPressCount += 1
        } else {
            superKeyPressCount = 1
        }
        lastSuperKeyPressTime = currentTime

        if isDevMode {
            print("[Keyly] Press count: \(superKeyPressCount)/\(count)")
        }

        if superKeyPressCount >= count {
            superKeyPressCount = 0
            // A cancelled hold from a previous key+key trigger must not block Caps Lock
            holdCancelled = false
            showShortcuts()
        }
    }

    private func cancelHold() {
        holdCancelled = true
        stopHoldTimer()
    }

    private func resetTriggerState() {
        stopHoldTimer()
        isSuperKeyPressed = false
        holdCancelled = false
        waitingForModifierRelease = false
        superKeyPressCount = 0
        // Caps Lock may have toggled while it was not the trigger
        isCapsLockOn = NSEvent.modifierFlags.contains(.capsLock)
    }

    private func startHoldTimer(_ seconds: Double) {
        superKeyHoldTimer?.invalidate()

        superKeyHoldTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.isSuperKeyPressed, !self.holdCancelled else {
                if self.isDevMode {
                    print("[Keyly] Hold timer fired but conditions not met (pressed: \(self.isSuperKeyPressed), cancelled: \(self.holdCancelled))")
                }
                return
            }
            if self.isDevMode {
                print("[Keyly] Hold timer completed, showing shortcuts")
            }
            self.showShortcuts()
        }
    }

    private func stopHoldTimer() {
        superKeyHoldTimer?.invalidate()
        superKeyHoldTimer = nil
    }

    private func showShortcuts() {
        guard isSuperKeyPressed || !holdCancelled else { return }
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }

        let shortcuts = shortcutExtractor.getShortcuts(for: frontmostApp)
        let categoryDescriptions = shortcutExtractor.getCategoryDescriptions(for: frontmostApp)
        let groupDescriptions = shortcutExtractor.getGroupDescriptions(for: frontmostApp)

        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindow()
        }

        shortcutsWindow?.displayShortcuts(shortcuts, appName: frontmostApp.localizedName ?? "Unknown App", appIcon: frontmostApp.icon, categoryDescriptions: categoryDescriptions, groupDescriptions: groupDescriptions)
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
        alert.informativeText = "A simple app to display keyboard shortcuts for the current application."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        if let logoURL = Bundle.module.url(forResource: "keyly", withExtension: "svg"),
           let logoImage = NSImage(contentsOf: logoURL) {
            logoImage.size = AppConstants.aboutIconSize
            alert.icon = logoImage
        }

        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func checkForUpdates() {
        if Updater.shared.canCheckForUpdates {
            Updater.shared.checkForUpdates()
        } else {
            let alert = NSAlert()
            alert.messageText = "Check for Updates"
            alert.informativeText = isDevMode
                ? "Update checking is disabled in dev mode."
                : "An update check is already in progress."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
