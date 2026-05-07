# claude-local

Personal Claude Code workspace for administering Marty's machines — system settings, environment, software, services, scheduled jobs, dev tooling. One git checkout, synced across Windows, Linux, and macOS. Sysadmin-style asks; not an application.

When Marty opens Claude Code in this directory on any machine, `CLAUDE.md` is auto-loaded. It detects the current OS from session context and tells Claude which skills, tools, and commands are eligible. Conversations pick up the conventions and tool knowledge without re-explaining each session.

## OS support matrix

| OS | Status | Skills available | Tools available |
|---|---|---|---|
| Windows 11 | ✅ Full | 10 (`windows-*`, `winget-packages`, `nilesoft-shell`, `dev-environment`) | 4 (perf, startup) |
| Linux | 🚧 Skeleton planned | none yet (Phase 3) | none yet |
| macOS | 🚧 Skeleton planned | none yet (Phase 4) | none yet |
| WSL | ↪ Treated as Linux | inherits Linux scope; flags `/mnt/c/...` writes | inherits Linux |
| All OSes | ✅ | `completing-an-improvement` | `/ship` command |

Each skill description starts with a `[scope]` tag — `[windows]`, `[linux]`, `[macos]`, `[unix]` (Linux+macOS), or `[all]`. Claude filters by current OS automatically; see the **Detect your platform first** section in `CLAUDE.md`.

## What this is

Three layers:

- **Skills** (`.claude/skills/`) — instruction files that tell Claude how to approach a task domain. Scope-tagged so Claude only uses ones that match the current OS.
- **Tools** (`tools/<os>/`) — executable scripts Claude can run directly (PowerShell on Windows, bash on Linux/macOS). Self-describing via header comments; Claude discovers them automatically via the Tool inventory section of `CLAUDE.md`.
- **Commands** (`.claude/commands/`) — slash commands that trigger multi-step workflows (e.g. `/perf`).

What it intentionally does **not** contain:

- No application code, build tooling, or tests.
- No persistent memory — that lives at `~/.claude/projects/<slug>/memory/`, outside this repo.

## Layout

```
claude-local/
├── CLAUDE.md                          # Workspace orientation + tool discovery instructions (auto-loaded)
├── README.md                          # You are here
├── .gitignore                         # Excludes backups/ and logs/
├── .claude/
│   ├── settings.local.json            # Per-project Claude Code permissions
│   ├── commands/                      # Slash commands
│   │   └── perf.md                    # /perf — snapshot + interpret
│   └── skills/                        # Domain skills, auto-discovered by name
│       ├── windows-registry/                # [windows]
│       ├── windows-env-vars/                # [windows]
│       ├── winget-packages/                 # [windows]
│       ├── windows-services/                # [windows]
│       ├── windows-scheduled-tasks/         # [windows]
│       ├── windows-system-settings/         # [windows]
│       ├── dev-environment/                 # [windows] (split planned)
│       ├── nilesoft-shell/                  # [windows]
│       ├── windows-perf-diagnosis/          # [windows]
│       ├── windows-startup-management/      # [windows]
│       └── completing-an-improvement/       # [all]
├── tools/                             # Executable scripts, organized by OS
│   ├── windows/                       # PowerShell — .ps1
│   │   ├── diagnostics/
│   │   │   ├── perf-snapshot.ps1      # One-shot system snapshot
│   │   │   └── perf-watch.ps1         # Continuous threshold monitor
│   │   └── startup/
│   │       ├── startup-inventory.ps1  # Read-only audit of every startup vector
│   │       └── inspect-task.ps1       # Deep-dive on named scheduled task(s)
│   ├── linux/                         # bash — .sh (Phase 3)
│   ├── macos/                         # bash — .sh (Phase 4)
│   └── unix/                          # portable bash for Linux + macOS
├── staging/                           # Edits ready to copy into protected dirs (elevated)
│   ├── windows/
│   │   ├── nilesoft/
│   │   │   ├── shell.nss
│   │   │   └── imports/
│   │   └── registry/
│   ├── linux/                         # systemd units, dotfiles, etc. (as needed)
│   └── macos/                         # plists, defaults exports (as needed)
├── logs/                              # GIT-IGNORED. Output from -SaveLog runs.
│   ├── windows/
│   ├── linux/
│   └── macos/
└── backups/                           # GIT-IGNORED. Timestamped snapshots before edits.
    ├── windows/
    ├── linux/
    └── macos/
```

