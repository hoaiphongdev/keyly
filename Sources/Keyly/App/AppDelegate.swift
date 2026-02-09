import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var superKeyHoldTimer: Timer?
    private var shortcutsWindow: ShortcutsWindow?
    private var isSuperKeyPressed = false
    private var holdCancelled = false
    private var superKeyPressCount = 0
    private var lastSuperKeyPressTime: TimeInterval = 0

    private let shortcutExtractor = ShortcutExtractor()
    private let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    private var settings: KeylySettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        requestAccessibilityPermissions()
        setupConfigManager()

        // MARK: - Update feature temporarily disabled
        // _ = UpdateManager.shared
        // DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        //     UpdateManager.shared.checkForUpdatesInBackground()
        // }

        if isDevMode {
            setupDevMode()
        }
        startMonitoringKeyboard()
    }

    private func setupConfigManager() {
        settings = SettingsManager.shared.getSettings()

        ConfigManager.shared.loadAllSheets()
        ConfigManager.shared.startWatching()
        ConfigManager.shared.onConfigReloaded = { [weak self] in
            if self?.shortcutsWindow?.window?.isVisible == true {
                self?.showShortcutsForCurrentApp()
            }
        }
        ConfigManager.shared.onSettingsReloaded = { [weak self] in
            self?.settings = SettingsManager.shared.getSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConfigManager.shared.stopWatching()
    }

    private func setupDevMode() {
        print("[Keyly] Dev mode enabled - use configured key combination to show shortcuts")

        let currentSettings = settings ?? SettingsManager.shared.getSettings()
        let superKey = currentSettings.superKey

        print("[Keyly] === Super Key Configuration ===")
        print("[Keyly] Super key: '\(superKey.key)'")
        print("[Keyly] Components: \(superKey.keyComponents)")
        print("[Keyly] Modifiers: \(superKey.modifiers)")
        print("[Keyly] Main key: \(superKey.mainKey ?? "none")")
        print("[Keyly] Has modifiers: \(superKey.hasModifiers)")
        print("[Keyly] Trigger type: \(superKey.triggerType)")

        switch superKey.triggerType {
        case "hold":
            print("[Keyly] Hold duration: \(currentSettings.hold.duration) seconds")
        case "press":
            print("[Keyly] Press count: \(currentSettings.press.count)")
        default:
            print("[Keyly] Unknown trigger type, using hold with duration: \(currentSettings.hold.duration) seconds")
        }
        print("[Keyly] ================================")
    }

    @objc private func activeAppDidChange(_ notification: Notification) {
    }

    private func showShortcutsForCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }

        let shortcuts = shortcutExtractor.getShortcuts(for: app)
        let categoryDescriptions = shortcutExtractor.getCategoryDescriptions(for: app)

        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindow()
        }

        shortcutsWindow?.displayShortcuts(shortcuts, appName: app.localizedName ?? "Unknown", categoryDescriptions: categoryDescriptions)
        shortcutsWindow?.showWindow(nil)
        shortcutsWindow?.window?.orderFrontRegardless()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "k.square.fill", accessibilityDescription: "Keyly")
            button.action = #selector(statusBarClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Keyly", action: #selector(showAbout), keyEquivalent: ""))

        // MARK: - Update feature temporarily disabled
        // let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        // checkUpdatesItem.target = self
        // menu.addItem(checkUpdatesItem)

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
            if event.keyCode == AppConstants.escapeKeyCode && self?.shortcutsWindow?.window?.isVisible == true {
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

    private func cancelHoldIfNeeded() {
        holdCancelled = true
        stopHoldTimer()
    }

    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        let modifierKeyCodes: Set<UInt16> = [
            AppConstants.KeyCodes.cmdLeft, AppConstants.KeyCodes.cmdRight,
            AppConstants.KeyCodes.ctrlLeft, AppConstants.KeyCodes.ctrlRight,
            AppConstants.KeyCodes.altLeft, AppConstants.KeyCodes.altRight,
            AppConstants.KeyCodes.shiftLeft, AppConstants.KeyCodes.shiftRight,
            AppConstants.KeyCodes.fn
        ]
        return modifierKeyCodes.contains(keyCode)
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 17: "t", 16: "y", 32: "u", 34: "i", 31: "o",
            35: "p", 33: "[", 30: "]", 36: "return", 38: "l", 40: "k", 37: ";", 41: "'", 42: "\\",
            43: ",", 47: ".", 44: "/", 49: "space", 39: "`",

            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",

            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
            101: "f9", 109: "f10", 103: "f11", 111: "f12",

            54: "cmd", 55: "cmd", 59: "ctrl", 62: "ctrl", 58: "alt", 61: "alt", 56: "shift", 60: "shift",
            63: "fn",

            126: "up", 125: "down", 123: "left", 124: "right",

            51: "delete", 117: "forward_delete", 53: "escape", 48: "tab", 76: "enter",
            116: "page_up", 121: "page_down", 115: "home", 119: "end"
        ]

        return keyMap[keyCode] ?? "key_\(keyCode)"
    }

    private func checkModifierFlags(_ flags: NSEvent.ModifierFlags, matches modifiers: [String]) -> Bool {
        for modifier in modifiers {
            let hasModifier: Bool
            switch modifier {
            case "cmd", "meta": hasModifier = flags.contains(.command)
            case "ctrl": hasModifier = flags.contains(.control)
            case "alt": hasModifier = flags.contains(.option)
            case "shift": hasModifier = flags.contains(.shift)
            case "fn": hasModifier = flags.contains(.function)
            default: hasModifier = false
            }

            if isDevMode {
                print("[Keyly] Checking modifier '\(modifier)': hasModifier=\(hasModifier)")
            }

            if !hasModifier {
                if isDevMode {
                    print("[Keyly] Missing required modifier: \(modifier)")
                }
                return false
            }
        }
        return true
    }

    private func isSuperKeyComboPressed(_ flags: NSEvent.ModifierFlags, keyCode: UInt16? = nil) -> Bool {
        guard let settings = settings else { return flags.contains(.command) }

        let superKey = settings.superKey

        if !checkModifierFlags(flags, matches: superKey.modifiers) {
            return false
        }

        if let mainKey = superKey.mainKey, let keyCode = keyCode {
            let pressedKey = keyCodeToString(keyCode)
            return pressedKey == mainKey
        }

        if superKey.mainKey == nil {
            return checkModifierFlags(flags, matches: superKey.modifiers)
        }

        return true
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard let settings = settings else { return }

        let superKey = settings.superKey

        if isSuperKeyComboPressed(event.modifierFlags, keyCode: event.keyCode) {
            if !isSuperKeyPressed {
                isSuperKeyPressed = true
                holdCancelled = false

                if isDevMode {
                    let keyString = keyCodeToString(event.keyCode)
                    print("[Keyly] Super key combo detected: \(superKey.key) (keyCode: \(event.keyCode) = \(keyString))")
                    print("[Keyly] Trigger type: \(superKey.triggerType)")
                }

                let currentTime = CACurrentMediaTime()

                switch superKey.triggerType {
                case "hold":
                    if isDevMode {
                        print("[Keyly] Starting hold timer for \(settings.hold.duration) seconds")
                    }
                    startHoldTimer()

                case "press":
                    if currentTime - lastSuperKeyPressTime < AppConstants.doubleClickTimeInterval {
                        superKeyPressCount += 1
                    } else {
                        superKeyPressCount = 1
                    }
                    lastSuperKeyPressTime = currentTime

                    if isDevMode {
                        print("[Keyly] Press count: \(superKeyPressCount)/\(settings.press.count)")
                    }

                    if superKeyPressCount >= settings.press.count {
                        if isDevMode {
                            print("[Keyly] Press count reached, showing shortcuts")
                        }
                        showShortcuts()
                        superKeyPressCount = 0
                    }

                default:
                    if isDevMode {
                        print("[Keyly] Unknown trigger type, defaulting to hold")
                    }
                    startHoldTimer()
                }
            }
        } else if isSuperKeyPressed {
            cancelHoldIfNeeded()
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard let settings = settings else { return }

        let superKey = settings.superKey

        let wasComboPressed = isSuperKeyComboPressed(event.modifierFlags, keyCode: event.keyCode)
        let isStillPressed = isSuperKeyComboPressed(event.modifierFlags)

        if isSuperKeyPressed && (!wasComboPressed || !isStillPressed) {
            isSuperKeyPressed = false

            if isDevMode {
                print("[Keyly] Super key released")
            }

            switch superKey.triggerType {
            case "hold":
                if isDevMode {
                    print("[Keyly] Hold released - stopping timer")
                }
                stopHoldTimer()

            default:
                break
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let settings = settings else { return }

        let flags = event.modifierFlags
        let superKey = settings.superKey

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

        // Only handle modifier-only combinations here
        if superKey.mainKey == nil && superKey.hasModifiers {
            let isSuperKeyDown = isSuperKeyComboPressed(flags)

            if isDevMode {
                print("[Keyly] Checking modifier-only combo: expected=\(superKey.modifiers), isSuperKeyDown=\(isSuperKeyDown)")
            }

            if isSuperKeyDown && !isSuperKeyPressed {
                isSuperKeyPressed = true
                holdCancelled = false

                if isDevMode {
                    print("[Keyly] Modifier-only super key combo detected: \(superKey.key)")
                }

                let currentTime = CACurrentMediaTime()

                switch superKey.triggerType {
                case "hold":
                    if isDevMode {
                        print("[Keyly] Starting modifier hold timer")
                    }
                    startHoldTimer()

                case "press":
                    if currentTime - lastSuperKeyPressTime < AppConstants.doubleClickTimeInterval {
                        superKeyPressCount += 1
                    } else {
                        superKeyPressCount = 1
                    }
                    lastSuperKeyPressTime = currentTime

                    if isDevMode {
                        print("[Keyly] Modifier press count: \(superKeyPressCount)/\(settings.press.count)")
                    }

                    if superKeyPressCount >= settings.press.count {
                        if isDevMode {
                            print("[Keyly] Modifier press count reached, showing shortcuts")
                        }
                        showShortcuts()
                        superKeyPressCount = 0
                    }

                default:
                    if isDevMode {
                        print("[Keyly] Unknown modifier trigger type, defaulting to hold")
                    }
                    startHoldTimer()
                }

            } else if !isSuperKeyDown && isSuperKeyPressed {
                isSuperKeyPressed = false

                switch superKey.triggerType {
                case "hold":
                    stopHoldTimer()

                default:
                    break
                }
            }
        }
    }

    private func startHoldTimer() {
        superKeyHoldTimer?.invalidate()

        let holdDuration = settings?.hold.duration ?? AppConstants.defaultHoldDuration

        superKeyHoldTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
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

        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindow()
        }

        shortcutsWindow?.displayShortcuts(shortcuts, appName: frontmostApp.localizedName ?? "Unknown App", categoryDescriptions: categoryDescriptions)
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
        if UpdateManager.shared.canCheckForUpdates {
            UpdateManager.shared.checkForUpdates()
        } else {
            let alert = NSAlert()
            alert.messageText = "Check for Updates"
            alert.informativeText = isDevMode
                ? "Update checking is disabled in dev mode."
                : "You're running the latest version!"
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
