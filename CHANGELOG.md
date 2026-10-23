# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **Install with Homebrew**: `brew install --cask hoaiphongdev/keyly/keyly`. No security prompt on first launch, and Keyly keeps updating itself. Already installed with `curl`? Add `--adopt` to let Homebrew take over the app you have.

### Changed
- **Reinstalling keeps Accessibility**: Running the install command again no longer resets the Accessibility permission, unless you're coming from 1.7.3 or older.

## [1.10.0] - 2026-10-21

### Added
- **Config problems in the ⚙︎ menu**: A line or value Keyly can't read is listed under "⚠︎ config problems"; click one to open the file at that line. Problems are also logged to Console.app (`com.keyly`).
- **`# App:` takes a name or bundle id**: `# App: Figma` and `# App: com.figma.Desktop` work next to the path. Sheets also match by name, so apps in `~/Applications`, Setapp or a newer year (Photoshop 2025 for a 2024 template) are found.
- **Escaped keys**: `\#`, `\[` and `\>` write a shortcut whose key starts with that character.

### Changed
- **Forgiving settings**: Names and values ignore case; quotes and trailing `# comments` are fine; `super_key` takes `command`, `option`, `control` and ⌘⌃⌥⇧ symbols; `hold_duration` takes `500ms`; numbers out of range are clamped (`hold_duration` 0.1–3s, `press_count` 1–4) instead of being accepted or reset. Typos get a "did you mean".
- **`setting.conf` is created on first launch**, with every option commented out.
- **Modifier-only triggers count on release**: With `super_key = cmd` and `trigger_type = press`, a tap counts when ⌘ is let go and any other key or modifier in between cancels it, so ⌘C or ⌘⇧ never open Keyly, even with `press_count = 1`.
- **`super_key` names**: `enter` means Return and `del` means ⌫, as in sheets. `fn` can't be combined with arrows, F keys, Home/End or Page Up/Down, because macOS reports fn for those keys on its own.
- **Same file in two folders**: When `templates/` and `~/.config/keyly/` both have a file with the same name, the one saved last is used and the other is listed in the ⚙︎ menu.
- **Faster, steadier reloads**: Config files are parsed off the main thread, the reload waits for the last save, and a file that can't be read mid-save keeps its previous version.

### Fixed
- **Trigger with extra modifiers**: `super_key = ctrl+k` no longer opens on ⌃⌘K.
- **Holding ⌘ then pressing ⌘C** cancels the hold, and typing in between no longer counts toward a double tap.
- **Evernote, Notion and Illustrator templates**: Markdown shortcuts (`#`, `##`, `>`) were read as comments or descriptions.
- **`⌘+click`** keeps its `+`.
- **Symlinked `templates/` folder** (dotfiles setups): its sheets load and reload on save.
- **Opening a config file in VS Code** works when Keyly is launched from Finder, where `code` in `/usr/local/bin` or `/opt/homebrew/bin` wasn't found before.
- **A missed key release** no longer blocks the next key + modifier trigger.
- **Open window keeps its search** when something unrelated changes in `~/.config/keyly` (Finder's `.DS_Store`, editor swap files).
- **UTF-16 config files** (with a byte order mark) are read correctly.

## [1.9.0] - 2026-10-20

### Added
- **Double-tap ⇪ Caps Lock**: The new default trigger. Your own `super_key` in `setting.conf` keeps working; an unknown key name now falls back to Caps Lock with a warning.
- **Instant search**: Start typing in the shortcuts window to filter by action, menu or key, with matches highlighted. The first ESC clears the search, the next one closes the window.

### Changed
- **Reskinned shortcuts window**: Keycap-style shortcuts, cleaner groups and a layout that fits small MacBook screens.
- **Templates folder**: `install-templates.sh` installs into `~/.config/keyly/templates/` and accepts names with or without `.keyly`. Files placed directly in `~/.config/keyly/` are still loaded.

### Fixed
- **Custom shortcuts and bundled templates load again**: Lines written as `CMD+SHIFT+T    Description` (tab or 2+ spaces) are read alongside `⇧⌘T | Description`, and written modifiers (`CMD`, `SHIFT`, `OPT`, `CTRL`, `ENTER`…) are shown as ⌘⇧⌥⌃⏎.
- **Caps Lock trigger after a live config change**: No longer ignored after switching from a key-combination trigger, and the first double-tap isn't lost.
- **Grouped rows**: The widest row inside a group card is no longer cut off.

## [1.8.0] - 2026-10-19

### Added
- **Auto-update**: Keyly checks for new versions every 6 hours (Sparkle). When one is out, the menu bar icon gets a red dot, an "Update to x.y.z…" menu item appears and you get a notification. One click installs and relaunches.
- **Check for Updates…**: Available in the menu bar menu and the shortcuts window settings menu.

### Changed
- **Stable signing**: Releases are signed with one fixed certificate, so the Accessibility permission survives updates.
- **Upgrading from 1.7.3 or older**: Run the install command once more and grant Accessibility again. Updates are automatic after that.

### Removed
- **Old update banner**: Replaced by the Sparkle updater.

## [1.7.3] - 2026-02-17

### Changed
- **Shortcuts as-is**: Shortcut text shows exactly as in template (no normalization/uppercasing).
- **UI reskin**: Dark gray window background; group 14pt bold vs category 11pt muted; group containers transparent with border only.

## [1.7.2] - 2026-02-10

### Fixed
- **Group reset**: `# Group: None/Empty` exits current group, renders plain without border
- **File order**: Chunks now render in exact template file order instead of dictionary-sorted
- **Category bleed**: New `# Group:` resets `currentCategory` to prevent description leaking
- **Shortcut casing**: Commands like `mole`, `git show` no longer uppercased — only modifier-based shortcuts normalize
- **Window width**: Calculated from widest group span + ungrouped count, no extra blank columns

## [1.7.1] - 2026-02-10

### Changed
- **Smart group layout**: Groups with >10 items auto-split into multi-column (max 4), grid-snapped for alignment
- **Bordered cards**: Default categories now wrapped in bordered containers for visual consistency
- **Shortest-column-first**: All items placed into shortest column instead of round-robin

## [1.7.0] - 2026-02-10

### Changed
- **Template syntax**: New pipe format `key/command | description`, invalid lines ignored
- **Dynamic column width**: Scales with content, capped by `screen_width_ratio`
- **Text wrapping**: Long descriptions wrap to new lines via `NSTextView`
- **Description color**: Slightly dimmed for visual hierarchy

### Removed
- **Group sizes**: Removed `groupSizes` from model, parser, extractor, and UI
- **Multi-column spanning**: Groups now render as single-column containers

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
