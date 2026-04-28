---
name: dev-environment
description: Set up and manage developer toolchains on Windows — git, SSH, language runtimes, WSL, PowerShell profile. Use when configuring dev tools.
---

# dev-environment

Use this skill when configuring or maintaining developer tooling: language runtimes, git, SSH keys, WSL, PowerShell profile. Defers to `winget-packages` for installation, `windows-env-vars` for PATH, `windows-registry` for low-level config.

## git

Install / upgrade:

```powershell
winget install --id Git.Git --exact
winget install --id GitHub.cli --exact   # gh
```

Common config — confirm name/email with Marty before setting:

```powershell
git config --global user.name  "Marty Sampson"
git config --global user.email "martysampson@gmail.com"
git config --global init.defaultBranch main
git config --global core.autocrlf true                    # Windows: CRLF on checkout, LF on commit
git config --global core.editor "code --wait"
git config --global pull.rebase false
git config --global fetch.prune true
git config --global rerere.enabled true
git config --global credential.helper manager             # Git Credential Manager
```

Inspect:

```powershell
git config --global --list
git config --global --edit          # opens in $EDITOR
```

## SSH keys

Default location is `C:\Users\marty\.ssh\`. Generate a key (ed25519 is the modern default):

```powershell
ssh-keygen -t ed25519 -C "marty@<machine>" -f $HOME\.ssh\id_ed25519
```

Use `ssh-agent` to avoid retyping the passphrase:

```powershell
# One-time: start the agent service
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent

# Add the key
ssh-add $HOME\.ssh\id_ed25519
ssh-add -l    # list loaded keys
```

Copy public key to clipboard:

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub | Set-Clipboard
```

For GitHub specifically:

```powershell
gh auth login                                            # easiest path; uses HTTPS or SSH
gh ssh-key add $HOME\.ssh\id_ed25519.pub --title "<host>"
```

## WSL

```powershell
wsl --list --online                  # available distros
wsl --list --verbose                 # installed
wsl --install -d Ubuntu              # install a distro
wsl --set-default Ubuntu
wsl --set-default-version 2          # WSL2 globally
wsl --update                         # update WSL kernel
wsl --shutdown                       # stop all distros (forces config reload)
```

`%USERPROFILE%\.wslconfig` controls WSL2 VM settings (memory, CPUs, swap):

```ini
[wsl2]
memory=8GB
processors=4
swap=4GB
localhostForwarding=true
```

After editing, `wsl --shutdown` to apply.

## Language runtimes

| Tool | Recommended install | Notes |
|---|---|---|
| Node.js | `winget install OpenJS.NodeJS.LTS` or `nvm-windows` (`winget install CoreyButler.NVMforWindows`) | Use nvm-windows when juggling multiple Node versions. |
| Python | `winget install Python.Python.3.12` | Use `py -3.12` to launch a specific version; `pipx` (`python -m pip install --user pipx`) for isolated tools. |
| Go | `winget install GoLang.Go` | `GOPATH` defaults to `%USERPROFILE%\go`. |
| Rust | `winget install Rustlang.Rustup`, then `rustup default stable` | Toolchains installed under `%USERPROFILE%\.cargo`. |
| .NET | `winget install Microsoft.DotNet.SDK.8` | |

After install, verify on PATH:

```powershell
node --version; npm --version
python --version; py -0p
go version
cargo --version; rustc --version
```

If a tool isn't on PATH after install, see `windows-env-vars`.

## PowerShell profile

The profile is the persistent shell config. Path:

```powershell
$PROFILE                                    # current user, current host
$PROFILE.CurrentUserAllHosts                # current user, all hosts (preferred for portable config)
```

Edit:

```powershell
if (-not (Test-Path $PROFILE.CurrentUserAllHosts)) {
    New-Item -ItemType File -Path $PROFILE.CurrentUserAllHosts -Force | Out-Null
}
code $PROFILE.CurrentUserAllHosts
```

Useful starter profile content:

```powershell
# Aliases
Set-Alias ll Get-ChildItem
Set-Alias which Get-Command

# Better history search (PSReadLine ships with pwsh 7+)
Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# UTF-8 default output
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

## VS Code

```powershell
winget install --id Microsoft.VisualStudioCode --exact
```

Settings live at `%APPDATA%\Code\User\settings.json`. Extension list:

```powershell
code --list-extensions
code --install-extension <publisher.name>
```

For per-machine reproducibility, export the extension list to the workspace:

```powershell
code --list-extensions > C:\DATA\Workspace-37m\claude-local\backups\vscode-extensions.txt
```

## Windows Terminal

Settings: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`. Edit via `Ctrl+,` in Terminal or open the file directly. Profiles for `pwsh`, Git Bash, WSL distros are added automatically once those tools are installed.
