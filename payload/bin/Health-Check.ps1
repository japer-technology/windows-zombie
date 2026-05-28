<#
.SYNOPSIS
    One-shot health summary for Windows 11 Zombie.

.DESCRIPTION
    Mirrors the legacy `health-check` bash helper:
      * Windows11Zombie-Chat service status
      * Tailscale login state (if installed)
      * RDP service status (TermService)
      * Defender Firewall enforcement
      * Provider key presence in the secrets file
      * Disk space
      * Audit log presence + entry count
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$installRoot  = if ($env:AI_ZOMBIE_ROOT) { $env:AI_ZOMBIE_ROOT } else { Join-Path $env:ProgramData 'AiZombie' }
$secretsFile  = Join-Path $installRoot 'secrets\env'
$auditLog     = Join-Path $installRoot 'logs\audit.log'
$serviceName  = 'Windows11Zombie-Chat'
$pass = 0; $warn = 0; $fail = 0

function Ok   ($m) { Write-Host "  [ok]   $m" -ForegroundColor Green; $script:pass++ }
function Warn ($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow; $script:warn++ }
function Fail ($m) { Write-Host "  [--]   $m" -ForegroundColor Red;   $script:fail++ }

Write-Host "== windows11-zombie health ==" -ForegroundColor White

# Chat service
$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Ok "chat service active"
} elseif ($svc) {
    Fail "chat service registered but $($svc.Status). (Start-Service $serviceName)"
} else {
    Fail "chat service not registered (run scripts/Install.ps1 install)"
}

# Tailscale
$ts = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $ts) {
    $out = & $ts status 2>&1
    if ($LASTEXITCODE -eq 0 -and $out -notmatch 'Logged out') {
        Ok "tailscale logged in"
    } else {
        Fail "tailscale logged out (`& '$ts' up`)"
    }
} else {
    Ok "tailscale not installed (skipped)"
}

# RDP
$rdp = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
if ($rdp -and $rdp.Status -eq 'Running') {
    Ok "Remote Desktop service active"
} else {
    Warn "Remote Desktop service not running"
}

# Firewall
$profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
if ($profiles) {
    $enabledCount = ($profiles | Where-Object Enabled -eq $true).Count
    if ($enabledCount -ge 1) { Ok "Defender Firewall enabled ($enabledCount profile(s))" }
    else { Fail "Defender Firewall disabled on all profiles" }
} else {
    Warn "could not query Defender Firewall"
}

# Provider key
if (Test-Path $secretsFile) {
    $content = Get-Content -LiteralPath $secretsFile -Raw
    if ($content -match '^\s*(?:export\s+)?(OPENAI|ANTHROPIC|GEMINI|XAI|OPENROUTER|MISTRAL|GROQ)_API_KEY\s*=\s*\S' ) {
        Ok "provider key present in secrets/env"
    } else {
        Warn "no provider key in secrets/env (notepad '$secretsFile')"
    }
} else {
    Warn "secrets/env missing at $secretsFile"
}

# Disk
$drive = Get-PSDrive C -ErrorAction SilentlyContinue
if ($drive) {
    $freeMb = [math]::Round($drive.Free / 1MB)
    if ($freeMb -gt 2000) { Ok "free disk space $freeMb MB" }
    elseif ($freeMb -gt 500) { Warn "low free disk space $freeMb MB" }
    else { Fail "very low free disk space $freeMb MB" }
}

# Audit log
if (Test-Path $auditLog) {
    $count = (Get-Content -LiteralPath $auditLog -ErrorAction SilentlyContinue | Measure-Object).Count
    Ok "audit log present ($count entries)"
} else {
    Warn "audit log missing (will appear on first chat use)"
}

Write-Host ""
Write-Host ("Result: {0} ok, {1} warn, {2} fail" -f $pass, $warn, $fail) -ForegroundColor White
if ($fail -gt 0) { exit 1 }
