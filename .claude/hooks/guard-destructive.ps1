<#
  guard-destructive.ps1  —  PreToolUse hook (matcher: Bash|PowerShell)

  Warns (does NOT block, does NOT auto-approve) when a proposed shell command
  matches a destructive-system-change pattern from this repo's CLAUDE.md safety
  rules. Emits `additionalContext` so the model is reminded of the rule and the
  required precaution; the normal permission prompt still happens, so Marty stays
  in control.

  Cross-platform: written in pwsh (runs on Windows, Linux, macOS). It selects the
  Windows or Unix pattern set from $IsWindows so warnings are OS-relevant.

  Contract: read hook JSON on stdin; on a match print one JSON object with
  hookSpecificOutput.additionalContext; always exit 0. Any parsing failure is
  swallowed (never break the session over a guard).
#>

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $j   = $raw | ConvertFrom-Json
    $cmd = [string]$j.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }
} catch { exit 0 }

# pattern -> reminder. Patterns are case-insensitive regex against the command text.
if ($IsWindows -ne $false) {   # Windows (also true when $IsWindows is $null on Win PowerShell 5.1)
    $rules = @(
        @{ rx = 'HKLM|HKEY_LOCAL_MACHINE';                         msg = 'HKLM (machine-wide) registry change — needs an explicit "yes go ahead" from Marty, and a `reg export` backup to backups\windows\registry\ FIRST.' }
        @{ rx = '\breg\s+delete\b';                                msg = 'reg delete — back up the key with `reg export` to backups\windows\registry\ before deleting; note the inverse.' }
        @{ rx = '(Set-ItemProperty|New-ItemProperty|Remove-Item|New-Item).*HK';  msg = 'Registry write — back it up first (windows-registry skill); HKCU is reversible, HKLM needs explicit confirmation.' }
        @{ rx = 'Set-MpPreference|DisableRealtimeMonitoring|Add-MpPreference.*Exclusion'; msg = 'Microsoft Defender change — NEVER disable Defender without an explicit instruction naming it.' }
        @{ rx = 'EnableLUA|ConsentPromptBehavior';                 msg = 'UAC change — never disable UAC without an explicit instruction naming it.' }
        @{ rx = 'SmartScreen';                                     msg = 'SmartScreen change — never disable without an explicit instruction naming it.' }
        @{ rx = '\b(wuauserv|UsoSvc|WaaSMedicSvc)\b';              msg = 'Windows Update service — never disable Windows Update without an explicit instruction.' }
        @{ rx = 'Stop-Service|Set-Service.*Disabled|Suspend-Service'; msg = 'Service stop/disable — confirm it is not critical (windows-services skill list); note how to re-enable.' }
        @{ rx = 'Unregister-ScheduledTask|Disable-ScheduledTask';  msg = 'Scheduled-task removal/disable — confirm; SYSTEM-owned tasks need explicit confirmation.' }
        @{ rx = 'winget\s+uninstall|Uninstall-Package|Uninstall-WindowsFeature'; msg = 'Uninstall — confirm before removing software (winget-packages skill).' }
        @{ rx = 'Remove-Item.*-Recurse.*-Force';                   msg = 'Recursive force delete — double-check the target path is what you think it is.' }
        @{ rx = '\bbcdedit\b|\bdiskpart\b|\bformat\b\s';           msg = 'Boot/disk/format operation — high blast radius; confirm explicitly.' }
        @{ rx = 'Start-Process.*-Verb\s+RunAs';                    msg = 'Auto-elevation — repo rule is DO NOT auto-elevate; print the command and let Marty run it in an elevated shell.' }
    )
} else {   # Linux / macOS
    $rules = @(
        @{ rx = 'rm\s+-[a-z]*r[a-z]*f?\s+(/|/etc|/usr|/bin|/boot|/var|/lib)\b'; msg = 'Recursive delete of a system path — extreme blast radius; confirm the exact target.' }
        @{ rx = '(>|>>|tee\s+-?a?\s*)\s*/etc/|sed\s+-i.*\s/etc/|\bvi(m)?\s+/etc/'; msg = 'Editing under /etc/ — back up to backups/linux|macos/etc/<ts>/ first; system-wide change needs explicit "yes".' }
        @{ rx = '/etc/(fstab|sudoers|ssh/sshd_config|passwd|shadow)';        msg = 'Critical /etc file — never edit fstab/sudoers/sshd_config without an explicit instruction naming it; back up first.' }
        @{ rx = 'systemctl\s+(disable|mask|stop)';                          msg = 'systemd unit stop/disable/mask — confirm it is not a critical unit (linux-systemd skill); note how to re-enable.' }
        @{ rx = '\b(ufw|iptables|nft|firewall-cmd)\b';                      msg = 'Firewall change — never modify firewall rules without an explicit instruction.' }
        @{ rx = 'setenforce|/etc/selinux|aa-disable|aa-complain';           msg = 'SELinux/AppArmor enforcement change — never modify without an explicit instruction.' }
        @{ rx = '\bapt(-get)?\s+(remove|purge)|dnf\s+remove|yum\s+remove|pacman\s+-R'; msg = 'Package removal — confirm; system-wide change needs explicit "yes" (linux-packages skill).' }
        @{ rx = 'csrutil\s+disable|spctl\s+--master-disable|fdesetup';      msg = 'macOS SIP/Gatekeeper/FileVault change — never disable without an explicit instruction.' }
        @{ rx = 'defaults\s+delete';                                        msg = 'defaults delete — snapshot the current value to backups/macos/defaults/<ts>/ first (macos-defaults skill).' }
        @{ rx = 'launchctl\s+(bootout|unload|disable).*(/Library|/System)'; msg = 'System-wide launchd change — /Library and /System daemons need explicit confirmation (macos-launchd skill).' }
        @{ rx = '\bdd\b.*of=/dev/|mkfs|fdisk|parted';                       msg = 'Disk/partition operation — high blast radius; confirm the device path.' }
        @{ rx = '\bsudo\b';                                                 msg = 'sudo — repo rule is DO NOT auto-elevate; print the command for Marty to run rather than piping to sudo silently.' }
    )
}

$hits = @()
foreach ($r in $rules) {
    if ($cmd -match "(?i)$($r.rx)") { $hits += "  - $($r.msg)" }
}
if ($hits.Count -eq 0) { exit 0 }

$msg = @"
SAFETY GUARD (claude-local): this command matches a destructive-system-change rule.
$($hits -join "`n")
Repo policy: prefer reversible changes, back up before destructive edits, note the inverse, and get an explicit go-ahead for machine-wide changes. This is a reminder only — the normal permission prompt still applies.
"@

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = 'PreToolUse'
        additionalContext = $msg
    }
}
$payload | ConvertTo-Json -Depth 6 -Compress
exit 0
