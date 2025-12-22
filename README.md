# Keyly

macOS menu bar app that displays keyboard shortcuts for the currently active application when you hold the ⌘ (Command) key.

> **Inspiration**: This project is inspired by [CheatSheet](https://www.mediaatelier.com/CheatSheet). Keyly is a complete reimplementation in Swift with additional features like custom shortcut configs and settings menu.

## Installation

### One-liner install

```bash
curl -fsSL https://raw.githubusercontent.com/hoaiphongdev/keyly/main/scripts/install.sh | bash
```

### Manual install

Download the latest `Keyly.dmg` from [Releases](https://github.com/hoaiphongdev/keyly/releases), open it and drag to Applications.

## Features

- Hold ⌘ for 1 second to show shortcuts
- Extracts real shortcuts from app menu bar via Accessibility API
- Works with any macOS application
- Multi-column layout with category grouping
- Floating window with blur effect
- Custom shortcut configs via `.keyly` files
- Settings menu (Reload, Open Config, Accessibility Settings, Quit)

## Requirements

- macOS 12.0+
- Swift 5.9+
- Accessibility permissions

## Permissions

The app requires Accessibility permissions to:
1. Monitor global keyboard events
2. Read menu bar shortcuts from other applications

On first launch, go to **System Settings → Privacy & Security → Accessibility** and enable **Keyly**.

## Usage

1. Run the app - you'll see a ⌘ icon in the menu bar
2. Open any application
3. Hold the **Command (⌘)** key for 1 second
4. A window will appear showing all keyboard shortcuts
5. Release ⌘ to hide the window

## Custom Shortcuts

Create `.keyly` files in `~/.config/keyly/` to add custom shortcuts:

```
# Sheet Name: My Shortcuts
# App: /Applications/Safari.app

[Navigation]
CMD+L       Open Location
CMD+T       New Tab
CMD+SHIFT+T Reopen Last Tab

[Bookmarks]
CMD+D       Add Bookmark
```

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

---

Made with ❤️ by [hoaiphongdev](https://github.com/hoaiphongdev)
