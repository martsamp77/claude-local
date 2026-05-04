<#
.NAME        inspect-task
.SYNOPSIS    Show full details of one or more scheduled tasks (action, principal, triggers).
.CATEGORY    startup
.USAGE       .\tools\startup\inspect-task.ps1 -Name SidebarStartup,StartCN
.WHEN        "what does <task> actually run", "is this task safe to remove",
             before unregister/disable of an unknown scheduled task.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Name
)

$ErrorActionPreference = 'Continue'

foreach ($n in $Name) {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    if (-not $t) {
        Write-Output "=== $n === (not found)"
        Write-Output ""
        continue
    }
    Write-Output ("=== {0} ===" -f $n)
    Write-Output ("Path:    " + $t.TaskPath + $t.TaskName)
    Write-Output ("State:   " + $t.State)
    if ($t.Author)      { Write-Output ("Author:  " + $t.Author) }
    if ($t.Description) { Write-Output ("Desc:    " + $t.Description) }
    Write-Output ("RunAs:   " + $t.Principal.UserId + " (RunLevel=" + $t.Principal.RunLevel + ")")

    $i = 0
    foreach ($a in $t.Actions) {
        $i++
        $line = "Action" + $i + ": " + $a.Execute
        if ($a.Arguments)        { $line += " " + $a.Arguments }
        Write-Output $line
        if ($a.WorkingDirectory) { Write-Output ("  WorkDir: " + $a.WorkingDirectory) }
    }

    foreach ($trg in $t.Triggers) {
        $cls = $trg.CimClass.CimClassName -replace 'MSFT_Task','' -replace 'Trigger',''
        $line = "Trigger: " + $cls + "  Enabled=" + $trg.Enabled
        if ($trg.Delay)      { $line += "  Delay="    + $trg.Delay }
        if ($trg.UserId)     { $line += "  UserId="   + $trg.UserId }
        if ($trg.StartBoundary) { $line += "  Start=" + $trg.StartBoundary }
        Write-Output $line
    }
    Write-Output ""
}