## Skills

### Windows (`[windows]`)

| Skill | What it covers |
|---|---|
| [`windows-registry`](.claude/skills/windows-registry/SKILL.md) | Reading/writing the registry safely; `reg export` backup pattern; HKCU vs HKLM scope rules |
| [`windows-env-vars`](.claude/skills/windows-env-vars/SKILL.md) | User vs Machine env vars; PATH split-dedupe-rewrite pattern; `WM_SETTINGCHANGE` broadcast |
| [`winget-packages`](.claude/skills/winget-packages/SKILL.md) | Search/install/upgrade/list/pin/uninstall; export/import for snapshots |
| [`windows-services`](.claude/skills/windows-services/SKILL.md) | `Get-Service` / `Set-Service`; startup type; critical-service warning list |
| [`windows-scheduled-tasks`](.claude/skills/windows-scheduled-tasks/SKILL.md) | `Register-ScheduledTask`; logon vs daily vs startup triggers; SYSTEM vs interactive |
| [`windows-system-settings`](.claude/skills/windows-system-settings/SKILL.md) | Common Win11 tweaks (Explorer, taskbar, dark mode, privacy); restart-Explorer pattern |
| [`dev-environment`](.claude/skills/dev-environment/SKILL.md) | git config, SSH keys, WSL setup, Node/Python/Go/Rust/.NET install; PowerShell `$PROFILE`. (Will be split into `windows-dev-environment` and `unix-dev-environment` in Phase 5.) |
| [`nilesoft-shell`](.claude/skills/nilesoft-shell/SKILL.md) | `.nss` syntax; CLI flags; runtime modifier shortcuts; reload mechanics |
| [`windows-perf-diagnosis`](.claude/skills/windows-perf-diagnosis/SKILL.md) | Diagnose slow/unresponsive machine; interpret snapshot output; known hogs and fixes |
| [`windows-startup-management`](.claude/skills/windows-startup-management/SKILL.md) | Audit startup items across Run keys / folders / scheduled tasks / services; triage tiers; disable patterns |

### Linux (`[linux]`)

_None yet — planned in Phase 3: `linux-systemd`, `linux-packages` (apt/dnf/pacman), `linux-env-vars`, `linux-perf-diagnosis`._

### macOS (`[macos]`)

_None yet — planned in Phase 4: `macos-launchd`, `macos-homebrew`, `macos-defaults`, `macos-env-vars`, `macos-perf-diagnosis`._

### Cross-platform (`[all]`)

| Skill | What it covers |
|---|---|
| [`completing-an-improvement`](.claude/skills/completing-an-improvement/SKILL.md) | End-to-end ship cycle for a verified repo improvement: smoke-test, doc updates, commit (with great-message guide), push |

## Tools

Scripts Claude can run directly. All paths are relative — no hardcoded machine paths. Filtered by `.PLATFORM` against the current OS.

### Windows (`tools/windows/`)

| Script | What it does | Key params |
|---|---|---|
| `tools/windows/diagnostics/perf-snapshot.ps1` | One-shot snapshot: CPU, RAM, disk, pagefile, power plan, top processes, known-hog check | `-Top <n>`, `-SaveLog` |
| `tools/windows/diagnostics/perf-watch.ps1` | Continuous monitor; highlights processes crossing CPU % or RAM MB thresholds | `-IntervalSec`, `-CpuThreshold`, `-RamThresholdMb` |
| `tools/windows/startup/startup-inventory.ps1` | Read-only audit: Run keys (incl. WOW6432), startup folders, logon/boot tasks, auto-start services, with enable/disable state | `-IncludeMicrosoftTasks`, `-SaveLog` |
| `tools/windows/startup/inspect-task.ps1` | Show full details of named scheduled task(s): action, principal, triggers | `-Name <task>[,<task>...]` |

