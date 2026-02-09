import Foundation

struct ShortcutItem {
    let category: String
    let action: String
    let shortcut: String
    let group: String?
    
    init(category: String, action: String, shortcut: String, group: String? = nil) {
        self.category = category
        self.action = action
        self.shortcut = shortcut
        self.group = group
    }
}
