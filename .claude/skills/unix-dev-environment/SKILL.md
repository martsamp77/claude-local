---
name: unix-dev-environment
description: "[unix] Set up and manage developer toolchains on Linux + macOS — git, SSH, language runtimes via mise/asdf or native tools, shell profile, VS Code, terminal emulators. Use when configuring dev tools on a Linux or Mac machine."
---

# unix-dev-environment

Use this skill when configuring or maintaining developer tooling on Linux or macOS. Defers to:
- `linux-packages` (Linux) or `macos-homebrew` (macOS) for installation
- `linux-env-vars` or `macos-env-vars` for PATH and env vars
- `linux-systemd` (Linux) or `macos-launchd` (macOS) for daemons

Where commands diverge between Linux and macOS, both are shown side by side.

## git

Install / upgrade:

```bash
# Linux (Debian/Ubuntu)
sudo apt install git
# Linux (Fedora/RHEL)
sudo dnf install git
# Linux (Arch)
sudo pacman -S git
# macOS
brew install git
# Plus the GitHub CLI:
brew install gh                       # macOS
sudo apt install gh                   # Ubuntu (after adding the official repo) — or `brew install gh` on Linuxbrew
```

Common config — confirm name/email with the user before setting:

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
git config --global core.autocrlf input        # Linux/macOS: keep LF on disk, accept LF or CRLF on commit
git config --global pull.rebase false
git config --global fetch.prune true
git config --global rerere.enabled true
```

Editor — pick one that matches what's installed:

```bash
git config --global core.editor "code --wait"        # VS Code
git config --global core.editor "nvim"               # Neovim
git config --global core.editor "vim"                # vim
```

Credential helper — different per OS:

| OS | Command | Backing store |
|---|---|---|
| Linux (GNOME/KDE) | `git config --global credential.helper /usr/lib/git-core/git-credential-libsecret` | libsecret (GNOME Keyring / KWallet) |
| Linux (server) | `git config --global credential.helper "cache --timeout=3600"` | RAM, 1-hour cache |
| macOS | `git config --global credential.helper osxkeychain` | macOS Keychain |

Inspect:

```bash
git config --global --list
git config --global --edit                   # opens in $EDITOR
```

## SSH keys

Default location is `~/.ssh/`. Generate an ed25519 key (modern default):

```bash
ssh-keygen -t ed25519 -C "you@<machine>" -f ~/.ssh/id_ed25519
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

`ssh-agent` is automatic on macOS (started by launchd) and on most desktop Linux (started per-session by the desktop environment). On a server / minimal Linux:

```bash
# One-shot in current shell:
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Persistent: add to ~/.zprofile / ~/.bash_profile:
[ -z "$SSH_AUTH_SOCK" ] && eval "$(ssh-agent -s)" >/dev/null
ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf ~/.ssh/id_ed25519 | awk '{print $2}')" \
    || ssh-add ~/.ssh/id_ed25519
```

On macOS, persist the passphrase in Keychain (one-time):

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
# And in ~/.ssh/config:
Host *
    UseKeychain yes
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
```

Copy public key to clipboard:

```bash
# Linux (X11)
xclip -selection clipboard < ~/.ssh/id_ed25519.pub
# Linux (Wayland)
wl-copy < ~/.ssh/id_ed25519.pub
# macOS
pbcopy < ~/.ssh/id_ed25519.pub
```

For GitHub:

```bash
gh auth login                                            # easiest path
gh ssh-key add ~/.ssh/id_ed25519.pub --title "<host>"
```

## Shell profile

The persistent shell config depends on which shell is the user's login shell:

```bash
echo "$SHELL"                # path to the login shell binary
chsh -s /bin/zsh             # switch login shell (logout/login to apply)
```

| Shell | Default on | Per-user config | Login config |
|---|---|---|---|
| bash | most Linux | `~/.bashrc` | `~/.bash_profile` (or fallback to `~/.profile`) |
| zsh | macOS (Catalina+); some Linux | `~/.zshrc` | `~/.zprofile` |

For the difference between login vs interactive vs both, see the `linux-env-vars` and `macos-env-vars` skills.

Useful starter zshrc content:

```zsh
# ~/.zshrc
# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Completion
autoload -Uz compinit && compinit

# Prompt — try a starship if installed
command -v starship >/dev/null && eval "$(starship init zsh)"