### Linux (`tools/linux/`) and macOS (`tools/macos/`)

_None yet — planned in Phases 3 & 4. Linux/macOS perf-snapshot equivalents will mirror the Windows version's section structure but use `top`/`free`/`/proc` (Linux) and `top -l 1`/`vm_stat` (macOS)._

## Commands

| Command | OS scope | What it does |
|---|---|---|
| `/perf` | Windows (Linux/macOS planned) | Run perf-snapshot, interpret output, return top issues + recommended actions |
| `/startup` | Windows only | Run startup-inventory, classify items into disable / investigate / leave-alone tiers, stage commands |
| `/ship` | All | Commit any uncommitted work (with doc check) and push to the remote |

## How a session typically works

1. Open Claude Code in this directory on whichever machine you're on.
2. Claude reads `Platform: win32 | linux | darwin` from the session's system reminder and filters skills/tools to the matching `[scope]`.
3. Ask in natural language — "why is my machine slow", "remove the AMD entry from the right-click menu", "set up scheduled defrag at 3am" (Windows); "what's holding port 8080" / "make this systemd unit start at boot" (Linux); etc.
4. For changes that need elevation (Windows: HKLM, services, machine env vars, `Program Files`; Linux/macOS: anything under `/etc`, system units, system-wide installs): Claude proposes the change, stages files in `staging/<os>/<area>/`, takes a backup in `backups/<os>/<area>/<timestamp>/`, and prints a one-line elevated command for you to paste into an admin/sudo shell.
5. Reversible local changes (per-user registry, user env vars, user packages, dotfile edits, file ops) execute directly.
6. When performance/slowness/resource issues come up, Claude auto-discovers `tools/<os>/diagnostics/` scripts and runs the appropriate one.

## Conventions

Every OS:
- **Honor the `[scope]` tag.** Don't reach for a Windows skill on Linux, or vice versa.
- **Back up before destructive edits.** Snapshot to `backups/<os>/<area>/<ts>/...`.
- **Don't auto-elevate.** Stage and hand back the `Start-Process -Verb RunAs` / `sudo ...` command.
- **Note the inverse** of any forward operation.
- **All tool scripts use relative paths via `$PSScriptRoot` (PS) or `$(dirname "$0")` (bash).** Never hardcode absolute paths to the repo.

OS-specific safety rules live in `CLAUDE.md` under **Per-OS conventions** — those override or extend the above for HKLM (Windows), `/etc/` and systemd (Linux), and SIP/launchd (macOS).

## Adding to the workspace

**New skill:** `.claude/skills/<kebab-name>/SKILL.md` with frontmatter + body. Description must start with a `[scope]` tag (`[windows]`, `[linux]`, `[macos]`, `[unix]`, or `[all]`) — wrap in double quotes since YAML treats leading `[` as a flow sequence. Use OS-prefixed names (`windows-foo`, `linux-foo`, `macos-foo`, `unix-foo`) for OS-specific skills. Add a row to the matching subtable above and to `CLAUDE.md`.

**New tool:** `tools/<os>/<category>/<name>.ps1` (or `.sh` for Linux/macOS) with the standard header block (`.NAME`, `.SYNOPSIS`, `.PLATFORM`, `.CATEGORY`, `.USAGE`, `.WHEN`). Add a row to the tools table above. Claude discovers it automatically next session via `CLAUDE.md`.

**New command:** `.claude/commands/<name>.md` describing the workflow. Add a row to the commands table above.

## Reference

- `everything-claude-code` (at `C:\DATA\Workspace-public\everything-claude-code` if present) — blueprint repo with 300+ skills / 50+ agents / 80+ commands. Consult as a library; don't auto-pull.
- [Nilesoft Shell](https://nilesoft.org) — source of truth for `.nss` syntax used by the `nilesoft-shell` skill.
