<#
.SYNOPSIS
    Bundle redacted logs and state for a bug report.

.DESCRIPTION
    Mirrors the legacy `collect-diagnostics` bash helper. Token-shaped
    values are scrubbed in every captured stream before write. The
    resulting zip is written under $env:TEMP.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$installRoot = if ($env:AI_ZOMBIE_ROOT) { $env:AI_ZOMBIE_ROOT } else { Join-Path $env:ProgramData 'AiZombie' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bundleDir = Join-Path $env:TEMP "windows11-zombie-diagnostics-$stamp"
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
$zipPath = Join-Path $env:TEMP "windows11-zombie-diagnostics-$stamp.zip"

function Hide-Secrets {
    param([string]$Text)
    if (-not $Text) { return '' }
    $patterns = @(
        @{ p = 'sk-[A-Za-z0-9_-]{12,}';     r = 'sk-***REDACTED***' },
        @{ p = 'sk-ant-[A-Za-z0-9_-]{12,}'; r = 'sk-ant-***REDACTED***' },
        @{ p = 'tskey-[A-Za-z0-9_-]{12,}';  r = 'tskey-***REDACTED***' },
        @{ p = '(?i)(API[_-]?KEY|TOKEN|PASSWORD|SECRET)\s*[:=]\s*\S+'; r = '$1=***REDACTED***' }
    )
    $out = $Text
    foreach ($pat in $patterns) {
        $out = [regex]::Replace($out, $pat.p, $pat.r)
    }
    return $out
}

function Capture {
    param([string]$Name, [scriptblock]$Block)
    $outPath = Join-Path $bundleDir $Name
    try {
        $raw = (& $Block 2>&1 | Out-String)
    } catch {
        $raw = "ERROR: $($_.Exception.Message)"
    }
    "## $Name (saved $((Get-Date).ToUniversalTime().ToString('s'))Z)`n" + (Hide-Secrets $raw) |
        Set-Content -LiteralPath $outPath -Encoding UTF8
}

Write-Host "[i] Collecting diagnostics into $bundleDir ..."

Capture 'computer-info.txt'      { Get-ComputerInfo | Format-List }
Capture 'os.txt'                  { Get-CimInstance Win32_OperatingSystem | Format-List }
Capture 'disk.txt'                { Get-PSDrive -PSProvider FileSystem | Format-Table }
Capture 'services.txt'            { Get-Service -Name 'Windows11Zombie-Chat','TermService','sshd' -ErrorAction SilentlyContinue | Format-Table }
Capture 'sched-tasks.txt'         { Get-ScheduledTask -TaskName 'Windows11Zombie-*' | Format-List TaskName,State,LastRunTime,NextRunTime }
Capture 'firewall.txt'            { Get-NetFirewallProfile | Format-Table; Get-NetFirewallRule -Group 'Windows11 Zombie' | Format-Table -AutoSize }
Capture 'event-log-application.txt' { Get-WinEvent -LogName Application -MaxEvents 200 -ErrorAction SilentlyContinue | Format-Table TimeCreated,LevelDisplayName,ProviderName,Id }
Capture 'tailscale.txt'           { if (Test-Path 'C:\Program Files\Tailscale\tailscale.exe') { & 'C:\Program Files\Tailscale\tailscale.exe' status } else { 'tailscale not installed' } }
Capture 'verify.txt'              { & (Join-Path $PSScriptRoot '..\..\scripts\Install.ps1') verify }
Capture 'health.txt'              { & (Join-Path $PSScriptRoot 'Health-Check.ps1') }

foreach ($f in @(
    Join-Path $installRoot 'logs\install.log',
    Join-Path $installRoot 'logs\audit.log',
    Join-Path $installRoot 'etc\policy.yaml'
)) {
    if (Test-Path -LiteralPath $f) {
        $dest = Join-Path $bundleDir (Split-Path -Leaf $f)
        Hide-Secrets (Get-Content -LiteralPath $f -Raw) | Set-Content -LiteralPath $dest -Encoding UTF8
    }
}

Compress-Archive -Path (Join-Path $bundleDir '*') -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $bundleDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Diagnostic bundle: $zipPath"
Write-Host "Secrets have been redacted, but please review before sharing."
