<#
.SYNOPSIS
    Provision the agent Python virtualenv and Playwright browser.

.DESCRIPTION
    Idempotent. Re-running upgrades pip + project dependencies and
    re-attempts the Playwright Chromium download with exponential
    backoff if it failed earlier.

.PARAMETER VenvDir
    Destination venv directory. Defaults to
    $env:ProgramData\AiZombie\agent-env.
#>
[CmdletBinding()]
param(
    [string]$VenvDir = (Join-Path $env:ProgramData 'AiZombie\agent-env')
)

$ErrorActionPreference = 'Stop'

function Resolve-Python {
    foreach ($cmd in @('py', 'python3', 'python')) {
        $p = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($p) { return $p.Source }
    }
    throw "Python 3 was not found on PATH. Install via 'winget install Python.Python.3.12'."
}

$python = Resolve-Python
if (-not (Test-Path $VenvDir)) {
    Write-Host "[i] Creating venv at $VenvDir"
    if ($python.EndsWith('py.exe')) {
        & $python -3 -m venv $VenvDir
    } else {
        & $python -m venv $VenvDir
    }
}

$venvPython = Join-Path $VenvDir 'Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    throw "Venv Python not found after creation: $venvPython"
}

function Invoke-PipRetry {
    param([string[]]$Args)
    $delay = 3
    for ($n = 1; $n -le 4; $n++) {
        & $venvPython -m pip @Args
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "[!] pip retry $n in ${delay}s..."
        Start-Sleep -Seconds $delay
        $delay *= 2
    }
    throw "pip failed after 4 attempts: $Args"
}

Invoke-PipRetry @('install', '--upgrade', 'pip', 'wheel', 'setuptools')
Invoke-PipRetry @('install', '--upgrade',
    'requests', 'pydantic', 'rich', 'typer', 'python-dotenv',
    'playwright', 'pyautogui', 'pillow', 'mss', 'opencv-python')

# Playwright browser download — flaky over slow networks; retry.
$cacheDir = Join-Path $env:LOCALAPPDATA 'windows11-zombie'
$null = New-Item -ItemType Directory -Force -Path $cacheDir
$failSentinel = Join-Path $cacheDir 'playwright-failed'

$delay = 5
for ($n = 1; $n -le 4; $n++) {
    & $venvPython -m playwright install chromium
    if ($LASTEXITCODE -eq 0) {
        if (Test-Path $failSentinel) { Remove-Item -LiteralPath $failSentinel -Force }
        Write-Host "[+] Playwright Chromium ready."
        exit 0
    }
    Write-Host "[!] Playwright retry $n in ${delay}s..."
    Start-Sleep -Seconds $delay
    $delay *= 2
}

Set-Content -LiteralPath $failSentinel -Value (Get-Date -Format 's')
Write-Host "[x] Playwright install failed; rerun later." -ForegroundColor Red
exit 1
