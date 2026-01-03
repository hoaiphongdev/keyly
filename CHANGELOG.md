# Changelog

All notable changes to this project will be documented in this file.

## [1.3.0] - 2025-01-03

### Changed
- Hold duration increased from 1.7s to 2s for more intentional activation
- Temporarily disabled auto-update feature

### Added
- Template installer script (`scripts/install-templates.sh`)
- Cursor IDE keyboard shortcuts template
- Support for fetching community templates from GitHub

### Templates
- New `-t` flag to specify template name (required)
- New `-n` flag to customize local filename (optional)
- Backup/replace prompt when template already exists
- Validation for template existence before download

## [1.2.0] - 2024-12-29

### Auto-Update
- Automatic update checking via GitHub Releases API (no Sparkle dependency)
- Background update check on app launch (every 2 days)
- "Check for Updates..." option in menu bar and settings menu
- Update notification banner in shortcuts window
  - Blue banner when update available
  - Spinner animation during download
  - Green banner when ready to install
- One-click update: download → install → relaunch automatically
- Update persists across app restarts (stored in UserDefaults)

### Scripts
- `check-update.sh`: Fetches latest version from GitHub Releases
- `perform-update.sh`: Downloads DMG, installs update, relaunches app
- Embedded script fallback for production builds

## [1.1.0] - 2024-12-24

### Changed
- Hold duration increased from 1s to 1.7s for better UX

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
