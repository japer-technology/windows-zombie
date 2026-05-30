<#
.SYNOPSIS
    One-shot health summary for Windows Zombie.

.DESCRIPTION
    Runs every 15 minutes from the ``WindowsZombie-Health``
    Scheduled Task. Checks service state, network/Tailscale,
    Defender Firewall, secrets, disk, audit log integrity, clock
    skew, and the loopback bind invariant. Writes a structured
    summary to ``state\health.json`` so dashboards can scrape it.

    Exit codes:
        0 — all checks passed (warnings allowed)
        1 — at least one check failed
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$installRoot  = if ($env:AI_ZOMBIE_ROOT) { $env:AI_ZOMBIE_ROOT } else { Join-Path $env:ProgramData 'AiZombie' }
$secretsFile  = Join-Path $installRoot 'secrets\env'
$auditLog     = Join-Path $installRoot 'logs\audit.log'
$stateDir     = Join-Path $installRoot 'state'
$healthJson   = Join-Path $stateDir 'health.json'
$serviceName  = 'WindowsZombie-Chat'
$chatPort     = if ($env:ZOMBIE_CHAT_PORT) { [int]$env:ZOMBIE_CHAT_PORT } else { 7878 }

$pass = 0; $warn = 0; $fail = 0
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [ValidateSet('ok','warn','fail')] [string]$Status, [string]$Detail = '')
    $checks.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail })
    switch ($Status) {
        'ok'   { Write-Host "  [ok]   $Name $Detail" -ForegroundColor Green; $script:pass++ }
        'warn' { Write-Host "  [warn] $Name $Detail" -ForegroundColor Yellow; $script:warn++ }
        'fail' { Write-Host "  [--]   $Name $Detail" -ForegroundColor Red;   $script:fail++ }
    }
}

Write-Host "== windows-zombie health ==" -ForegroundColor White

# --- Chat service --------------------------------------------------
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Add-Check 'chat service active' 'ok'
} elseif ($svc) {
    Add-Check 'chat service registered' 'fail' "status=$($svc.Status); Start-Service $serviceName"
} else {
    Add-Check 'chat service registered' 'fail' 'run scripts/Install.ps1 install'
}

# --- Loopback bind invariant --------------------------------------
# Look up listeners on the chat port. If anything other than 127.0.0.1
# or ::1 is listening, the loopback invariant has regressed.
try {
    $listeners = Get-NetTCPConnection -State Listen -LocalPort $chatPort -ErrorAction SilentlyContinue
    if ($listeners) {
        $bad = $listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') }
        if ($bad) {
            Add-Check 'loopback bind invariant' 'fail' ("port {0} bound to {1}" -f $chatPort, ($bad.LocalAddress -join ','))
        } else {
            Add-Check 'loopback bind invariant' 'ok' ("port {0} on loopback only" -f $chatPort)
        }
    } else {
        Add-Check 'loopback bind invariant' 'warn' "no listener on port $chatPort (service stopped?)"
    }
} catch {
    Add-Check 'loopback bind invariant' 'warn' "could not query TCP listeners: $($_.Exception.Message)"
}

# --- Tailscale ----------------------------------------------------
$ts = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $ts) {
    $out = & $ts status 2>&1
    if ($LASTEXITCODE -eq 0 -and $out -notmatch 'Logged out') {
        Add-Check 'tailscale logged in' 'ok'
    } else {
        Add-Check 'tailscale logged in' 'warn' "tailscale up?"
    }
} else {
    Add-Check 'tailscale installed' 'ok' '(not installed; skipped)'
}

# --- RDP ----------------------------------------------------------
$rdp = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
if ($rdp -and $rdp.Status -eq 'Running') {
    Add-Check 'Remote Desktop service' 'ok'
} else {
    Add-Check 'Remote Desktop service' 'warn' 'TermService not running'
}

