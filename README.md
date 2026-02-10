# Keyly

macOS menu bar app that displays keyboard shortcuts for the currently active application when you hold the ⌘ (Command) key.

## 🚀 Installation

> **1.** Open any terminal app on your Mac (Terminal, iTerm, Warp, etc.)
>
> **2.** Paste this command and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/hoaiphongdev/keyly/main/scripts/install.sh | bash
```

> **3.** Follow the on-screen instructions to grant Accessibility permission
>
> **4.** Done! Hold `⌘ Command` for 2 seconds to show shortcuts

## Screenshots

<p align="center">
  <img src="docs/images/example-1.png" alt="Screenshot 1" width="600">
  <br><br>
  <img src="docs/images/example-2.png" alt="Screenshot 2" width="600">
</p>

## Features

- **Customizable Trigger**: Hold ⌘ for specified duration or press multiple times
- **Real-time Search**: Search shortcuts with instant filtering
- **Group System**: Organize shortcuts with descriptions and multi-column layouts
- **Custom Templates**: Create `.keyly` files for any application
- **Runtime Settings**: Configure via `~/.config/keyly/setting.conf`
- **Multiple Close Options**: Press ESC or click outside to close
- **Dynamic UI**: Responsive layout that adapts to content
- **Global Shortcuts**: System-wide shortcuts from templates

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
3. Hold the **Command (⌘)** key for 0.5 seconds (default)
4. A window will appear showing all keyboard shortcuts
5. **Close the window by**:
   - Press **ESC** key
   - **Click outside** the window
   - Use the configured super key again

## Configuration

### Settings (`~/.config/keyly/setting.conf`)

Configure app behavior:

```ini
# Super key configuration
super_key=cmd
trigger_type=hold
hold_duration=0.5

# UI settings
screen_width_ratio=0.7
```

**Options:**
- `super_key`: Key combination (e.g., `cmd`, `cmd+shift`, `ctrl+alt`)
- `trigger_type`: `hold` or `press`
- `hold_duration`: Hold time in seconds
- `screen_width_ratio`: Window width ratio (0.1-1.0)

### Custom Templates (`~/.config/keyly/templates/`)

Create `.keyly` files for any application:

```
# Sheet Name: My Shortcuts
# App: /Applications/Safari.app
# Hide Default: false

# Group: Navigation - Web browsing shortcuts - Size: 2
[Navigation]
CMD+L       Open Location
CMD+T       New Tab
CMD+SHIFT+T Reopen Last Tab

[Bookmarks]
> Bookmark management
CMD+D       Add Bookmark
```

**Template Features:**
- `# Hide Default: true` - Hide system menu shortcuts
- `# Group: Name - Description - Size: 2` - Multi-column groups
- `> Description` - Category descriptions

## Community Templates

Install pre-made shortcut templates from the community:

Install a template:

```bash
curl -sL https://raw.githubusercontent.com/hoaiphongdev/keyly/main/scripts/install-templates.sh | bash -s -- -t cursor.keyly
```

Install with custom name:

```bash
curl -sL https://raw.githubusercontent.com/hoaiphongdev/keyly/main/scripts/install-templates.sh | bash -s -- -t cursor.keyly -n my-cursor.keyly
```

**Options:**
- `-t <name>` - Template name (required)
- `-n <name>` - Save as custom filename (optional)

**Available templates:** [templates/](https://github.com/hoaiphongdev/keyly/tree/main/templates)

## Auto-Update

Keyly uses [Sparkle](https://sparkle-project.org/) for automatic updates. Updates are checked daily and can also be triggered manually via:
- Menu bar icon → Check for Updates...
- Settings button → Check for Updates...

### For Developers: Release Process

1. **Generate EdDSA keys** (one-time setup):
   ```bash
   swift build  # Fetch Sparkle
   ./scripts/generate-keys.sh
   # Save the public key to sparkle_eddsa_public_key.txt
   ```

2. **Build release**:
   ```bash
   just release 1.0.0
   ```

3. **Sign the DMG**:
   ```bash
   ./scripts/sign-update.sh .build/Keyly.dmg
   ```

4. **Update appcast.xml** with the signature and upload to GitHub Pages

5. **Create GitHub Release** and upload `Keyly.dmg`

## License

Licensed under the [MIT License](LICENSE).

---

Made with ❤️ by [hoaiphongdev](https://github.com/hoaiphongdev)
