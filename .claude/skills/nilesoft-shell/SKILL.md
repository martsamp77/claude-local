---
name: nilesoft-shell
description: Manage Nilesoft Shell — Windows context-menu replacement. Edit shell.nss configs, change theme, add/modify items, register/unregister via CLI, reload after changes.
---

# nilesoft-shell

Use this skill when Marty wants to customize his Windows context menus via Nilesoft Shell — adjust theme, add custom items, modify or remove system entries, change dark mode behavior, or register/unregister the extension.

## Where things live

- **Install dir:** `C:\Program Files\Nilesoft Shell\` — under `Program Files`, so **edits need an elevated shell** (admin).
- **Main config:** `C:\Program Files\Nilesoft Shell\shell.nss` — entry point. Imports modular files.
- **Modular configs:** `C:\Program Files\Nilesoft Shell\imports\*.nss` — `theme.nss`, `images.nss`, `modify.nss`, `terminal.nss`, `file-manage.nss`, `develop.nss`, `goto.nss`, `taskbar.nss`, plus `lang/<locale>.nss`.
- **Runtime log:** `C:\Program Files\Nilesoft Shell\shell.log` — read-only; check it for config parse errors. Don't edit.
- **Reference docs:** `C:\DATA\Workspace-public\Shell\docs\` (HTML). Authoritative for syntax, settings, themes, expressions, functions.

## Backup before editing

Always copy the file (or the whole `Nilesoft Shell\` dir) to `C:\DATA\Workspace-37m\claude-local\backups\nilesoft\<timestamp>\` before changes. The dir needs admin to write but anyone can read — `Copy-Item` from a normal shell works for backup.

```powershell
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$bk = "C:\DATA\Workspace-37m\claude-local\backups\nilesoft\$ts"
New-Item -ItemType Directory -Path $bk -Force | Out-Null
Copy-Item "C:\Program Files\Nilesoft Shell\shell.nss" $bk
Copy-Item "C:\Program Files\Nilesoft Shell\imports" $bk -Recurse
```

## CLI (run elevated)

`shell.exe` lives at `C:\Program Files\Nilesoft Shell\shell.exe`. Verified flags:

| Flag | Effect |
|---|---|
| `-register` | Register the shell extension. |
| `-unregister` | Unregister. |
| `-treat` | Disable the Windows 11 modern (compact) context menu so Nilesoft fully replaces it. |
| `-silent` | Suppress message dialogs (use for unattended runs). |
| `-restart` | Restart Windows Explorer after the operation. |
| `-?` | Show help. |

Common combos:

```powershell
# First-time install / re-register, take over Win11 menu, restart Explorer, no popups
& "C:\Program Files\Nilesoft Shell\shell.exe" -register -treat -restart -silent

# Remove
& "C:\Program Files\Nilesoft Shell\shell.exe" -unregister -restart -silent
```

There is **no `-reload` flag**. To pick up edits to `shell.nss` after the extension is already registered, restart Explorer:

```powershell
Stop-Process -Name explorer -Force   # auto-restarts
```

Or use a context-menu item that runs `@app.reload()` if one is configured. `app.reload`, `app.unload`, `app.cfg` are functions you invoke from inside `.nss`, not CLI flags.

## .nss syntax — what to know

Plain text, case-insensitive. Comments with `//`. Blocks use `{ }`. Variables `$name = value`. Image references `@image_id`. Strings can be plain or expressions in single quotes (`'...'`).

Top-level constructs in `shell.nss`:

- `settings { ... }` — global behavior (showdelay, exclude.where, tip.*, modify.*, new.*).
- `theme { ... }` — appearance (handled in `imports/theme.nss` by default).
- `import 'imports/<file>.nss'` — pull in a modular file.
- `modify(find=... where=...) { ... }` — change/move/remove existing system items.
- `remove(find=...)` — strip an item.
- `item(...)`, `menu(...)`, `separator` — add new entries.

Each item supports properties like `title`, `cmd`, `image`, `where`, `keys`, `admin`, `mode`, `position`, `parent`, `col`, `vis`. See `C:\DATA\Workspace-public\Shell\docs\configuration\properties.html` for the full list.

## Common tasks

**Switch to dark mode (theme.nss):**

```nss
theme
{
    name = "modern"
    dark = true       // or auto / false
    background.effect = 3   // 0 none, 1 transparent, 2 blur, 3 acrylic
}
```

**Hide an item from the system menu (modify.nss):**

```nss
modify(find='Restore previous versions' menu=true) // moves it into 'more options'
remove(find='Cast to Device')                       // removes outright
```

**Add a custom item that opens a shell here:**

```nss
item(title='PowerShell here' image=icon.terminal cmd='pwsh.exe' arg='-NoExit -NoProfile' admin=key.shift())
```

**Set the menu font:**

```nss
theme
{
    font.name = "Segoe UI Variable"
    font.size = 9
    font.weight = 4
}
```

## Apply changes

1. Backup (above).
2. Edit `shell.nss` or the relevant `imports\*.nss` (needs admin — open VS Code as admin, or use `Start-Process notepad -Verb RunAs <path>`).
3. Restart Explorer: `Stop-Process -Name explorer -Force`.
4. Right-click somewhere to verify.
5. If the menu didn't update or items are missing, check `C:\Program Files\Nilesoft Shell\shell.log` for parse errors.

## Don't

- Don't edit `shell.log`.
- Don't run `-unregister` without confirming with Marty — it strips the extension and reverts to the default Windows menu until re-registered.
- Don't add destructive commands (e.g. `del`, `format`) to `cmd=` items without explicit ask — context-menu entries fire on a single click.
- Don't blanket-replace `imports\*.nss` with versions from the public repo without diffing first — the installed copies may have local edits.
