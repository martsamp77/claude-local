# macOS performance diagnostics — `tools/macos/diagnostics/`

Native bash snapshot for a slow Mac / beachballs / fan noise. For *intermittent* slowdowns, use the
portable capture/analyze pair in [`tools/unix/diagnostics/`](../../unix/diagnostics/README.md).

> 🧰 **All repo tools:** [root README → Tools](../../../README.md#tools)
> 🧠 **Interpretation:** the [`macos-perf-diagnosis`](../../../.claude/skills/macos-perf-diagnosis/SKILL.md) skill;
> the [`/perf`](../../../.claude/commands/perf.md) command runs this on `darwin` and interprets it.

## Scripts

| Script | What it does | Key params |
|---|---|---|
| [`perf-snapshot.sh`](perf-snapshot.sh) | One-shot snapshot: hardware, model + chip (Apple Silicon perf/efficiency cores), memory (`vm_stat`), swap, disks, power/battery, top by CPU+RAM, Mac-specific known-hog check (`kernel_task`, `WindowServer`, `mds_stores`, …) | `-t TOP` (default 15), `-l` (save log) |

## Quick start

```bash
./tools/macos/diagnostics/perf-snapshot.sh -t 20 -l
```

## Notes

- `-l` saves the snapshot to `logs/macos/diagnostics/` (git-ignored).
- Beachballs that "come and go"? Capture over time with
  [`tools/unix/diagnostics/perf-capture.sh`](../../unix/diagnostics/README.md), then `perf-analyze.sh`.
