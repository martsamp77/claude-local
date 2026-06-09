# Linux performance diagnostics — `tools/linux/diagnostics/`

Native bash snapshot for a slow/unresponsive Linux box. For *intermittent* slowdowns, use the
portable capture/analyze pair in [`tools/unix/diagnostics/`](../../unix/diagnostics/README.md).

> 🧰 **All repo tools:** [root README → Tools](../../../README.md#tools)
> 🧠 **Interpretation:** the [`linux-perf-diagnosis`](../../../.claude/skills/linux-perf-diagnosis/SKILL.md) skill;
> the [`/perf`](../../../.claude/commands/perf.md) command runs this on `linux` and interprets it.

## Scripts

| Script | What it does | Key params |
|---|---|---|
| [`perf-snapshot.sh`](perf-snapshot.sh) | One-shot snapshot: distro, kernel, load, CPU, RAM, swap, disk, top processes by CPU+RAM, known-hog check | `-t TOP` (default 15), `-l` (save log) |

## Quick start

```bash
./tools/linux/diagnostics/perf-snapshot.sh -t 20 -l
```

## Notes

- `-l` saves the snapshot to `logs/linux/diagnostics/` (git-ignored).
- Slowness that "comes and goes"? Capture it over time with
  [`tools/unix/diagnostics/perf-capture.sh`](../../unix/diagnostics/README.md), then `perf-analyze.sh`.
