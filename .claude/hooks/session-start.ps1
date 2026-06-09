<#
  session-start.ps1  —  SessionStart hook

  Injects a compact, OS-filtered orientation as additionalContext so each session
  starts knowing: which platform, the tools available for THIS OS (name + synopsis),
  and whether a perf-capture monitor is already running. Automates the "list tools
  at session start" step from CLAUDE.md.

  Cross-platform pwsh (Windows/Linux/macOS). Always exits 0; never breaks startup.
#>

$ErrorActionPreference = 'SilentlyContinue'

try {
    $repoRoot = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

    if ($IsWindows -ne $false) { $os = 'windows'; $toolDirs = @('windows'); $glob = '*.ps1' }
    elseif ($IsMacOS)          { $os = 'macos';   $toolDirs = @('macos','unix'); $glob = '*.sh' }
    else                       { $os = 'linux';   $toolDirs = @('linux','unix'); $glob = '*.sh' }

    # Collect tool headers (.NAME / .SYNOPSIS) for the current OS only.
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $toolDirs) {
        $base = Join-Path $repoRoot "tools/$d"
        if (-not (Test-Path $base)) { continue }
        foreach ($f in (Get-ChildItem $base -Recurse -Filter $glob -File)) {
            $head = Get-Content $f.FullName -TotalCount 12
            $name = ($head | Where-Object { $_ -match '\.NAME\s' }) -replace '.*\.NAME\s+', '' -replace '^#\s*', ''
            $syn  = ($head | Where-Object { $_ -match '\.SYNOPSIS\s' }) -replace '.*\.SYNOPSIS\s+', '' -replace '^#\s*', ''
            if ($name) {
                $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
                $lines.Add(("  {0,-14} {1}  [{2}]" -f $name.Trim(), $syn.Trim(), $rel))
            }
        }
    }

    # perf-capture monitor status
    $pidFile = Join-Path $repoRoot "logs/$os/diagnostics/.perf-capture.pid"
    $monitor = 'none running'
    if (Test-Path $pidFile) {
        $parts = (Get-Content $pidFile -TotalCount 1) -split '\|'
        $mpid  = $parts[0]
        if ($mpid -and (Get-Process -Id ([int]$mpid) -ErrorAction SilentlyContinue)) {
            $monitor = "RUNNING pid=$mpid since $($parts[2]) -> log $($parts[1]).  Use /capture status|analyze|stop."
        } else {
            $monitor = 'stale pidfile (process gone) — a previous capture did not clean up'
        }
    }

    $ctx = @"
claude-local orientation (auto, SessionStart hook):
Platform=$os. Tools available for this OS:
$($lines -join "`n")
perf-capture monitor: $monitor
Reminder: honor [scope] tags, back up before destructive edits, don't auto-elevate. See CLAUDE.md.
"@

    $payload = @{
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $ctx
        }
    }
    $payload | ConvertTo-Json -Depth 6 -Compress
} catch { }
exit 0
