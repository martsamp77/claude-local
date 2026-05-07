---
name: macos-env-vars
description: "[macos] Read and persist macOS environment variables across zsh files, /etc/paths, and GUI app launch. Use whenever a task touches env vars beyond the current shell."
---

# macos-env-vars

Use this skill for any task that needs an env var to survive the current shell. macOS uses zsh by default since Catalina, so this skill is zsh-first; bash sections are noted where they differ.

## The zsh hierarchy

zsh reads files in a specific order depending on shell type. The order matters because each file can override the previous:

| File | Read by | Sourced when |
|---|---|---|
| `/etc/zshenv` | EVERY shell | always (system-wide) |
| `~/.zshenv` | EVERY shell | always (per-user) |
| `/etc/zprofile` | login shells | once at login |
| `~/.zprofile` | login shells | once at login |
| `/etc/zshrc` | interactive shells | each interactive shell |
| `~/.zshrc` | interactive shells | each interactive shell |
| `/etc/zlogin` | login shells | end of login (rarely used) |
| `~/.zlogin` | login shells | end of login |

**Rule of thumb:**
- `~/.zprofile` — env vars and PATH adjustments that GUI apps + Terminal both need at login. Most personal env config lives here.
- `~/.zshrc` — aliases, prompt, completion, interactive things. NOT for GUI-relevant env vars (GUI apps don't read it).
- `~/.zshenv` — read by every zsh including non-interactive scripts. Keep minimal; can hurt script perf.

For bash users (older Macs / `bash` explicitly): the equivalents are `~/.bash_profile` (login) and `~/.bashrc` (interactive). macOS Terminal opens login shells by default, so `.bash_profile` is what runs.

## Where macOS looks for PATH

macOS has its own PATH-building system at login: `path_helper`, configured by:

- `/etc/paths` — one absolute path per line (in order of priority).
- `/etc/paths.d/<name>` — drop-in files, one path per line.
- `/etc/manpaths` and `/etc/manpaths.d/` — same idea for `MANPATH`.

`path_helper` runs from `/etc/zprofile` and assembles `PATH` from these files. Anything you put in `/etc/paths.d/<name>` is system-wide and survives reinstalls cleanly.

To see what `path_helper` produces:

```bash
/usr/libexec/path_helper -s
```

## Read

```bash
echo "$PATH"
printenv PATH
env | sort
launchctl getenv PATH         # what GUI app launches inherit (older versions of macOS)
```

GUI app environment is a separate world — see "GUI app environment" below.

## Write — per-user

For env vars that should reach GUI apps + Terminal, put them in `~/.zprofile` (zsh) or `~/.bash_profile` (bash):

```zsh
# ~/.zprofile
export EDITOR=nvim
export PAGER=less
export GO111MODULE=on
```

For terminal-only / interactive vars, `~/.zshrc`.

After editing, open a new Terminal window — or `source ~/.zprofile` in the current one. **GUI apps won't see the change until you log out and back in** (they inherit env at process start).

## Write — system-wide PATH

The cleanest way to add a system-wide PATH entry is a drop-in:

```bash
# /etc/paths.d/mycorp
sudo tee /etc/paths.d/mycorp >/dev/null <<'EOF'
/opt/mycorp/bin
EOF
```

Reboot or log out + back in to apply (path_helper runs at login).

For env vars (not PATH), `/etc/zshenv` is the system-wide place — but it's read by every zsh, including scripts, so be careful with side effects:

```zsh
# /etc/zshenv
export MYCORP_API_URL=https://api.mycorp.example
```

Per CLAUDE.md, **back up `/etc/paths`, `/etc/paths.d/<name>`, or `/etc/zshenv` to `backups/macos/defaults/<ts>/` before edits**, and confirm system-wide writes with Marty.

## PATH editing pattern (zsh)

zsh has a parallel array `path` synced with `PATH`. Use it:

```zsh
typeset -U path                           # auto-dedupe
path=(~/bin /opt/homebrew/bin $path)      # prepend (Apple Silicon)
path=(~/bin /usr/local/bin   $path)       # prepend (Intel)
```

For a one-off conditional:

```zsh
[[ -d /opt/homebrew/bin ]] && path=(/opt/homebrew/bin $path)
[[ -d /usr/local/bin   ]] && path=(/usr/local/bin   $path)
```

This belongs in `~/.zprofile` so GUI Terminal sessions and login shells both pick it up.

## Apple Silicon vs Intel Homebrew on PATH

Apple Silicon Macs install Homebrew under `/opt/homebrew`. Intel under `/usr/local`. Both binaries dirs need to be on PATH; Homebrew's installer adds the right one to `~/.zprofile` automatically:

```zsh
eval "$(/opt/homebrew/bin/brew shellenv)"   # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"      # Intel
```

If you've migrated machines and PATH looks weird, this is usually why.

## GUI app environment (the tricky part)

GUI apps launched from Finder, Spotlight, Dock, or Launchpad **do not read `~/.zprofile`**. Their environment comes from `launchd`. Setting an env var there:

```bash
# Sets the variable for any new GUI process started in this session
launchctl setenv MYVAR somevalue

# Persist across reboots: a LaunchAgent that runs setenv
# (heavy-handed; usually only needed for things like JAVA_HOME for IntelliJ)
```

Modern macOS: a per-user LaunchAgent that runs `launchctl setenv ...` at login is the pattern. Older `~/.MacOSX/environment.plist` and `/etc/launchd.conf` no longer work as of OS X 10.10+.

For most cases, if your GUI app reads PATH, just relying on `path_helper` (`/etc/paths.d/`) is enough. For app-specific vars (JAVA_HOME, GO_PATH), most modern apps respect the user shell config when launched from Terminal — the cleanest fix is to launch the app from Terminal (`open -a "AppName"` or just `code .`) so it inherits your shell env.

## Reload after edits

| Edit | How to apply |
|---|---|
| `~/.zshrc` | `source ~/.zshrc` or new terminal |
| `~/.zprofile` | new terminal session; for GUI: log out + back in |
| `~/.zshenv` | new shell (any) |
| `/etc/paths` or `/etc/paths.d/*` | log out + back in (path_helper at login) |
| `/etc/zshenv` | new shell session-wide |
| `launchctl setenv X Y` | new GUI processes (existing ones don't see it) |

## Remove a var

`unset NAME` in current shell. For persistence, find and delete the line from whichever file set it:

```bash
grep -n NAME ~/.zshrc ~/.zprofile ~/.zshenv /etc/paths /etc/paths.d/* /etc/zshenv 2>/dev/null
```

## Safety

- **Don't put secrets in `/etc/zshenv` or `/etc/paths`** — they're world-readable. Per-user files (`chmod 600 ~/.zprofile`) are safer.
- **Don't shell-expand inside `/etc/paths` or `/etc/paths.d/*`** — they're plain absolute paths, not shell scripts.
- **Test PATH edits in a subshell first:** `zsh -l -c 'echo $PATH'` reproduces a login shell's PATH.
- **Apple Silicon: do not blindly copy an Intel `~/.zprofile`** — the Homebrew prefix is different. Re-run the Homebrew installer command on the new Mac and let it write the correct line.
- **Backup `/etc/paths`, `/etc/paths.d/*`, `/etc/zshenv` to `backups/macos/defaults/<ts>/`** before editing.
