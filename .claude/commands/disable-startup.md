Disable a startup item (service / Run entry / processes) reversibly, with a backup first. Argument: `$ARGUMENTS` — a preset name (e.g. `logi`, `LogiOptionsPlus`) or a plain-English description of what to disable.

This is the **action** counterpart to `/startup` (which only audits). Windows-only.

Steps:

1. **Resolve the target.**
   - If `$ARGUMENTS` names or clearly maps to a preset in `disable-startup-item.ps1` (e.g. "logi", "logitech", "options+" → `LogiOptionsPlus`), use `-Preset <name>`.
   - Otherwise treat it as ad-hoc: run `.\tools\windows\startup\startup-inventory.ps1` (or use the `windows-startup-management` skill's triage) to find the exact service name / Run value name / process name, then build the `-Service` / `-RunEntry` / `-RunHive` / `-KillProcess` arguments. Do not guess registry/service names — verify them against the inventory first.
   - If the item is in the skill's **Tier 3 "don't touch"** list (work EDR/RMM, load-bearing drivers, things the user actively uses), stop and warn instead of disabling.

2. **Preview.** Run the tool with `-DryRun` first and show Marty the planned actions and the current state.

3. **Confirm.** Service and HKLM Run changes are machine-wide — per `CLAUDE.md`, get an explicit "go ahead" before applying. (HKCU-only / process-only changes are reversible and can proceed with normal care.)

4. **Apply.** Run the tool for real (it backs up to `backups/windows/registry/` first):
   ```powershell
   .\tools\windows\startup\disable-startup-item.ps1 -Preset <name> [-SaveLog]
   ```
   If you're not in an elevated shell and the change needs admin, the tool prints a ready-to-paste `Start-Process … -Verb RunAs` block — hand that to the user rather than auto-elevating.

5. **Verify.** The tool prints post-state; if useful, re-run `.\tools\windows\startup\startup-inventory.ps1` to confirm.

6. **App-level follow-up.** Some apps re-register their Run key/service on next launch unless their own "launch at startup" setting is unchecked (e.g. Logi Options+ → Settings → "Open at startup"; Adobe Creative Cloud → Preferences → "Launch at login"). Mention this where relevant.

To reverse any of this later: same invocation plus `-Undo` (sets services back to Automatic + Started, re-enables the Run entry).
