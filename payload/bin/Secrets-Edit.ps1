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
    Write-Host ""
    Write-Host "Saved. Restart the chat service to pick up the new value:"
    Write-Host "  Restart-Service Windows11Zombie-Chat"
}