# --- Firewall -----------------------------------------------------
$profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
if ($profiles) {
    $enabledCount = ($profiles | Where-Object Enabled -eq $true).Count
    if ($enabledCount -ge 1) {
        Add-Check 'Defender Firewall enabled' 'ok' "$enabledCount profile(s)"
    } else {
        Add-Check 'Defender Firewall enabled' 'fail' 'disabled on all profiles'
    }
} else {
    Add-Check 'Defender Firewall queryable' 'warn'
}

$fwRule = Get-NetFirewallRule -Group 'Windows Zombie' -ErrorAction SilentlyContinue
if ($fwRule) {
    Add-Check 'firewall rule group present' 'ok'
} else {
    Add-Check 'firewall rule group present' 'fail' 'run scripts/Install.ps1 repair'
}

# --- Provider key -------------------------------------------------
if (Test-Path $secretsFile) {
    $content = Get-Content -LiteralPath $secretsFile -Raw
    if ($content -match '^\s*(?:export\s+)?(OPENAI|ANTHROPIC|GEMINI|XAI|OPENROUTER|MISTRAL|GROQ)_API_KEY\s*=\s*\S' ) {
        Add-Check 'provider key in secrets/env' 'ok'
    } else {
        Add-Check 'provider key in secrets/env' 'warn' "notepad '$secretsFile'"
    }
} else {
    Add-Check 'secrets/env present' 'warn' "missing at $secretsFile"
}

# --- Disk ---------------------------------------------------------
$drive = Get-PSDrive C -ErrorAction SilentlyContinue
if ($drive) {
    $freeMb = [math]::Round($drive.Free / 1MB)
    if ($freeMb -gt 1024) { Add-Check 'free disk space' 'ok'   "$freeMb MB" }
    elseif ($freeMb -gt 500) { Add-Check 'free disk space' 'warn' "$freeMb MB (< 1 GB)" }
    else { Add-Check 'free disk space' 'fail' "$freeMb MB (< 500 MB)" }
}

# --- Audit log ---------------------------------------------------
if (Test-Path $auditLog) {
    $count = (Get-Content -LiteralPath $auditLog -ErrorAction SilentlyContinue | Measure-Object).Count
    Add-Check 'audit log present' 'ok' "$count entries"
    $verify = Join-Path $PSScriptRoot 'Verify-Audit.ps1'
    if (Test-Path $verify) {
        $null = & $verify -Path $auditLog 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-Check 'audit chain integrity' 'ok'
        } else {
            Add-Check 'audit chain integrity' 'fail' 'tamper detected; see logs/audit.log'
        }
    }
} else {
    Add-Check 'audit log present' 'warn' 'will appear on first chat use'
}

# --- Clock skew --------------------------------------------------
try {
    $local = (Get-Date).ToUniversalTime()
    # w32tm reports drift in seconds; fall back to "unknown" if it
    # isn't configured (common on home installs).
    $w32 = & w32tm /stripchart /computer:time.windows.com /samples:1 /dataonly 2>&1 | Select-String -Pattern '[+-]?\d+\.\d+s'
    if ($w32) {
        $skew = [math]::Abs([double]($w32.Matches[0].Value -replace 's$', ''))
        if ($skew -le 60) { Add-Check 'clock skew' 'ok' ("{0:N2}s" -f $skew) }
        elseif ($skew -le 300) { Add-Check 'clock skew' 'warn' ("{0:N2}s" -f $skew) }
        else { Add-Check 'clock skew' 'fail' ("{0:N2}s (> 5 min)" -f $skew) }
    } else {
        Add-Check 'clock skew' 'ok' '(w32tm unavailable; skipped)'
    }
} catch {
    Add-Check 'clock skew' 'warn' "w32tm error: $($_.Exception.Message)"
}

# --- Write health.json -------------------------------------------
$summary = [ordered]@{
    ts_utc  = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    ok      = ($fail -eq 0)
    pass    = $pass
    warn    = $warn
    fail    = $fail
    checks  = $checks
}
try {
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $healthJson -Encoding UTF8
} catch {
    Write-Host "[!] could not write $healthJson : $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("Result: {0} ok, {1} warn, {2} fail" -f $pass, $warn, $fail) -ForegroundColor White
if ($fail -gt 0) { exit 1 }
exit 0
