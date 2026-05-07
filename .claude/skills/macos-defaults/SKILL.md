---
name: macos-defaults
description: "[macos] Read and write macOS app/system preferences via the `defaults` command — Dock, Finder, Safari, NSGlobalDomain. Use for tweaks like 'dock auto-hide', 'show hidden files', 'expand save dialog'. Analog of windows-system-settings."
---

# macos-defaults

macOS preferences live in `.plist` files under `~/Library/Preferences/` (per-user) and `/Library/Preferences/` (system). Apps read them via `cfprefsd`. The `defaults` command is the canonical tool for reading and writing them.

Use this skill for:
- Dock behavior (auto-hide, position, magnification)
- Finder behavior (show hidden files, status bar, default view)
- Safari developer tools, Keyboard, Trackpad, Mission Control
- Per-app prefs that have no GUI toggle

## Read

```bash
defaults read                                  # everything for current user (huge)
defaults read com.apple.dock                   # all Dock settings
defaults read com.apple.finder AppleShowAllFiles  # specific key
defaults read-type com.apple.dock autohide     # type (bool, int, string, etc.)
defaults domains                               # list every domain
```

Common domains to know:

- `com.apple.dock`
- `com.apple.finder`
- `com.apple.safari`
- `com.apple.symbolichotkeys`
- `com.apple.systempreferences`
- `com.apple.menuextra.clock`
- `NSGlobalDomain` — system-wide settings (alias `-g` or `-globalDomain`)

For app-specific domains: usually the bundle ID. Find it with:

```bash
osascript -e 'id of app "AppName"'
```

## Write

```bash
defaults write <domain> <key> -<type> <value>
```

Types: `-bool`, `-int`, `-float`, `-string`, `-array`, `-dict`, `-data`. Without a type, defaults guesses, which can produce strings where you wanted bools. **Always specify the type.**

Examples:

```bash
# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true

# Show hidden files in Finder
defaults write com.apple.finder AppleShowAllFiles -bool true

# Expand save panel by default
defaults write -g NSNavPanelExpandedStateForSaveMode -bool true
defaults write -g NSNavPanelExpandedStateForSaveMode2 -bool true

# Disable smart quotes (for typing code)
defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write -g NSAutomaticDashSubstitutionEnabled -bool false

# Keep folders on top in Finder
defaults write com.apple.finder _FXSortFoldersFirst -bool true
```

## Apply changes (kill the agent)

Most settings need a `killall` to take effect — the responsible process re-reads its plist when relaunched:

| Domain | Apply with |
|---|---|
| `com.apple.dock` | `killall Dock` |
| `com.apple.finder`, `_FXSortFoldersFirst`, `AppleShowAllFiles` | `killall Finder` |
| `com.apple.systemuiserver` (menu bar) | `killall SystemUIServer` |
| `NSGlobalDomain` general | varies; sometimes need full logout/login |
| `com.apple.controlcenter` | `killall ControlCenter` |
| Per-app | quit and relaunch the app |

`killall Dock` is harmless — Dock respawns instantly. Same for Finder.

## Delete a key (revert to default)

```bash
defaults delete com.apple.dock autohide        # one key
defaults delete com.apple.dock                 # whole domain (back to factory)
```

Then `killall Dock` (or whatever) to apply.

## Common recipes

```bash
# Show file extensions everywhere
defaults write -g AppleShowAllExtensions -bool true && killall Finder

# Show full posix path in Finder window title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true && killall Finder

# Disable .DS_Store on network shares
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Speed up Mission Control animation
defaults write com.apple.dock expose-animation-duration -float 0.15 && killall Dock

# Disable press-and-hold for accent menu (use repeat)
defaults write -g ApplePressAndHoldEnabled -bool false

# Set screenshot location
defaults write com.apple.screencapture location ~/Pictures/Screenshots && killall SystemUIServer

# Set screenshot format (png, jpg, pdf, tiff)
defaults write com.apple.screencapture type -string png

# Disable shadow in screenshots
defaults write com.apple.screencapture disable-shadow -bool true

# Always show full URL in Safari address bar
defaults write com.apple.safari ShowFullURLInSmartSearchField -bool true

# Enable Safari developer menu
defaults write com.apple.safari IncludeDevelopMenu -bool true
defaults write com.apple.safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true
```

## Backup before write

Per CLAUDE.md, snapshot the current value before changing it:

```bash
mkdir -p backups/macos/defaults/$(date +%Y%m%d-%H%M%S)
defaults read com.apple.dock > backups/macos/defaults/$(date +%Y%m%d-%H%M%S)/com.apple.dock.txt
```

For a single key: capture current value before overwriting:

```bash
defaults read com.apple.dock autohide  # note this output before writing
```

To revert later:

```bash
defaults write com.apple.dock autohide -bool false  # whatever the prior value was
killall Dock
```

## Where things live

- Per-user prefs: `~/Library/Preferences/<domain>.plist`
- System prefs: `/Library/Preferences/<domain>.plist`
- Sandboxed apps: `~/Library/Containers/<bundle-id>/Data/Library/Preferences/<domain>.plist`
- Don't edit plist files directly with text editors — they're often binary. Use `defaults` or `plutil -convert xml1`.

## Safety

- **Per-user (`~/Library/Preferences/`) is reversible** — just rewrite or delete the key. Proceed with normal care.
- **System-wide (`/Library/Preferences/`) needs sudo + explicit confirmation** per CLAUDE.md.
- **Some keys take effect only after logout/login** — Dock/Finder kills usually work, but global UI settings sometimes don't until next session.
- **Don't `defaults delete` an entire domain casually** — you'll lose every setting in it. Delete specific keys when possible.
- **Sandboxed app prefs** (Mac App Store apps mostly) need the full path including `Containers/<bundle-id>/Data/...` — using just the bundle ID won't work.
