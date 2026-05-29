<#
.SYNOPSIS
    Safely edit the windows11-zombie secrets file in $env:EDITOR / notepad.
    Re-applies ACLs after the editor exits, even on error.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\scripts\Common.ps1') -ErrorAction SilentlyContinue
if (-not $script:AzConfig) {
    # Fallback when run from the installed tree (no scripts/ next door)
    $installRoot = if ($env:AI_ZOMBIE_ROOT) { $env:AI_ZOMBIE_ROOT } else { Join-Path $env:ProgramData 'AiZombie' }
    $secretsFile = Join-Path $installRoot 'secrets\env'
    $agentUser = if ($env:ZOMBIE_USER) { $env:ZOMBIE_USER } else { 'zombie' }
} else {
    Assert-Administrator
    $secretsFile = $script:AzConfig.SecretsFile
    $agentUser   = $script:AzConfig.AgentUser
}

if (-not (Test-Path -LiteralPath $secretsFile)) {
    if ($script:AzConfig) {
        Ensure-SecretsFile -Path $secretsFile -AgentUser $agentUser
    } else {
        throw "Secrets file missing and Common.ps1 not loaded: $secretsFile"
    }
}

# Back up the existing secrets file before invoking the editor so a
# fat-finger save can be recovered without re-typing the API key.
# Backups inherit the same ACL as the live env file and live under
# secrets\backups\ alongside it. Only the most recent 10 backups are
# retained; older ones are pruned on every edit.
$backupDir = Join-Path (Split-Path -Parent $secretsFile) 'backups'
if (-not (Test-Path -LiteralPath $backupDir)) {
    $null = New-Item -ItemType Directory -Path $backupDir -Force
}
if ($script:AzConfig) {
    Set-AiZombieAcl -Path $backupDir -AgentUser $agentUser -AgentAccess ReadOnlySecrets
}
if ((Test-Path -LiteralPath $secretsFile) -and `
    ((Get-Item -LiteralPath $secretsFile).Length -gt 0)) {
    $backupTs   = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $backupFile = Join-Path $backupDir "env.$backupTs"
    Copy-Item -LiteralPath $secretsFile -Destination $backupFile -Force
    if ($script:AzConfig) {
        Set-AiZombieAcl -Path $backupFile -AgentUser $agentUser -AgentAccess ReadOnlySecrets
    }
    Write-Host "[i] Backup written: $backupFile"
    # Keep the last 10 backups (newest first), prune the rest.
    Get-ChildItem -LiteralPath $backupDir -Filter 'env.*' -File |
        Sort-Object -Property LastWriteTimeUtc -Descending |
        Select-Object -Skip 10 |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

$editor = $env:VISUAL
if (-not $editor) { $editor = $env:EDITOR }
if (-not $editor) { $editor = 'notepad.exe' }

Write-Host "[i] Opening $secretsFile in $editor"
try {
    & $editor $secretsFile | Out-Null
} finally {
    if ($script:AzConfig) {
        Set-AiZombieAcl -Path $secretsFile -AgentUser $agentUser -AgentAccess ReadOnlySecrets
    }
    # If the file was emptied or truncated by mistake, point the operator
    # at the most recent backup so they can restore it.
    $latest = Get-ChildItem -LiteralPath $backupDir -Filter 'env.*' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ((-not (Test-Path -LiteralPath $secretsFile) -or `
        ((Get-Item -LiteralPath $secretsFile).Length -eq 0)) -and $latest) {
        Write-Host ""
        Write-Warning "$secretsFile is now empty."
        Write-Warning "To roll back to the previous version, run:"
        Write-Warning "  Copy-Item -LiteralPath '$($latest.FullName)' -Destination '$secretsFile' -Force"
        Write-Warning "  pwsh -File .\payload\bin\Secrets-Edit.ps1   # re-applies ACLs"
    }
    Write-Host ""
    Write-Host "Saved. Restart the chat service to pick up the new value:"
    Write-Host "  Restart-Service Windows11Zombie-Chat"
}
