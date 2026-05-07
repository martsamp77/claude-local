---
name: linux-env-vars
description: "[linux] Read and persist Linux environment variables across shells, sessions, and login types; edit PATH safely. Use whenever a task touches env vars beyond the current shell."
---

# linux-env-vars

Use this skill when a task needs to set or change environment variables that survive the current shell. **Don't** use `export NAME=value` for persistence — that only sets it in the current shell.

The right file depends on whether the variable is per-user vs system-wide and whether it must apply to login shells, interactive shells, GUI sessions, or all of them.

## Where Linux looks for env vars

| File | Read by | Best for |
|---|---|---|
| `~/.profile` | login shells (bash + sh fallback), GUI sessions on most desktops | per-user, applies everywhere including GUI apps |
| `~/.bashrc` | non-login interactive bash | per-user shell-only — aliases, prompt, vars used in terminals |
| `~/.bash_profile` | login bash (overrides `~/.profile` if present) | rare; usually just `source ~/.profile` and `source ~/.bashrc` |
| `~/.zshrc` | interactive zsh | per-user, zsh equivalent of `.bashrc` |
| `~/.zprofile` / `~/.zlogin` | login zsh | zsh equivalent of `.profile` |
| `/etc/environment` | systemd PAM (login + GUI) | system-wide, parsed line-by-line as `KEY=value` (no shell syntax) |
| `/etc/profile` | system-wide login shells | system-wide; sources `/etc/profile.d/*.sh` |
| `/etc/profile.d/*.sh` | system-wide login shells | system-wide drop-ins |

**Rule of thumb for per-user vars:**
- Going to be used by GUI apps + terminals → `~/.profile` (bash) or `~/.zprofile` (zsh).
- Only needed in terminals → `~/.bashrc` / `~/.zshrc`.

## Read

```bash
echo "$NAME"                # current shell
printenv NAME               # only env-exported, not just set
env                         # everything in this process
env -0 | tr '\0' '\n' | sort  # sorted, handles multiline values

# What did login set vs. what did .bashrc add?
ssh user@host -t 'env' > login.env       # login shell env
ssh user@host -t 'bash -i -c env' > interactive.env
diff login.env interactive.env
```

## Write — per-user

Append to `~/.profile` (or `~/.zprofile`) for vars that should be visible to GUI apps too:

```bash
# ~/.profile
export EDITOR=nvim
export PAGER=less
export GO111MODULE=on
```

Append to `~/.bashrc` (or `~/.zshrc`) for vars only needed in interactive shells:

```bash
# ~/.bashrc
export PROMPT_COMMAND='history -a'
```

After editing, `source ~/.profile` (or open a new terminal) to apply. **GUI sessions only re-read `~/.profile` on logout/login** — for GUI-relevant vars, log out + back in.

## Write — system-wide

`/etc/environment` is the cleanest spot for system-wide vars that should reach GUI apps. It's parsed by PAM, NOT executed as shell — no `export`, no shell expansion, no `$VAR` interpolation:

```
# /etc/environment
EDITOR=nvim
JAVA_HOME=/usr/lib/jvm/default-java
```

For shell-only system-wide vars, drop a file under `/etc/profile.d/`:

```bash
# /etc/profile.d/mycorp.sh
export MYCORP_API_URL=https://api.mycorp.example
```

Per CLAUDE.md, **back up `/etc/environment` or the existing profile.d file to `backups/linux/etc/<ts>/` before editing**, and confirm system-wide changes with Marty before each write.

## PATH editing

PATH is a colon-separated list. The split-dedupe-rewrite pattern, in bash:

```bash
# Add ~/bin to PATH if not already there (idempotent)
case ":$PATH:" in
    *":$HOME/bin:"*) ;;
    *) export PATH="$HOME/bin:$PATH" ;;
esac
```

For persistence, append the case-statement to `~/.profile` (per-user, GUI + terminal) or to `/etc/profile.d/<name>.sh` (system-wide).

To dedupe a tangled PATH (no shell function calls):

```bash
PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '!seen[$0]++' | sed 's/:$//')
```

For zsh, prefer the `path` array:

```zsh
typeset -U path                 # auto-dedupe
path=(~/bin /usr/local/bin $path)
```

## Remove a var

`unset NAME` in the current shell. For persistence, find and delete the line from whichever file set it (`grep -rn 'NAME' ~/.profile ~/.bashrc /etc/environment /etc/profile.d/`).

## Reload after edits

| Edit | How to apply |
|---|---|
| `~/.bashrc` | `source ~/.bashrc` or open a new terminal |
| `~/.profile` | new login shell; for GUI: log out + back in |
| `~/.zshrc` | `source ~/.zshrc` or new terminal |
| `/etc/environment` | log out + back in (no live reload) |
| `/etc/profile.d/*.sh` | new login shell session-wide |

There is no `WM_SETTINGCHANGE`-style live broadcast on Linux. GUI apps inherit env at launch — restart the app (or the whole session) for env changes to take effect.

## Safety

- **Don't put secrets in `/etc/environment`** — it's world-readable. Use `~/.profile` (mode 0600) or a secret manager.
- **Don't edit `/etc/environment` with shell syntax** — no `export`, no `$VAR`. PAM doesn't run a shell on this file; it just reads `KEY=value` lines.
- **Always quote values with spaces or special chars:** `MY_VAR="some value with spaces"`.
- **Test PATH edits in a subshell first:** `bash -c 'source ~/.profile; echo $PATH'` before opening a new login session.
- **Backup before editing system-wide files** to `backups/linux/etc/<ts>/`.
