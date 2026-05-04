---
name: completing-an-improvement
description: Use after successfully adding or improving a tool, skill, command, or staging file in this repo. Verifies the change, updates docs, commits with a great message, and pushes to origin.
---

# completing-an-improvement

End-to-end ship cycle for improvements made to **this repo** (`claude-local`). When a change demonstrably works, this skill carries it from "done in the working tree" to "pushed and documented" without dropping any of the conventions.

## When to invoke

Trigger this skill when **all** of these are true:
- You added a new tool, skill, command, or staging file — OR materially improved an existing one (new feature, behavior change, important fix).
- The change has been verified to actually work (smoke-tested, output looks right, no broken paths).
- The work is in `claude-local`. (Other repos have their own conventions.)

Skip this skill when:
- The task was purely conversational (no files changed).
- The work is partially done — you're still iterating.
- The change is a trivial typo with no behavior implications and no doc impact.
- The user has explicitly said don't push.

## The lifecycle

1. **Verify** — smoke-test the change.
   - New script: run it once and confirm output / log file appears.
   - New skill: read it back; confirm the trigger description makes sense and the body matches what was implemented.
   - New slash command: confirm the file exists and references real tools/skills.
   - Staging file: confirm syntax with the relevant validator if one exists (e.g. for `.nss`, the `nilesoft-shell` skill).
   Don't proceed past failed verification — fix it first.

2. **Update documentation** — README.md tables and the corresponding lists in CLAUDE.md.
   - Skills → README.md "Skills" table + CLAUDE.md "Existing skills" list.
   - Tools → README.md "Tools" table.
   - Commands → README.md "Commands" table + CLAUDE.md "Existing commands" list.
   - Repo layout changes → README.md tree diagram.
   - Cross-check: every new artifact appears in *every* place it should, with an accurate one-line description.

3. **Stage explicitly** — `git add` files by name. Never `git add .` or `git add -A`. The repo's `.gitignore` already excludes `backups/` and `logs/`, but explicit staging keeps it foolproof.

4. **Compose the commit message** — see the "Great commit message" section below. Pass it via heredoc to preserve formatting.

5. **Commit** — include the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer. Don't `--amend`. Don't `--no-verify`.

6. **Push** — `git push origin <branch>`. If the push would require force, abort and warn the user — don't force.

The `/ship` slash command already implements steps 3–6 with the doc check. From inside this skill, the cleanest path is: do step 1 yourself, then invoke `/ship` for the rest. `/ship` will redo the doc check defensively, which is fine.

## Great commit message

A great message tells a future reader — including future-you six months from now — **why** this change exists, **what** it does, and any **key technical detail** they'd want without re-reading the diff.

Structure:

- **Subject line** (under 72 chars, imperative mood). Captures the headline. Not "Update files"; not "Misc changes". Examples that work: `Add startup-management skill, /startup command, and startup audit tools` / `Expand perf-snapshot with VM identification and new hogs from session` / `Add tools/ layer, performance-diagnosis skill, and /perf command`.
- **Blank line.**
- **Body** — 2–6 lines for small changes, longer when warranted. Lead with the motivation (one sentence on *why* this exists), then enumerate what changed. Call out non-obvious decisions, machine-specific behavior, or trade-offs.
- **Co-Authored-By trailer.**

Hallmarks of a great message vs. a fine one:
- Names the *why*, not just the *what*. ("Captures the session's work auditing startup items into reusable assets" beats "Add startup files".)
- Flags non-obvious decisions ("filtering by path substring was unreliable; switched to non-svchost predicate").
- References constraints or quirks the future reader should know (vendor weirdness, scheduled-task reappearance, elevation requirements).
- No marketing words. No emojis. Substance over flourish.

Reference: the recent `Add startup-management...` and `Expand perf-snapshot...` commits in `git log` set the tone — read those before writing a new one.

## Safety

- **Never force-push.** If a push would require force, stop and ask the user.
- **Never disable hooks** (`--no-verify`, `--no-gpg-sign`). If a hook fails, fix the root cause.
- **Never bundle unrelated work.** If the working tree has changes that aren't part of this improvement, stage only the improvement's files and tell the user about the leftover changes.
- **Verification before assertion.** Don't claim the improvement works unless you've actually run it.
