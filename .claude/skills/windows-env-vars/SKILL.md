---
name: windows-env-vars
description: Read and persist Windows environment variables (User vs Machine scope) and edit PATH safely. Use whenever a task touches env vars beyond the current shell.
---

# windows-env-vars

Use this skill when a task involves persistent environment variables or PATH editing. **Do not** use `$env:NAME = "value"` for persistence — that only sets the variable in the current shell.

## The three scopes

| Scope | Where it lives | Persistence | Admin? |
|---|---|---|---|
| `Process` | Current PowerShell session | Until shell exits | No |
| `User` | `HKCU\Environment` | Persists for Marty across sessions | No |
| `Machine` | `HKLM\System\CurrentControlSet\Control\Session Manager\Environment` | Persists for all users | **Yes** |

Always default to `User` scope unless Marty asks for machine-wide.

## Read

```powershell
# Effective value in current process
$env:PATH

# Persisted values (don't use $env:* for these)
[Environment]::GetEnvironmentVariable("PATH", "User")
[Environment]::GetEnvironmentVariable("PATH", "Machine")

# Combined effective PATH for new shells
$user = [Environment]::GetEnvironmentVariable("PATH", "User")
$machine = [Environment]::GetEnvironmentVariable("PATH", "Machine")
"$machine;$user"
```

## Set a non-PATH variable

```powershell
[Environment]::SetEnvironmentVariable("MY_VAR", "value", "User")
# Confirm
[Environment]::GetEnvironmentVariable("MY_VAR", "User")
```

To delete: pass `$null` or empty string as the value.

## PATH: split, dedupe, rewrite

Never just `$path += ";newdir"` — duplicates accumulate, broken entries get preserved. Always split, normalize, dedupe, rewrite.

```powershell
function Add-ToUserPath {
    param([Parameter(Mandatory)][string]$Dir)
    $Dir = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\')
    $current = [Environment]::GetEnvironmentVariable("PATH", "User")
    $entries = if ($current) { $current -split ';' | Where-Object { $_ } } else { @() }
    $normalized = $entries | ForEach-Object { $_.TrimEnd('\') }
    if ($normalized -contains $Dir) {
        Write-Host "Already on PATH: $Dir"
        return
    }
    $new = ($normalized + $Dir) -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $new, "User")
    Write-Host "Added to User PATH: $Dir"
}

function Remove-FromUserPath {
    param([Parameter(Mandatory)][string]$Dir)
    $Dir = $Dir.TrimEnd('\')
    $current = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $current) { return }
    $kept = $current -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $Dir) }
    [Environment]::SetEnvironmentVariable("PATH", ($kept -join ';'), "User")
}
```

Always show Marty the diff (which entries were added/removed) before committing.

## Make new shells see the change

`SetEnvironmentVariable` writes the registry but running shells don't repoll. Two options:

1. **Restart the shell** — simplest. Most reliable.
2. **Broadcast `WM_SETTINGCHANGE`** — explorer.exe and new processes pick up the change without a restart:

```powershell
$signature = @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
$type = Add-Type -MemberDefinition $signature -Name 'Win32SendMessage' -Namespace Win32Functions -PassThru
$HWND_BROADCAST = [IntPtr]0xffff
$WM_SETTINGCHANGE = 0x1A
$result = [UIntPtr]::Zero
$type::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
```

The current PowerShell session won't update either way — `$env:PATH` reflects the snapshot taken at shell start. Update it manually if needed:

```powershell
$env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")
```

## Don't

- Don't use `setx` from scripts — it truncates PATH at 1024 chars and corrupts it. Use `[Environment]::SetEnvironmentVariable` instead.
- Don't write to `$env:PATH` and expect it to persist.
- Don't edit `HKCU\Environment` directly via `Set-ItemProperty` unless you also broadcast `WM_SETTINGCHANGE` — `[Environment]::SetEnvironmentVariable` handles this for you.
