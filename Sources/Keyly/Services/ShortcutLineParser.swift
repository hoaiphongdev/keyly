import Foundation

/// Parses one shortcut line of a `.keyly` file.
///
/// Two layouts are accepted:
/// - `⇧⌘T | Reopen last tab` — split on `|` (needed when the left side contains spaces, e.g. `tool attach <name> | Attach`)
/// - `CMD+SHIFT+T    Reopen last tab` — split on the first tab or run of 2+ spaces, else the first space
///
/// Written modifiers (`CMD+SHIFT+T`, `ctrl-alt-delete`) are normalized to macOS glyphs (`⇧⌘T`, `⌃⌥⌫`).
enum ShortcutLineParser {
    static func parse(_ line: String) -> (shortcut: String, action: String)? {
        guard let (left, right) = split(line) else { return nil }
        return (normalize(left), right)
    }

    static func split(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.contains("|") {
            let parts = trimmed.components(separatedBy: "|")
            if parts.count == 2, let pair = nonEmpty(parts[0], parts[1]) {
                return pair
            }
        }

        guard let separator = columnGap(in: trimmed) ?? trimmed.range(of: " ") else { return nil }
        return nonEmpty(String(trimmed[..<separator.lowerBound]), String(trimmed[separator.upperBound...]))
    }

    private static func columnGap(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isWhitespace else {
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            while end < text.endIndex && text[end].isWhitespace {
                end = text.index(after: end)
            }
            if text[index] == "\t" || text.distance(from: index, to: end) >= 2 {
                return index..<end
            }
            index = end
        }
        return nil
    }

    /// Normalizes each space-separated chord ("CMD+K CMD+S" → "⌘K ⌘S").
    /// Anything that is not a modifier combination or a named key is returned unchanged.
    static func normalize(_ raw: String) -> String {
        raw.components(separatedBy: " ")
            .map(normalizeChord)
            .joined(separator: " ")
    }

    private static func normalizeChord(_ chord: String) -> String {
        var rest = Substring(chord)
        var modifiers: Set<String> = []

        // Consume leading "<modifier>+" / "<modifier>-" tokens; the key itself may be "+" or "-"
        consuming: while !rest.isEmpty {
            let upper = rest.uppercased()
            for (names, symbol) in ShortcutMapping.modifierNames {
                for name in names {
                    guard rest.count > name.count,
                          upper.hasPrefix(name) else { continue }
                    let separatorIndex = rest.index(rest.startIndex, offsetBy: name.count)
                    guard rest[separatorIndex] == "+" || rest[separatorIndex] == "-" else { continue }
                    let keyStart = rest.index(after: separatorIndex)
                    guard keyStart < rest.endIndex else { continue }
                    modifiers.insert(symbol)
                    rest = rest[keyStart...]
                    continue consuming
                }
            }
            break
        }

        let key = String(rest)
        let namedKey = ShortcutMapping.specialKeys[key.uppercased()]

        guard !modifiers.isEmpty || namedKey != nil else { return chord }

        let orderedModifiers = ShortcutMapping.modifierOrder.filter(modifiers.contains).joined()
        if let namedKey { return orderedModifiers + namedKey }
        return key.count == 1 ? orderedModifiers + key.uppercased() : orderedModifiers + "+" + key
    }

    private static func nonEmpty(_ left: String, _ right: String) -> (String, String)? {
        let left = left.trimmingCharacters(in: .whitespaces)
        let right = right.trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return (left, right)
    }
}