# Aliases
alias ll='ls -lah'
alias gs='git status'
alias gd='git diff'
```

For bash, equivalent in `~/.bashrc`:

```bash
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

command -v starship >/dev/null && eval "$(starship init bash)"

alias ll='ls -lah'
alias gs='git status'
```

## Language runtimes

The cleanest way to manage multiple language versions on Unix is a polyglot version manager:

- **`mise`** (modern, Rust-built, shell-agnostic; replaces asdf + nvm + pyenv + rbenv etc.):

  ```bash
  # Install
  curl https://mise.run | sh
  # Or:
  brew install mise

  # Add to shell:
  echo 'eval "$(mise activate zsh)"' >> ~/.zshrc      # or bash

  # Use:
  mise use --global node@lts python@3.12 go@latest rust@stable
  mise use node@20                        # per-directory (writes .tool-versions)
  mise list                               # what's installed
  mise upgrade                            # update everything
  ```

- **`asdf`** — older, more established equivalent. Same idea, slower.
- **`nvm`** — Node-only, scripts add `~/.nvm/nvm.sh` to your shell rc.

For one-off language installs without a version manager, use the package manager directly:

| Tool | Linux (apt example) | macOS |
|---|---|---|
| Node.js | `sudo apt install nodejs npm` (often old; prefer mise) | `brew install node` |
| Python | usually preinstalled; `sudo apt install python3 python3-pip python3-venv` | `brew install python` |
| Go | `sudo apt install golang` (or download from go.dev for current) | `brew install go` |
| Rust | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` | same (or `brew install rustup`) |
| .NET | `sudo apt install dotnet-sdk-8.0` (after adding the MS repo) | `brew install --cask dotnet-sdk` |

Verify on PATH after install:

```bash
node --version; npm --version
python3 --version
go version
cargo --version; rustc --version
```

If a tool isn't on PATH, see `linux-env-vars` or `macos-env-vars`.

## VS Code

```bash
brew install --cask visual-studio-code            # macOS
sudo apt install code                             # Linux (after adding MS repo)
```

Settings on Linux: `~/.config/Code/User/settings.json`
Settings on macOS: `~/Library/Application Support/Code/User/settings.json`

Extensions:

```bash
code --list-extensions
code --install-extension <publisher.name>
```

For per-machine reproducibility, export the extension list to a backup file in this repo (path is repo-relative — run from the repo root):

```bash
# Linux
code --list-extensions > backups/linux/vscode-extensions.txt

# macOS
code --list-extensions > backups/macos/vscode-extensions.txt
```

## Terminal emulator

| OS | Built-in | Recommended upgrade |
|---|---|---|
| Linux | distro-default (gnome-terminal, konsole) | `kitty`, `alacritty`, or `wezterm` |
| macOS | Terminal.app | `iTerm2` (`brew install --cask iterm2`) or `wezterm` |

For macOS Terminal/iTerm2, the relevant settings live in their respective preferences (use the `macos-defaults` skill for scripted prefs).

For kitty/alacritty/wezterm: configs live under `~/.config/<name>/` as plain text — easy to version-control.

## Common patterns

**Bootstrap a new Mac:**

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Restore from a Brewfile (see macos-homebrew skill)
brew bundle install --file=~/Brewfile

# Set up git, SSH, shell profile per the sections above
```

**Bootstrap a new Linux box (Ubuntu):**

```bash
sudo apt update && sudo apt install -y git curl wget zsh build-essential
chsh -s /bin/zsh
curl https://mise.run | sh
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
mise use --global node@lts python@3.12 go@latest

# Generate SSH key, add to GitHub
ssh-keygen -t ed25519 -C "you@$(hostname)" -f ~/.ssh/id_ed25519
gh auth login
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"
```

## Safety

- **Don't `chsh` to a shell that's not in `/etc/shells`.** Add it first if needed.
- **Don't blindly `curl | sh`** unfamiliar installer scripts. The ones above are standard for their respective tools, but read the script if you're unsure.
- **`ssh-keygen` overwrites the existing key without warning** if you reuse the same `-f` path. Check first: `ls ~/.ssh/`.
- **Per-user files (`~/.zshrc`, `~/.gitconfig`, `~/.ssh/`) should be `chmod 600` or stricter** for anything containing secrets or auth material.
- **Don't put credentials in `~/.gitconfig`** — use the credential helper instead (libsecret, osxkeychain, or cache).
