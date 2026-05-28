<#
.SYNOPSIS
    Build, lint, test, package, and verify targets for windows11-zombie.

.DESCRIPTION
    Cross-platform PowerShell (Windows PowerShell 5.1+ or PowerShell 7+)
    entry point. Mirrors the old GNU Makefile targets:

        pwsh -File build.ps1 <target>

    Available targets:
        help            print this list
        lint            PSScriptAnalyzer (if installed) + Python compile + policy.yaml parse
        test            run tests/Smoke.ps1 in 'all' mode
        smoke           same as test
        verify          run scripts/Install.ps1 verify (requires Administrator)
        package         emit dist/windows11-zombie-<VERSION>.zip
        clean           remove dist/ and Python caches

    `lint` and `test` are designed to run unprivileged on Windows, Linux,
    or macOS (so a developer working under WSL or macOS can still run the
    syntax/parse checks). `verify` and the real installer require Windows
    11 with administrator rights.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'lint', 'test', 'smoke', 'verify', 'package', 'clean')]
    [string]$Target = 'help'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

function Get-Version {
    $vfile = Join-Path $RepoRoot 'VERSION'
    if (-not (Test-Path $vfile)) { return '0.0.0' }
    return (Get-Content $vfile -Raw).Trim()
}

function Invoke-Help {
    Write-Host "Targets:"
    Write-Host "  help     - print this help"
    Write-Host "  lint     - PSScriptAnalyzer + Python compile + policy.yaml parse"
    Write-Host "  test     - run tests/Smoke.ps1 all (unprivileged)"
    Write-Host "  smoke    - alias for test"
    Write-Host "  verify   - scripts/Install.ps1 verify (requires admin on Windows)"
    Write-Host "  package  - dist/windows11-zombie-<VERSION>.zip"
    Write-Host "  clean    - remove dist/ and __pycache__"
}

function Invoke-Lint {
    Write-Host "==> PowerShell syntax parse"
    $ps1Files = Get-ChildItem -Recurse -File -Include *.ps1, *.psm1, *.psd1 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\dist\\' -and $_.FullName -notmatch '/dist/' -and $_.FullName -notmatch '[\\/]examples[\\/]dsc[\\/]' }
    foreach ($f in $ps1Files) {
        $tokens = $null; $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) {
            Write-Host "    PARSE ERROR in $($f.FullName)" -ForegroundColor Red
            $errs | ForEach-Object { Write-Host "      $($_.Message) at line $($_.Extent.StartLineNumber)" }
            throw "PowerShell parse errors found."
        }
    }
    Write-Host "    parsed $($ps1Files.Count) .ps1 files OK"

    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        Write-Host "==> PSScriptAnalyzer"
        Import-Module PSScriptAnalyzer -ErrorAction Stop
        $issues = Invoke-ScriptAnalyzer -Path $RepoRoot -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost, PSUseShouldProcessForStateChangingFunctions, PSAvoidUsingPositionalParameters
        if ($issues) {
            $issues | Format-Table -AutoSize | Out-String | Write-Host
            $errors = @($issues | Where-Object { $_.Severity -eq 'Error' })
            if ($errors.Count -gt 0) { throw "PSScriptAnalyzer found $($errors.Count) errors." }
        } else {
            Write-Host "    no PSScriptAnalyzer findings"
        }
    } else {
        Write-Host "==> PSScriptAnalyzer not installed; skipping (Install-Module PSScriptAnalyzer)" -ForegroundColor Yellow
    }

    Write-Host "==> Python compile (payload/agent)"
    $py = (Get-Command python -ErrorAction SilentlyContinue) ?? (Get-Command python3 -ErrorAction SilentlyContinue)
    if (-not $py) { Write-Host "    python not found; skipping" -ForegroundColor Yellow }
    else {
        & $py.Source -m compileall -q (Join-Path $RepoRoot 'payload/agent')
        if ($LASTEXITCODE -ne 0) { throw "python -m compileall failed." }
    }

    Write-Host "==> policy.yaml parse"
    if ($py) {
        $code = @'
import sys, yaml, pathlib
p = pathlib.Path(sys.argv[1])
yaml.safe_load(p.read_text(encoding="utf-8"))
print("ok")
'@
        $tmp = New-TemporaryFile
        Set-Content -Path $tmp -Value $code -Encoding utf8
        try {
            & $py.Source $tmp (Join-Path $RepoRoot 'payload/etc/policy.yaml')
            if ($LASTEXITCODE -ne 0) { throw "policy.yaml failed to parse" }
        } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

        Write-Host "==> policy.yaml schema validation"
        $schemaCode = @'
import sys, json, yaml, pathlib
data = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
schema = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
try:
    import jsonschema
except ImportError:
    print("jsonschema not installed; skipping schema validation")
    sys.exit(0)
jsonschema.validate(instance=data, schema=schema)
print("schema ok")
'@
        $tmp2 = New-TemporaryFile
        Set-Content -Path $tmp2 -Value $schemaCode -Encoding utf8
        try {
            & $py.Source $tmp2 (Join-Path $RepoRoot 'payload/etc/policy.yaml') (Join-Path $RepoRoot 'schemas/policy.schema.json')
            if ($LASTEXITCODE -ne 0) { throw "policy.yaml does not validate against schemas/policy.schema.json" }
        } finally { Remove-Item $tmp2 -ErrorAction SilentlyContinue }
    }
    Write-Host "==> lint OK" -ForegroundColor Green
}

