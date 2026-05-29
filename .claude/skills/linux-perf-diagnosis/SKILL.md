---
name: linux-perf-diagnosis
description: "[linux] Diagnose Linux performance issues — slow/unresponsive machine, high CPU, RAM, or load average. Use when the user reports sluggishness on a Linux box or when interpreting perf-snapshot.sh output."
---

# linux-perf-diagnosis

Use this skill when:
- the user says the Linux machine is slow, laggy, or hung
- Interpreting output from `tools/linux/diagnostics/perf-snapshot.sh`
- Triaging which process or subsystem is the cause before recommending action

## The tool

```bash
./tools/linux/diagnostics/perf-snapshot.sh [-t TOP] [-l]
```

Produces a snapshot covering: distro/kernel, load average, memory, swap, disk usage, top processes by CPU + RAM, and a known-hogs check. `-l` saves the output to `logs/linux/diagnostics/<ts>-perf-snapshot.txt` (gitignored).

For continuous monitoring of CPU spikes, the equivalent of perf-watch is `top -d 1` or `htop` — no scripted version yet.

## What to look for

Read the snapshot top-down and flag anything in these zones:

- **Load average** > number of logical CPUs sustained → CPU saturation. A 4-core box with load 8/8/6 is overloaded; load 8/2/0.5 is a recent spike that's resolving.
- **Memory used %** ≥ 85 → memory pressure. Check whether `MemAvailable` (not `free`) is genuinely low — Linux uses RAM aggressively for cache.
- **Swap in use** at all → previous memory pressure. Steady swap-in is fine; swap-out under load is the actual problem.
- **Disk** ≥ 90% on `/`, `/var`, or `/home` → triage candidate (logs, journal, snap revisions, package cache).
- **Top by CPU** with one process > 80% sustained → that's the cause; look at `comm` and decide.
- **Top by RAM** with one process > 25% of total → restart candidate, especially browsers/IDEs.

## Common Linux hogs and recipes

| Symptom | Likely cause | Action |
|---|---|---|
| One CPU pinned at 100% via `tracker-miner-fs-3` | First-time GNOME indexer crawl | Wait it out, or `tracker3 daemon -t` to terminate |
| `baloo_file_extractor` chewing CPU on KDE | Baloo file indexer | `balooctl disable` (per-user) if you don't use Dolphin search |
| Memory pressure, `dockerd` + many `containerd-shim-*` | Containers running quietly | `docker ps`; stop ones that aren't needed; `docker system prune -a` reclaims disk |
| Swap usage growing over time, no obvious culprit | Memory leak in long-running process | Check `ps aux --sort=-rss \| head`, restart the offender |
| `snapd` doing heavy work post-boot | Snap auto-refresh | `sudo snap refresh --hold=72h` to defer |
| Disk full on `/var/log/journal` | systemd-journald growing unbounded | `sudo journalctl --vacuum-time=7d` |
| Firefox/Chromium > 4 GB RSS | Tab accumulation | Restart the browser; consider Tab Suspender/Auto Tab Discard |
| `kswapd0` busy | Memory + swap both pressured | Free RAM (kill big processes) before adding swap |

## Triage decision tree

1. **High load + high CPU on one process** → that process is the cause. Decide: kill, restart, throttle (`cpulimit`/`systemd-run --slice=user.slice -p CPUQuota=50%`), or accept.
2. **High load + no obvious CPU hog** → check `iotop` for I/O wait. Disk-bound work shows in `wa` of `top`.
3. **Memory pressure (used >85% AND swap in use)** → biggest RSS first. Restart browsers/IDEs before reaching for `oomctl`/`earlyoom`.
4. **Disk full** → biggest dirs first: `du -h --max-depth=1 / 2>/dev/null | sort -rh | head -20`. Common: `/var/log`, `/var/cache`, `/var/lib/docker`, `/home/*/.cache`.
5. **Nothing obvious in the snapshot** → run `dmesg | tail -50`, check `journalctl -p err -b` for kernel/service errors.

## Safety

- **Never** kill `init`/`systemd` (PID 1), `kthreadd`, `kworker/*`, `dbus-daemon`, `NetworkManager`, `systemd-journald`, or `sshd` — system breaks immediately.
- `kill -9` is a last resort. Send `-TERM` first; give it 5–10 seconds.
- `oom-killer` events are visible in `dmesg`. Don't disable it; tune `oom_score_adj` for the few processes you need to protect.

## Output format for `/perf` on Linux

When `/perf` runs this on Linux: read the snapshot, surface the 2–3 issues by impact, give one concrete action per issue, end with a one-line health summary. Same shape as the Windows variant — keep responses tight.
