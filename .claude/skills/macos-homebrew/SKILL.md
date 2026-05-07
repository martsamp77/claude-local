---
name: macos-homebrew
description: "[macos] Install, upgrade, search, list, pin, and uninstall packages via Homebrew (formulae + casks). Use for software management on macOS — analog of winget-packages on Windows and linux-packages on Linux."
---

# macos-homebrew

Homebrew is the de-facto package manager on macOS. It manages two kinds of things:

- **Formulae** — command-line tools and libraries (`ripgrep`, `git`, `jq`, `python`).
- **Casks** — GUI macOS apps installed as `.app` bundles (`firefox`, `slack`, `iterm2`, `visual-studio-code`).

## Apple Silicon vs Intel paths

| Mac | Homebrew prefix | binaries on PATH |
|---|---|---|
| Apple Silicon (M-series) | `/opt/homebrew` | `/opt/homebrew/bin` |
| Intel | `/usr/local` | `/usr/local/bin` |

These don't conflict — you could even have both on a Rosetta-enabled Apple Silicon machine. Apps installed under one prefix don't appear under the other. Check `which brew` to confirm which one is active.

For PATH setup, see the `macos-env-vars` skill.

## Install Homebrew (first-time only)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Verify with `brew doctor` after install.

## Search and inspect

```bash
brew search <query>                 # formulae + casks matching name
brew search --formula <query>
brew search --cask <query>
brew info <pkg>                     # version, deps, caveats, install size
brew home <pkg>                     # open homepage
brew deps <pkg>                     # what depends on what
brew uses <pkg> --installed         # what installed packages depend on this one
brew leaves                         # explicitly-installed (not pulled in as deps)
```

## Install / uninstall

```bash
brew install <formula>              # CLI tool
brew install --cask <app>           # GUI app
brew uninstall <pkg>
brew uninstall --zap <cask>         # cask + all its config/state
brew reinstall <pkg>                # reinstall from current source
```

`brew install --cask` requires Internet for the .app download. `--zap` is the cask-specific equivalent of "purge config too."

## Upgrade

```bash
brew update                         # refresh package metadata
brew outdated                       # what's behind the current bottle
brew upgrade                        # upgrade everything
brew upgrade <pkg>                  # one specific
brew upgrade --cask                 # casks only
```

`brew upgrade` doesn't auto-cleanup old versions. Run `brew cleanup` periodically.

## Pin / hold

```bash
brew pin <pkg>                      # exclude from upgrade
brew unpin <pkg>
brew list --pinned
```

Casks don't have a built-in pin; for casks, just don't run `brew upgrade --cask` until you mean to.

## List

```bash
brew list                           # all installed (formulae + casks)
brew list --formula
brew list --cask
brew list --versions <pkg>
```

## Tap (third-party repos)

```bash
brew tap                            # list active taps
brew tap <user/repo>                # add a tap
brew untap <user/repo>
brew install <user/repo/<formula>>  # from a specific tap
```

Common useful taps: `homebrew/cask-fonts` (fonts), `homebrew/cask-versions` (older app versions).

## Brewfile (snapshot + restore)

```bash
brew bundle dump --file=~/Brewfile  # snapshot current installs
brew bundle install --file=~/Brewfile  # install everything in the file
brew bundle cleanup --file=~/Brewfile  # show what's installed but not in Brewfile
```

A `Brewfile` looks like:

```ruby
tap "homebrew/cask-fonts"
brew "ripgrep"
brew "jq"
cask "iterm2"
cask "visual-studio-code"
mas "Xcode", id: 497799835      # if mas-cli is installed for App Store apps
```

This is the macOS analog of `winget export` / `winget import`. Useful for setting up a new Mac from scratch.

## Doctor and cleanup

```bash
brew doctor                         # warnings about your install
brew cleanup                        # remove old versions
brew cleanup -n                     # dry-run
brew autoremove                     # remove no-longer-needed dependencies
brew missing                        # report missing deps
```

Run `brew doctor` after macOS upgrades — sometimes Xcode CLT breaks.

## Common patterns

**Set up a new Mac:**

```bash
# Install Homebrew (once)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Restore from Brewfile
brew bundle install --file=~/Brewfile

# Or one-shot
brew install ripgrep jq fzf bat
brew install --cask iterm2 visual-studio-code firefox
```

**Switch between cask versions** (e.g. older Firefox):

```bash
brew tap homebrew/cask-versions
brew install --cask firefox-esr
```

**Find what brought in a transitive dependency:**

```bash
brew uses <transitive-pkg> --installed
```

## Safety

- **App Store apps don't go through brew.** Use `mas` (`brew install mas`) if you need scriptable App Store installs.
- **Casks install full apps** — check `brew info --cask <name>` for the installer's source URL before installing unfamiliar casks.
- **`brew uninstall --zap` deletes config** — including app preferences, license info, etc. Use plain `brew uninstall` if you might reinstall later.
- **Don't run brew with `sudo`** unless explicitly told to. It manages its own permissions; sudo can break the install.
- **System Python / Ruby / OpenSSL stay system-managed.** Brew installs *additional* versions; don't try to replace `/usr/bin/python3` with the brew version on the PATH unless you know what depends on it.