function Invoke-Test {
    $smoke = Join-Path $RepoRoot 'tests/Smoke.ps1'
    if (-not (Test-Path $smoke)) { throw "tests/Smoke.ps1 missing" }
    & pwsh -NoProfile -File $smoke -Mode all
    if ($LASTEXITCODE -ne 0) { throw "tests/Smoke.ps1 failed (exit $LASTEXITCODE)" }

    # Python unit tests (best-effort: skip cleanly if pytest is absent).
    $pyTests = Join-Path $RepoRoot 'tests/python'
    if (Test-Path $pyTests) {
        $py = (Get-Command python -ErrorAction SilentlyContinue) ?? (Get-Command python3 -ErrorAction SilentlyContinue)
        if ($py) {
            $hasPytest = $false
            & $py.Source -c "import pytest" 2>$null
            if ($LASTEXITCODE -eq 0) { $hasPytest = $true }
            if ($hasPytest) {
                Write-Host "==> pytest tests/python"
                & $py.Source -m pytest $pyTests -q
                if ($LASTEXITCODE -ne 0) { throw "pytest failed (exit $LASTEXITCODE)" }
            } else {
                Write-Host "==> pytest not installed; skipping tests/python (pip install pytest)" -ForegroundColor Yellow
            }
        }
    }

    # Pester tests (best-effort).
    $pester = Join-Path $RepoRoot 'tests/Pester'
    if (Test-Path $pester) {
        if (Get-Module -ListAvailable -Name Pester) {
            Write-Host "==> Pester tests/Pester"
            Import-Module Pester -MinimumVersion 5.0 -ErrorAction SilentlyContinue
            $cfg = New-PesterConfiguration
            $cfg.Run.Path = $pester
            $cfg.Output.Verbosity = 'Normal'
            $cfg.Run.Throw = $true
            Invoke-Pester -Configuration $cfg
        } else {
            Write-Host "==> Pester not installed; skipping tests/Pester (Install-Module Pester)" -ForegroundColor Yellow
        }
    }
}

function Invoke-Verify {
    $installer = Join-Path $RepoRoot 'scripts/Install.ps1'
    & pwsh -NoProfile -File $installer verify
    if ($LASTEXITCODE -ne 0) { throw "Install.ps1 verify failed (exit $LASTEXITCODE)" }
}

function Invoke-Package {
    $version = Get-Version
    $dist = Join-Path $RepoRoot 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $zip = Join-Path $dist "windows11-zombie-$version.zip"
    if (Test-Path $zip) { Remove-Item $zip }
    $paths = @(
        'scripts', 'payload', 'tests', 'build.ps1', 'VERSION',
        'README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'CODE_OF_CONDUCT.md',
        'LICENSE', '.editorconfig', 'SECURITY.md', 'docs', 'schemas'
    ) | Where-Object { Test-Path (Join-Path $RepoRoot $_) }
    Compress-Archive -Path ($paths | ForEach-Object { Join-Path $RepoRoot $_ }) -DestinationPath $zip -Force

    # Emit SHA256SUMS alongside the zip so releases are verifiable.
    $sumsPath = Join-Path $dist "SHA256SUMS"
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower()
    "$sha  $(Split-Path -Leaf $zip)" | Set-Content -LiteralPath $sumsPath -Encoding ascii -NoNewline
    Add-Content -LiteralPath $sumsPath -Value ""
    Write-Host "Wrote $zip"
    Write-Host "Wrote $sumsPath"
}

function Invoke-Clean {
    $dist = Join-Path $RepoRoot 'dist'
    if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
    Get-ChildItem -Recurse -Force -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
    Write-Host "cleaned"
}

switch ($Target) {
    'help'    { Invoke-Help }
    'lint'    { Invoke-Lint }
    'test'    { Invoke-Test }
    'smoke'   { Invoke-Test }
    'verify'  { Invoke-Verify }
    'package' { Invoke-Package }
    'clean'   { Invoke-Clean }
}
