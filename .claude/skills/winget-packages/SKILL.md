---
name: winget-packages
description: Install, upgrade, search, list, pin, and uninstall software via winget. Use for software management on Windows 11.
---

# winget-packages

`winget` is Windows' built-in package manager. Default to it for installing software. Only fall back to chocolatey or manual installers when a package isn't in the winget repo.

## Search

```powershell
winget search <name>
winget search "Visual Studio Code"
winget search --id Microsoft.VisualStudioCode --exact
```

When an install command needs a precise package, get the `Id` from search and use `--id` + `--exact` to avoid ambiguity.

## Install

```powershell
# Interactive (will prompt for source agreement on first run)
winget install --id Microsoft.VisualStudioCode --exact

# Unattended (good for scripts and re-installs)
winget install --id Microsoft.VisualStudioCode --exact --silent --accept-package-agreements --accept-source-agreements

# Specific version
winget install --id Microsoft.VisualStudioCode --version 1.95.0 --exact

# Install scope
winget install --id <id> --scope user      # default for most packages
winget install --id <id> --scope machine   # needs admin
```

Confirm before running `--scope machine`.

## List installed

```powershell
winget list                            # everything
winget list --id Microsoft.PowerToys   # specific
winget list --upgrade-available        # what's out of date
```

## Upgrade

```powershell
winget upgrade --id Microsoft.PowerToys --exact
winget upgrade --all                   # upgrade everything — confirm with Marty first
winget upgrade --all --include-unknown # also upgrade packages with unknown installed versions
```

`winget upgrade --all` can pull large updates (Visual Studio, Office, drivers) and reboot prompts. Don't run it autonomously — list what would change first.

## Pin (prevent upgrades)

```powershell
winget pin add --id <id> --exact            # block upgrades entirely
winget pin add --id <id> --exact --version "1.95.*"  # allow only patch upgrades
winget pin list
winget pin remove --id <id> --exact
```

Useful for tools that break with minor upgrades (e.g. specific Node/Python versions).

## Uninstall

```powershell
winget uninstall --id <id> --exact
winget uninstall --id <id> --exact --silent
```

Always confirm before uninstalling. Some packages leave config behind — note it.

## Export / import (machine snapshots)

```powershell
winget export -o C:\DATA\Workspace-37m\claude-local\backups\winget-packages.json
winget import -i C:\DATA\Workspace-37m\claude-local\backups\winget-packages.json
```

Useful before a reinstall or for replicating tooling on another machine.

## Common package IDs

Dev tooling: `Microsoft.VisualStudioCode`, `Git.Git`, `GitHub.cli`, `Microsoft.PowerShell` (pwsh 7+), `Microsoft.WindowsTerminal`, `Microsoft.PowerToys`, `OpenJS.NodeJS.LTS`, `Python.Python.3.12`, `GoLang.Go`, `Rustlang.Rustup`, `Docker.DockerDesktop`, `JetBrains.Toolbox`.

Browsers: `Mozilla.Firefox`, `Google.Chrome`, `Brave.Brave`.

Utilities: `7zip.7zip`, `Notepad++.Notepad++`, `voidtools.Everything`, `Microsoft.Sysinternals.ProcessExplorer`, `WinDirStat.WinDirStat`.

Always verify with `winget search --id <guess> --exact` before installing — IDs occasionally change.

## Source health

```powershell
winget source list
winget source update          # refresh package index
winget source reset --force   # last resort if sources are broken
```
