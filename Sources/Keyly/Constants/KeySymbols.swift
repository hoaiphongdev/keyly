import Foundation

enum Modifier {
    static let command = "⌘"
    static let control = "⌃"
    static let option = "⌥"
    static let shift = "⇧"
    
    static let allCharacters: Set<Character> = ["⌘", "⌃", "⌥", "⇧"]
}

enum KeySymbol {
    static let enter = "⏎"
    static let tab = "⇥"
    static let escape = "esc"
    static let space = "Space"
    static let delete = "⌫"
    static let up = "↑"
    static let down = "↓"
    static let left = "←"
    static let right = "→"
}

enum ShortcutMapping {
    static let modifiersWithSeparator: [(patterns: [String], symbol: String)] = [
        (["CMD+", "COMMAND+", "CMD-", "COMMAND-"], Modifier.command),
        (["CTRL+", "CONTROL+", "CTRL-", "CONTROL-"], Modifier.control),
        (["OPT+", "OPTION+", "ALT+", "OPT-", "OPTION-", "ALT-"], Modifier.option),
        (["SHIFT+", "SHIFT-"], Modifier.shift),
    ]
    
    static let modifiersDirect: [(patterns: [String], symbol: String)] = [
        (["CMD", "COMMAND"], Modifier.command),
        (["CTRL", "CONTROL"], Modifier.control),
        (["OPT", "OPTION", "ALT"], Modifier.option),
        (["SHIFT"], Modifier.shift),
    ]
    
    static let specialKeys: [String: String] = [
        "ENTER": KeySymbol.enter,
        "RETURN": KeySymbol.enter,
        "TAB": KeySymbol.tab,
        "ESC": KeySymbol.escape,
        "ESCAPE": KeySymbol.escape,
        "SPACE": KeySymbol.space,
        "DELETE": KeySymbol.delete,
        "BACKSPACE": KeySymbol.delete,
        "UP": KeySymbol.up,
        "DOWN": KeySymbol.down,
        "LEFT": KeySymbol.left,
        "RIGHT": KeySymbol.right,
    ]
    
    static let unicodeToSymbol: [String: String] = [
        "\u{007F}": KeySymbol.delete,
        "\u{F700}": KeySymbol.up,
        "\u{F701}": KeySymbol.down,
        "\u{F702}": KeySymbol.left,
        "\u{F703}": KeySymbol.right,
        "\u{0009}": KeySymbol.tab,
        "\u{0003}": KeySymbol.enter,
        "\u{000D}": KeySymbol.enter,
    ]
    
    static let systemKeyMap: [String: String] = [
        "\u{F710}": "__GLOBE__",
        "\u{F711}": "__GLOBE__",
        "🌐": "__GLOBE__",
        "\u{F712}": "__SKIP__",
        "🎤": "__SKIP__",
        "\u{F713}": "⏻",
        "\u{F714}": "⏏",
        "\u{F715}": "🔇",
        "\u{F716}": "🔉",
        "\u{F717}": "🔊",
        "\u{F718}": "🔆",
        "\u{F719}": "🔅",
        "\u{F72C}": "⏯",
        "\u{F72D}": "⏮",
        "\u{F72E}": "⏭",
        "\u{001B}": KeySymbol.escape,
        "\u{F728}": "⌦",
        "\u{007F}": KeySymbol.delete,
        "\u{F729}": "↖",
        "\u{F72B}": "↘",
        "\u{F72A}": "⇞",
        "\u{F72F}": "⇟",
        "\u{F700}": KeySymbol.up,
        "\u{F701}": KeySymbol.down,
        "\u{F702}": KeySymbol.left,
        "\u{F703}": KeySymbol.right,
        "\u{0009}": KeySymbol.tab,
        "\u{0003}": KeySymbol.enter,
        "\u{000D}": KeySymbol.enter,
        "\u{0020}": KeySymbol.space,
        "\u{F704}": "F1",
        "\u{F705}": "F2",
        "\u{F706}": "F3",
        "\u{F707}": "F4",
        "\u{F708}": "F5",
        "\u{F709}": "F6",
        "\u{F70A}": "F7",
        "\u{F70B}": "F8",
        "\u{F70C}": "F9",
        "\u{F70D}": "F10",
        "\u{F70E}": "F11",
        "\u{F70F}": "F12",
    ]
}

