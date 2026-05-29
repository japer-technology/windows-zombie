<#
.SYNOPSIS
    Smoke tests for windows-zombie.

.DESCRIPTION
    Designed to run unprivileged on Windows, Linux, or macOS so CI can
    catch regressions before requiring an elevated Windows runner.

    Modes:
        syntax        parse every PowerShell file (no execution)
        python        py_compile every payload/agent/*.py
        policy        parse payload/etc/policy.yaml
        subcommands   check Install.ps1 / Uninstall.ps1 export expected param sets
        standards     repo standards (no stray ubuntu-zombie text in active code, VERSION shape, license year)
        all           every check above
#>
[CmdletBinding()]
param(
    [ValidateSet('syntax', 'python', 'policy', 'subcommands', 'standards', 'all')]
    [string]$Mode = 'all'
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Repo 'payload'))) {
    # fall back if invoked from repo root
    $Repo = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
}
$failures = New-Object System.Collections.ArrayList

function Add-Failure([string]$msg) {
    Write-Host "  FAIL: $msg" -ForegroundColor Red
    [void]$failures.Add($msg)
}

function Test-Syntax {
    Write-Host "==> PowerShell syntax parse"
    $ps1 = Get-ChildItem -Recurse -File -Include *.ps1, *.psm1 -Path $Repo |
        Where-Object { $_.FullName -notmatch '[\\/]dist[\\/]' -and $_.FullName -notmatch '[\\/]examples[\\/]dsc[\\/]' }
    foreach ($f in $ps1) {
        $tokens = $null; $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) {
            foreach ($e in $errs) {
                Add-Failure "$($f.Name):$($e.Extent.StartLineNumber): $($e.Message)"
            }
        }
    }
    Write-Host "  parsed $($ps1.Count) PowerShell files"
}

function Test-Python {
    Write-Host "==> Python compile"
    $py = (Get-Command python3 -ErrorAction SilentlyContinue) ?? (Get-Command python -ErrorAction SilentlyContinue)
    if (-not $py) { Add-Failure "python not found"; return }
    & $py.Source -m compileall -q (Join-Path $Repo 'payload/agent')
    if ($LASTEXITCODE -ne 0) { Add-Failure "python compileall failed" }
}

function Test-Policy {
    Write-Host "==> policy.yaml parse"
    $py = (Get-Command python3 -ErrorAction SilentlyContinue) ?? (Get-Command python -ErrorAction SilentlyContinue)
    if (-not $py) { Add-Failure "python not found for policy parse"; return }
    $code = "import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding='utf-8').read()); print('ok')"
    & $py.Source -c $code (Join-Path $Repo 'payload/etc/policy.yaml')
    if ($LASTEXITCODE -ne 0) { Add-Failure "policy.yaml failed to parse" }
}

function Test-Subcommands {
    Write-Host "==> Install.ps1 / Uninstall.ps1 subcommand surface"
    $install = Join-Path $Repo 'scripts/Install.ps1'
    $uninstall = Join-Path $Repo 'scripts/Uninstall.ps1'
    foreach ($f in @($install, $uninstall)) {
        if (-not (Test-Path $f)) { Add-Failure "missing $f"; continue }
        $text = Get-Content $f -Raw
        $expected = @('install', 'verify', 'doctor', 'repair', 'uninstall')
        foreach ($verb in $expected) {
            if ($text -notmatch [regex]::Escape($verb)) {
                # Uninstall.ps1 only needs 'uninstall'
                if ($f -eq $uninstall -and $verb -ne 'uninstall') { continue }
                Add-Failure "subcommand '$verb' not referenced in $(Split-Path $f -Leaf)"
            }
        }
    }
}

function Test-Standards {
    Write-Host "==> Repo standards (no stray legacy names in active code)"
    # paths.py keeps Linux-fallback constants on purpose, and this file
    # documents the standards check; both are allowed to mention the
    # legacy name. README.md and CHANGELOG.md intentionally credit the
    # upstream `ubuntu-zombie` inspiration and keep the platform history,
    # and WINDOWS10-POSSIBILITIES.md references it as the parity baseline.
    $allowList = @(
        (Join-Path $Repo 'payload/agent/paths.py'),
        (Join-Path $Repo 'tests/Smoke.ps1'),
        (Join-Path $Repo 'README.md'),
        (Join-Path $Repo 'CHANGELOG.md'),
        (Join-Path $Repo 'WINDOWS10-POSSIBILITIES.md')
    )
    $bad = Get-ChildItem -Recurse -File -Path $Repo |
        Where-Object {
            $_.FullName -notmatch '[\\/](\.git|dist|node_modules|__pycache__|agent-env)[\\/]' -and
            $allowList -notcontains $_.FullName
        } |
        Where-Object {
            try {
                $content = Get-Content $_.FullName -Raw -ErrorAction Stop
                $content -match 'ubuntu-zombie'
            } catch { $false }
        }
    if ($bad) {
        foreach ($f in $bad) { Add-Failure "stale 'ubuntu-zombie' reference in $($f.FullName.Substring($Repo.Length+1))" }
    }
    $vfile = Join-Path $Repo 'VERSION'
    if (Test-Path $vfile) {
        $v = (Get-Content $vfile -Raw).Trim()
        if ($v -notmatch '^\d+\.\d+\.\d+$') { Add-Failure "VERSION '$v' not semver" }
    } else {
        Add-Failure "VERSION file missing"
    }
}

switch ($Mode) {
    'syntax'      { Test-Syntax }
    'python'      { Test-Python }
    'policy'      { Test-Policy }
    'subcommands' { Test-Subcommands }
    'standards'   { Test-Standards }
    'all' {
        Test-Syntax
        Test-Python
        Test-Policy
        Test-Subcommands
        Test-Standards
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Smoke FAILED ($($failures.Count) issue(s))" -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "Smoke OK" -ForegroundColor Green
exit 0
