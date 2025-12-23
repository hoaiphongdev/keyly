# Changelog

All notable changes to this project will be documented in this file.

## [1.0.1] - 2024-12-23

### Bug Fixes
- Fix release scripts whitespace error in justfile
- Fix settings menu popup alignment (now opens to the left)
- Fix window height not scaling to content (now fits content, max 80% screen height)

## [1.0.0] - 2024-12-22

### Features
- Hold ⌘ (Command) key for 1 second to show keyboard shortcuts
- Extracts real shortcuts from app menu bar via Accessibility API
- Multi-column layout with category grouping
- Floating window with blur effect
- Auto-cancels if any other key is pressed while holding ⌘
- Dev mode for development (always visible, auto-refresh on app switch)
- Menu bar icon with status menu
- About dialog with app logo
- Supports all macOS applications
- Smart key mapping for special keys (F1-F12, arrows, etc.)
- Emoji & Symbols shortcut mapped to ⌃⌘Space
- Dynamic window height based on content (80% screen width, max 75% height)
- Aligned shortcut layout (modifiers | key | action)

### Settings Menu
- Settings button in shortcuts window
- Reload: refresh shortcuts from current app
- Open Config: open configuration file
- Open Accessibility Settings: quick access to fix permission issues
- Quit: exit the app

### Installation
- DMG installer with Applications drop link
- One-liner install script: `curl -fsSL https://raw.githubusercontent.com/hoaiphongdev/keyly/main/scripts/install.sh | bash`
- Auto-reset accessibility permissions on update
