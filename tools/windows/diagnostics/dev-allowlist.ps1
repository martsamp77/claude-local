<#
.NAME        dev-allowlist
.SYNOPSIS    Shared dev-tool allowlist + matching helpers for the perf-* tools (dot-sourced, not run directly).
.PLATFORM    windows
.CATEGORY    diagnostics
.USAGE       . "$PSScriptRoot\dev-allowlist.ps1"
.WHEN        Internal — loaded by perf-* tools when -ExcludeDev/-Exclude/-OnlyDev is requested. Do not run on its own.
#>

# The protected set: processes that are SUPPOSED to be busy on a software-development box and
# should not be flagged as "what's slowing the machine down". Categories exist only so the
# suppression footer can read "node x7, Docker x3, ...". Matching flattens them.
#
# Patterns match Get-Process .Name (no .exe), case-insensitive, via -like. Literal dots in
# com.docker.backend / PowerToys.Awake need no escaping; '*' is the only wildcard.
$script:DevAllowlistByCategory = [ordered]@{
    'Claude'    = @('claude', 'claude-code')                  # Claude Code CLI (native binary, not node)
    'Codex'     = @('codex', 'codex-cli')                     # Codex CLI / UI (matches 'Codex' too — -like is case-insensitive)
    'node'      = @('node')                                   # MCP servers, language servers, other node-based dev tools
    'Docker'    = @('Docker Desktop', 'com.docker.backend', 'com.docker.build', 'dockerd', 'docker',
                    'vmmem', 'vmmemWSL', 'wslservice', 'wsl')  # Docker Desktop + the WSL2 VM that backs it
    'PowerToys' = @('PowerToys*')                             # all modules incl. PowerToys.Awake
    'Tailscale' = @('tailscaled', 'Tailscale-IPN', 'tailscale')
}
$script:DevAllowlist = @($script:DevAllowlistByCategory.Values | ForEach-Object { $_ })

function Test-DevProcess {
    # True when a process Name belongs to the dev allowlist (or a caller-supplied extra pattern).
    # Takes a string so it works for live Get-Process objects AND names parsed out of a capture log.
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$ExtraPatterns = @()
    )
    foreach ($pat in (@($script:DevAllowlist) + @($ExtraPatterns))) {
        if ($Name -like $pat) { return $true }   # -like is case-insensitive
    }
    return $false
}

function Get-DevCategory {
    # Returns the category a Name belongs to ('node'/'Docker'/'PowerToys'/'Tailscale'),
    # 'custom' if it only matched a caller-supplied -ExtraPatterns entry, or $null if not dev.
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$ExtraPatterns = @()
    )
    foreach ($cat in $script:DevAllowlistByCategory.Keys) {
        foreach ($pat in $script:DevAllowlistByCategory[$cat]) {
            if ($Name -like $pat) { return $cat }
        }
    }
    foreach ($pat in @($ExtraPatterns)) {
        if ($Name -like $pat) { return 'custom' }
    }
    return $null
}

function Get-DevCategoryBreakdown {
    # "node x7, Docker x3, custom x1" for the names that are dev tools; '' if none.
    param(
        [string[]]$Names = @(),
        [string[]]$ExtraPatterns = @()
    )
    $counts = [ordered]@{}
    foreach ($n in $Names) {
        $cat = Get-DevCategory -Name $n -ExtraPatterns $ExtraPatterns
        if (-not $cat) { continue }
        if (-not $counts.Contains($cat)) { $counts[$cat] = 0 }
        $counts[$cat]++
    }
    if (-not $counts.Keys.Count) { return '' }
    (($counts.Keys | ForEach-Object { '{0} x{1}' -f $_, $counts[$_] }) -join ', ')
}

function Get-DevSuppressionSummary {
    # Footer for the snapshot-style view: counts by category + total CPU-seconds + total RAM (GB).
    # The CALLER passes the set it actually suppressed (so the line is correct whether that came from
    # -ExcludeDev, -Exclude, or both) — nothing vanishes silently because this footer always prints it.
    # $Suppressed are Get-Process objects (need .Name; .CPU and .WorkingSet64 are summed when present).
    param(
        [Parameter(Mandatory)]$Suppressed,
        [string[]]$ExtraPatterns = @()
    )
    $s = @($Suppressed)
    if (-not $s.Count) { return '' }
    $breakdown = Get-DevCategoryBreakdown -Names $s.Name -ExtraPatterns $ExtraPatterns
    $cpuS  = [math]::Round((($s | Measure-Object CPU -Sum).Sum), 0)
    $ramGb = [math]::Round((($s | Measure-Object WorkingSet64 -Sum).Sum / 1GB), 1)
    "(suppressed from top tables: {0}  totaling {1}s CPU / {2} GB RAM — re-run without -ExcludeDev for PIDs)" -f $breakdown, $cpuS, $ramGb
}
