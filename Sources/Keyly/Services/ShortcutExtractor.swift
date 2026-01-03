import Cocoa

final class ShortcutExtractor {
    
    func getShortcuts(for app: NSRunningApplication, mergeCustom: Bool = true) -> [ShortcutItem] {
        var shortcuts: [ShortcutItem] = []
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var menuBar: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBar)
        
        if result == .success, let menuBarElement = menuBar {
            shortcuts = extractShortcutsFromMenuBar(menuBarElement as! AXUIElement)
        }
        
        if mergeCustom, let bundleId = app.bundleIdentifier {
            let customSheets = ConfigManager.shared.sheets(for: bundleId)
            for sheet in customSheets {
                shortcuts = sheet.shortcuts + shortcuts
            }
        }
        
        if shortcuts.isEmpty {
            shortcuts = getDefaultShortcuts()
        }
        
        return shortcuts
    }
    
    private func extractShortcutsFromMenuBar(_ menuBar: AXUIElement) -> [ShortcutItem] {
        var shortcuts: [ShortcutItem] = []
        
        var children: AnyObject?
        AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &children)
        
        if let menuItems = children as? [AXUIElement] {
            for (index, menuItem) in menuItems.enumerated() {
                if index == 0 { 
                    continue 
                }
                shortcuts.append(contentsOf: extractShortcutsFromMenuItem(menuItem))
            }
        }
        
        return shortcuts
    }
    
    private func extractShortcutsFromMenuItem(_ menuItem: AXUIElement, parentTitle: String = "") -> [ShortcutItem] {
        var shortcuts: [ShortcutItem] = []
        
        var title: AnyObject?
        AXUIElementCopyAttributeValue(menuItem, kAXTitleAttribute as CFString, &title)
        
        var shortcut: AnyObject?
        AXUIElementCopyAttributeValue(menuItem, "AXMenuItemCmdChar" as CFString, &shortcut)
        
        var modifiers: AnyObject?
        AXUIElementCopyAttributeValue(menuItem, "AXMenuItemCmdModifiers" as CFString, &modifiers)
        
        if let itemTitle = title as? String, !itemTitle.isEmpty,
           let cmdChar = shortcut as? String, !cmdChar.isEmpty {
            let skipTitles = ["Start Dictation", "Dictation", "Emoji & Symbols"]
            let emojiTitles = ["Emoji & Symbols", "Emoji"]
            
            if skipTitles.contains(where: { itemTitle.contains($0) }) && !emojiTitles.contains(where: { itemTitle.contains($0) }) {
            } else if emojiTitles.contains(where: { itemTitle.contains($0) }) {
                let category = parentTitle.isEmpty ? "General" : parentTitle
                shortcuts.append(ShortcutItem(category: category, action: itemTitle, shortcut: "\(Modifier.control)\(Modifier.command)\(KeySymbol.space)"))
            } else if let cleanedKey = cleanShortcutKey(cmdChar) {
                if cleanedKey == "__SKIP__" {
                } else if cleanedKey == "__GLOBE__" {
                    let category = parentTitle.isEmpty ? "General" : parentTitle
                    shortcuts.append(ShortcutItem(category: category, action: itemTitle, shortcut: "\(Modifier.control)\(Modifier.command)\(KeySymbol.space)"))
                } else {
                    let modifierString = formatModifiers(modifiers as? Int ?? 0)
                    let fullShortcut = modifierString + cleanedKey
                    
                    let category = parentTitle.isEmpty ? "General" : parentTitle
                    shortcuts.append(ShortcutItem(category: category, action: itemTitle, shortcut: fullShortcut))
                }
            }
        }
        
        var children: AnyObject?
        AXUIElementCopyAttributeValue(menuItem, kAXChildrenAttribute as CFString, &children)
        
        if let subMenuItems = children as? [AXUIElement] {
            let currentTitle = (title as? String) ?? parentTitle
            for subItem in subMenuItems {
                shortcuts.append(contentsOf: extractShortcutsFromMenuItem(subItem, parentTitle: currentTitle))
            }
        }
        
        return shortcuts
    }
    
    private func formatModifiers(_ modifiers: Int) -> String {
        var result = ""
        if modifiers & ModifierFlag.control != 0 { result += Modifier.control }
        if modifiers & ModifierFlag.option != 0 { result += Modifier.option }
        if modifiers & ModifierFlag.shift != 0 { result += Modifier.shift }
        if modifiers & ModifierFlag.noCommand == 0 { result += Modifier.command }
        return result
    }
    
    private func cleanShortcutKey(_ key: String) -> String? {
        if let mapped = ShortcutMapping.systemKeyMap[key] {
            return mapped
        }
        
        for scalar in key.unicodeScalars {
            if scalar.value >= 0xE000 && scalar.value <= 0xF8FF {
                if ShortcutMapping.systemKeyMap[key] == nil {
                    return nil
                }
            }
        }
        
        return key
    }
    
    private func getDefaultShortcuts() -> [ShortcutItem] {
        let cmd = Modifier.command
        let shift = Modifier.shift
        return [
            ShortcutItem(category: "File", action: "New", shortcut: "\(cmd)N"),
            ShortcutItem(category: "File", action: "Open", shortcut: "\(cmd)O"),
            ShortcutItem(category: "File", action: "Save", shortcut: "\(cmd)S"),
            ShortcutItem(category: "File", action: "Close", shortcut: "\(cmd)W"),
            ShortcutItem(category: "Edit", action: "Copy", shortcut: "\(cmd)C"),
            ShortcutItem(category: "Edit", action: "Paste", shortcut: "\(cmd)V"),
            ShortcutItem(category: "Edit", action: "Cut", shortcut: "\(cmd)X"),
            ShortcutItem(category: "Edit", action: "Undo", shortcut: "\(cmd)Z"),
            ShortcutItem(category: "Edit", action: "Redo", shortcut: "\(shift)\(cmd)Z"),
            ShortcutItem(category: "View", action: "Zoom In", shortcut: "\(cmd)+"),
            ShortcutItem(category: "View", action: "Zoom Out", shortcut: "\(cmd)-"),
        ]
    }
}
