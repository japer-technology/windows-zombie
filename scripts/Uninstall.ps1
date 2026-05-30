<#
.SYNOPSIS
    Reverse the Windows Zombie installer.

.DESCRIPTION
    Stops and removes the chat service, scheduled health and backup
    tasks, firewall rules, install tree under
    $env:ProgramData\AiZombie, and (with
    confirmation) the agent local account. Does NOT remove Python,
    Node.js, Git, or Tailscale — those are general-purpose tools that
    other things may depend on.

.PARAMETER Archive
    Archive the state and secrets directories under
    $env:ProgramData\AiZombie-backups\ before removal.

.PARAMETER AssumeYes
    Skip all confirmation prompts. Honours ZOMBIE_NONINTERACTIVE=1.

.PARAMETER KeepAgent
    Leave the local agent account in place.
#>
[CmdletBinding()]
param(
    [switch]$Archive,
    [switch]$AssumeYes,
    [switch]$KeepAgent
)

. (Join-Path $PSScriptRoot 'Common.ps1')

Assert-Administrator

if ($env:ZOMBIE_NONINTERACTIVE -eq '1') { $AssumeYes = $true }
$cfg = $script:AzConfig

function Confirm-Action {
    param([string]$Prompt)
    if ($AssumeYes) { return $true }
    $ans = Read-Host "$Prompt  Type YES to proceed"
    return ($ans -eq 'YES')
}

Write-AzLog "== windows-zombie uninstall =="

# 1. Service + scheduled task
if (Get-Service -Name $cfg.ServiceName -ErrorAction SilentlyContinue) {
    Write-AzLog "Stopping service '$($cfg.ServiceName)'."
    Stop-Service -Name $cfg.ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $cfg.ServiceName | Out-Null
}
foreach ($taskName in @($cfg.HealthTask, 'WindowsZombie-Backup')) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-AzLog -Level OK "Removed scheduled task '$taskName'."
    }
}

# 2. Firewall
Get-NetFirewallRule -Group $cfg.FirewallGroup -ErrorAction SilentlyContinue |
    ForEach-Object {
        Remove-NetFirewallRule -DisplayName $_.DisplayName -ErrorAction SilentlyContinue
        Write-AzLog -Level OK "Removed firewall rule '$($_.DisplayName)'."
    }

# 3. Archive
if ($Archive -and (Test-Path $cfg.InstallRoot)) {
    $backupRoot = Join-Path $env:ProgramData 'AiZombie-backups'
    Ensure-Directory $backupRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zip = Join-Path $backupRoot "windows-zombie-$stamp.zip"
    Write-AzLog "Archiving install tree to '$zip'."
    Compress-Archive -Path (Join-Path $cfg.InstallRoot '*') -DestinationPath $zip -Force
}

# 4. Install tree
if (Test-Path $cfg.InstallRoot) {
    if (Confirm-Action "Remove '$($cfg.InstallRoot)' (includes secrets, state, history)?") {
        Remove-Item -LiteralPath $cfg.InstallRoot -Recurse -Force
        Write-AzLog -Level OK "Removed '$($cfg.InstallRoot)'."
    } else {
        Write-AzLog -Level WARN "Keeping '$($cfg.InstallRoot)'. Privileged code is still on disk."
    }
}

# 5. Account
if ($KeepAgent) {
    Write-AzLog "Keeping local account '$($cfg.AgentUser)' (-KeepAgent)."
} else {
    $existing = Get-LocalUser -Name $cfg.AgentUser -ErrorAction SilentlyContinue
    if ($existing) {
        if (Confirm-Action "Remove local account '$($cfg.AgentUser)' and its profile?") {
            Remove-LocalUser -Name $cfg.AgentUser
            $profilePath = Join-Path $env:SystemDrive "Users\$($cfg.AgentUser)"
            if (Test-Path $profilePath) {
                Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-AzLog -Level OK "Removed account '$($cfg.AgentUser)'."
        } else {
            Write-AzLog -Level WARN "Keeping account '$($cfg.AgentUser)'."
        }
    }
}

Write-AzLog -Level OK "Uninstall complete."
Write-AzLog "Left intact on purpose: Python, Node.js, Git, Tailscale (uninstall with `winget uninstall` if no longer needed)."
