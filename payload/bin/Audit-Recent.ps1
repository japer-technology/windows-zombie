<#
.SYNOPSIS
    Pretty-print recent windows11-zombie audit entries (JSON Lines).

.PARAMETER N        Number of entries to show (default 25).
.PARAMETER All      Show the entire log.
.PARAMETER Type     Filter to entries whose 'type' equals one of these (repeatable).
.PARAMETER Follow   Tail the log and stream new entries (Get-Content -Wait).
#>
[CmdletBinding()]
param(
    [int]$N = 25,
    [switch]$All,
    [string[]]$Type,
    [switch]$Follow
)

$installRoot = if ($env:AI_ZOMBIE_ROOT) { $env:AI_ZOMBIE_ROOT } else { Join-Path $env:ProgramData 'AiZombie' }
$auditLog = if ($env:ZOMBIE_AUDIT_LOG) { $env:ZOMBIE_AUDIT_LOG } else { Join-Path $installRoot 'logs\audit.log' }

if (-not (Test-Path -LiteralPath $auditLog)) {
    Write-Error "Audit log not found at $auditLog. (Run windows11-zombie first to create it.)"
    exit 1
}

function Format-Entry {
    param([string]$Line)
    try { $obj = $Line | ConvertFrom-Json -ErrorAction Stop } catch { Write-Output $Line; return }
    if ($Type -and ($Type -notcontains $obj.type)) { return }
    $color = switch ($obj.type) {
        'prompt'         { 'Cyan' }
        'proposal'       { 'Yellow' }
        'approval'       { 'Magenta' }
        'execution'      { 'Green' }
        'tool_call'      { 'Blue' }
        'provider_error' { 'Red' }
        default          { 'White' }
    }
    $tail = ''
    foreach ($f in 'pid','tool','classification','decision','command','exit_code','duration_ms','prompt','error') {
        if ($null -ne $obj.$f -and "$($obj.$f)" -ne '') {
            $val = "$($obj.$f)" -replace "`n",' ⏎ '
            if ($val.Length -gt 160) { $val = $val.Substring(0,160) + '…' }
            $tail += " $f=$val"
        }
    }
    Write-Host ("[{0}] {1}{2}" -f $obj.ts, $obj.type, $tail) -ForegroundColor $color
    foreach ($f in 'stdout_preview','stderr_preview') {
        if ($obj.$f) {
            $val = "$($obj.$f)" -replace "`n",' ⏎ '
            if ($val.Length -gt 160) { $val = $val.Substring(0,160) + '…' }
            Write-Host ("    {0}> {1}" -f ($f -replace '_preview',''), $val) -ForegroundColor DarkGray
        }
    }
}

if ($Follow) {
    Get-Content -LiteralPath $auditLog -Tail $N -Wait | ForEach-Object { Format-Entry $_ }
    return
}

if ($All) {
    Get-Content -LiteralPath $auditLog | ForEach-Object { Format-Entry $_ }
} else {
    Get-Content -LiteralPath $auditLog -Tail $N | ForEach-Object { Format-Entry $_ }
}
