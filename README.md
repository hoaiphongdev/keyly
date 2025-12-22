# Keyly

macOS menu bar app that displays keyboard shortcuts for the currently active application when you hold the ⌘ (Command) key.

## Features

- Hold ⌘ for 1 second to show shortcuts
- Extracts real shortcuts from app menu bar via Accessibility API
- Works with any macOS application
- Multi-column layout with category grouping
- Floating window with blur effect

## Requirements

- macOS 12.0+
- Swift 5.9+
- Accessibility permissions

## Project Structure

```
Sources/Keyly/
├── App/
│   ├── main.swift
│   └── AppDelegate.swift
├── Models/
│   └── ShortcutItem.swift
├── Services/
│   └── ShortcutExtractor.swift
└── Windows/
    └── ShortcutsWindow.swift
```

## Build & Run

### Using just

```bash
just install    # Clean and build release
just dev        # Dev mode (always visible, auto-refresh on app switch)
just prod       # Production mode
```

### Using Swift CLI

```bash
swift build
swift run Keyly
```

### Using Xcode

```bash
open Package.swift
```

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

### Dev Mode

Dev mode keeps the shortcuts window always visible and auto-updates when you switch apps:

```bash
just dev
```

## Building a Release

```bash
just release 1.0.0
```

This creates:
- `.build/release/Keyly.app` - App bundle
- `.build/Keyly-1.0.0.dmg` - DMG installer

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

---

Made with ❤️ by [hoaiphongdev](https://github.com/hoaiphongdev)
