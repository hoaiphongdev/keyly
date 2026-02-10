# Changelog

All notable changes to this project will be documented in this file.

## [1.6.0] - 2026-02-09

### Added
- **Runtime Settings Management**: Load configuration from `~/.config/keyly/setting.conf`
- **Customizable Super Key Combinations**: Support for any key combination (e.g., `cmd+a`, `ctrl+shift+x`, `fn`)
- **Multiple Trigger Types**: `hold` (duration-based) and `press` (count-based)
- **Search Functionality**: Real-time search with debouncing and minimum UI dimensions
- **Group System**: Organize shortcuts with descriptions and custom sizes (1-N columns)
- **Global Shortcuts**: System-wide shortcuts from `global.keyly` template
- **Click-Outside-to-Close**: Modal closes when clicking outside or pressing ESC
- **Settings Auto-Reload**: Configuration changes detected and applied automatically

### Changed
- **Dynamic Window Sizing**: Width scales with content, respects screen ratio limits
- **Group Display Order**: Default shortcuts first, then file order (not alphabetical)
- **UI Color System**: Clean black background with white text variants
- **Search UI**: Minimum 500x300px to prevent ugly small windows
- **Group Containers**: Support multi-column spanning with proper content scaling

### Fixed
- **Super Key Detection**: Corrected guard logic preventing panel display
- **Window Positioning**: Content properly centered with dynamic grid offset
- **Group Descriptions**: Multi-line text wrapping with proper width constraints
- **Search Performance**: Debounced filtering with async UI updates
- **Color Contrast**: High contrast text on solid backgrounds

### Technical
- **New Architecture**: Separated `AppConstants`, `WindowConstants`, `SettingsConstants`
- **Enhanced Models**: Added `groupSizes`, `groupDescriptions` to `ShortcutSheet`
- **Performance**: Optimized search filtering and UI rebuilding
- **Code Quality**: 1700+ lines added, comprehensive error handling

## [1.5.0] - 2025-01-04

### Changed
- Improved shortcuts window visibility on both light and dark app backgrounds
- Added subtle diagonal gradient overlay for consistent contrast
- Updated text colors: white headers, cyan key labels, improved opacity hierarchy

### Fixed
- Shortcuts window was too transparent/hard to read on light-themed apps

## [1.4.1] - 2025-01-03

### Fixed
- Removed "Check for Updates..." from settings menu (was still visible after disabling auto-update)

## [1.4.0] - 2025-01-03

### Added
- Category descriptions in templates (use `> description` after `[Category]`)
- Sub-description displayed below category title in shortcuts window
- `-f` flag for force replace in template installer script

### Templates
- Updated cursor.keyly with contextual hints for each category
- Example: `> Focus on chat panel first.` under `[Chat]`

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
