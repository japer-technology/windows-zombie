<#
.SYNOPSIS
    Install or upgrade Windows Zombie on this machine.

.DESCRIPTION
    Idempotent installer that:
      * creates a local Administrator account (`zombie` by default,
        overridable via $env:ZOMBIE_USER) for the AI Systems Administrator
      * provisions the install tree at $env:ProgramData\AiZombie\
      * sets NTFS ACLs equivalent to the legacy 0750/0640 model
      * installs Python 3.12, Node.js 20 (LTS), Git, and Tailscale via WinGet
      * sets up the agent Python venv and Playwright browser
      * registers the WindowsZombie-Chat service (auto-start, loopback)
      * registers WindowsZombie-Health as a Scheduled Task
      * applies a Defender Firewall block for non-loopback access

    Re-running the installer is safe: every step checks current state
    before mutating.

.PARAMETER Subcommand
    One of: install, verify, doctor, repair, uninstall, backup, restore.

.PARAMETER SkipDependencies
    Skip the WinGet bootstrap of Python/Node/Tailscale (use when those
    are already managed by the operator).

.PARAMETER SkipTailscale
    Do not install or configure Tailscale.

.EXAMPLE
    PS> Set-ExecutionPolicy -Scope Process Bypass
    PS> .\scripts\Install.ps1 install

.NOTES
    Run from an elevated PowerShell session.
    Honours ZOMBIE_NONINTERACTIVE=1 for CI.
#>
[CmdletBinding()]
param(
    [ValidateSet('install','verify','doctor','repair','uninstall','backup','restore')]
    [string]$Subcommand = 'install',

    [switch]$SkipDependencies,
    [switch]$SkipTailscale,
    [string]$Path,
    [switch]$Force
)

. (Join-Path $PSScriptRoot 'Common.ps1')

# ---------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------

function Invoke-Install {
    Assert-Administrator
    Assert-SupportedWindows

    # Migrate any pre-rename (windows11-zombie) service/task/firewall
    # artifacts so an in-place upgrade does not leave orphans behind.
    Remove-LegacyServiceArtifact

    $cfg = $script:AzConfig
    if (-not (Test-ValidAgentUsername $cfg.AgentUser)) {
        throw "Invalid ZOMBIE_USER '$($cfg.AgentUser)'. Use a 1-20 char ASCII identifier."
    }

    Write-AzLog "Install root : $($cfg.InstallRoot)"
    Write-AzLog "Agent user   : $($cfg.AgentUser)"
    Write-AzLog "Chat port    : $($cfg.ChatPort)"

    # 1. Filesystem layout
    foreach ($p in @($cfg.InstallRoot, $cfg.BinDir, $cfg.AgentDir, $cfg.EtcDir,
                     $cfg.SecretsDir, $cfg.LogDir, $cfg.StateDir, $cfg.SkillsDir,
                     $cfg.PolicyDir, (Split-Path $cfg.PiSettings -Parent))) {
        Ensure-Directory $p | Out-Null
    }
    Set-AiZombieAcl -Path $cfg.InstallRoot -AgentUser $cfg.AgentUser -AgentAccess Read
    Set-AiZombieAcl -Path $cfg.LogDir       -AgentUser $cfg.AgentUser -AgentAccess ReadWrite
    Set-AiZombieAcl -Path $cfg.StateDir     -AgentUser $cfg.AgentUser -AgentAccess ReadWrite
    Set-AiZombieAcl -Path $cfg.SecretsDir   -AgentUser $cfg.AgentUser -AgentAccess ReadOnlySecrets

    # 2. Agent account
    Ensure-AgentAccount -AgentUser $cfg.AgentUser

    # 3. Copy the payload tree into the install root
    Copy-Payload -SourceRoot (Join-Path $PSScriptRoot '..') -DestRoot $cfg.InstallRoot

    # 4. Dependencies
    if (-not $SkipDependencies) {
        Install-CoreDependencies -IncludeTailscale:(-not $SkipTailscale)
    } else {
        Write-AzLog -Level WARN "Skipping dependency install (operator-managed)."
    }

    # 5. Python venv + Playwright
    $venvDir = Join-Path $cfg.InstallRoot 'agent-env'
    & (Join-Path $cfg.BinDir 'Setup-AgentVenv.ps1') -VenvDir $venvDir

    $pythonExe = Join-Path $venvDir 'Scripts\python.exe'
    if (-not (Test-Path $pythonExe)) {
        throw "Agent venv missing after Setup-AgentVenv.ps1: $pythonExe"
    }

    # 6. Secrets file
    Ensure-SecretsFile -Path $cfg.SecretsFile -AgentUser $cfg.AgentUser

    # 7. Service + scheduled task
    Register-AiZombieService -PythonExe $pythonExe `
        -ServerScript (Join-Path $cfg.AgentDir 'server.py') `
        -Port $cfg.ChatPort
    Register-HealthScheduledTask -ScriptPath (Join-Path $cfg.BinDir 'Health-Check.ps1')
    Register-BackupScheduledTask -InstallerPath (Join-Path $PSScriptRoot 'Install.ps1')

    # 8. Firewall
    Ensure-FirewallRules

    Start-Service -Name $cfg.ServiceName -ErrorAction SilentlyContinue

    Write-AzLog -Level OK "Install complete."
    Write-AzLog "Next steps:"
    Write-AzLog "  1. Add a provider key:  notepad '$($cfg.SecretsFile)'"
    Write-AzLog "  2. Restart the service: Restart-Service $($cfg.ServiceName)"
    Write-AzLog "  3. Open http://127.0.0.1:$($cfg.ChatPort)/ in a local browser."
}

function Invoke-Verify {
    $cfg = $script:AzConfig
    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check([string]$name, [bool]$ok, [string]$detail = '') {
        $checks.Add([pscustomobject]@{ Check = $name; OK = $ok; Detail = $detail })
    }

    Add-Check "install root exists" (Test-Path $cfg.InstallRoot) $cfg.InstallRoot
    Add-Check "agent script present" (Test-Path (Join-Path $cfg.AgentDir 'server.py')) ''
    Add-Check "agent venv present"   (Test-Path (Join-Path $cfg.InstallRoot 'agent-env\Scripts\python.exe')) ''
    Add-Check "policy.yaml present"  (Test-Path $cfg.PolicyFile) $cfg.PolicyFile
    Add-Check "secrets file present" (Test-Path $cfg.SecretsFile) $cfg.SecretsFile
    Add-Check "agent account present" ([bool](Get-LocalUser -Name $cfg.AgentUser -ErrorAction SilentlyContinue)) ''
    $svc = Get-Service -Name $cfg.ServiceName -ErrorAction SilentlyContinue
    Add-Check "chat service registered" ([bool]$svc) ''
    Add-Check "chat service running"    ($svc -and $svc.Status -eq 'Running') ''
    $task = Get-ScheduledTask -TaskName $cfg.HealthTask -ErrorAction SilentlyContinue
    Add-Check "health task registered" ([bool]$task) ''
    $fw = Get-NetFirewallRule -DisplayName "windows-zombie chat: deny remote inbound" -ErrorAction SilentlyContinue
    Add-Check "firewall rule present" ([bool]$fw) ''

    $fail = 0
    foreach ($c in $checks) {
        if ($c.OK) {
            Write-AzLog -Level OK "$($c.Check) $($c.Detail)"
        } else {
            Write-AzLog -Level ERROR "$($c.Check) $($c.Detail)"
            $fail++
        }
    }
    if ($fail -gt 0) {
        Write-AzLog -Level ERROR "Verify failed ($fail check(s))."
        exit 1
    }
    Write-AzLog -Level OK "Verify passed."
}

function Invoke-Doctor {
    Write-AzLog "doctor: collecting non-mutating diagnostics."
    Invoke-Verify
    Write-Host ''
    Write-AzLog "Service:"
    Get-Service -Name $script:AzConfig.ServiceName -ErrorAction SilentlyContinue |
        Format-List Name,Status,StartType,DisplayName
    Write-AzLog "Last 20 Application Event Log entries:"
    Get-WinEvent -LogName Application -MaxEvents 20 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, LevelDisplayName, ProviderName, Id -AutoSize
    Write-AzLog "Firewall profiles:"
    Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction
    if (Test-Path 'C:\Program Files\Tailscale\tailscale.exe') {
        Write-AzLog "Tailscale status:"
        & 'C:\Program Files\Tailscale\tailscale.exe' status
    }
}

function Invoke-Repair {
    Write-AzLog "repair: re-applying ACLs, service config, firewall rules, scheduled tasks."
    Assert-Administrator
    $cfg = $script:AzConfig

    # Clean up any leftover pre-rename artifacts before re-applying state.
    Remove-LegacyServiceArtifact

    # Re-create install root if a sibling tree was deleted.
    foreach ($p in @($cfg.InstallRoot, $cfg.BinDir, $cfg.AgentDir, $cfg.EtcDir,
                     $cfg.SecretsDir, $cfg.LogDir, $cfg.StateDir, $cfg.SkillsDir,
                     $cfg.PolicyDir, (Split-Path $cfg.PiSettings -Parent))) {
        Ensure-Directory $p | Out-Null
    }

    Set-AiZombieAcl -Path $cfg.InstallRoot -AgentUser $cfg.AgentUser -AgentAccess Read
    Set-AiZombieAcl -Path $cfg.LogDir       -AgentUser $cfg.AgentUser -AgentAccess ReadWrite
    Set-AiZombieAcl -Path $cfg.StateDir     -AgentUser $cfg.AgentUser -AgentAccess ReadWrite
    Set-AiZombieAcl -Path $cfg.SecretsDir   -AgentUser $cfg.AgentUser -AgentAccess ReadOnlySecrets

    # Re-create the local agent account if missing.
    Ensure-AgentAccount -AgentUser $cfg.AgentUser

    # Re-create secrets template if it's gone (operator must repaste key).
    Ensure-SecretsFile -Path $cfg.SecretsFile -AgentUser $cfg.AgentUser

    # Re-create the venv if Python is broken.
    $venvPython = Join-Path $cfg.InstallRoot 'agent-env\Scripts\python.exe'
    $needVenv = $true
    if (Test-Path $venvPython) {
        try {
            & $venvPython -c "import sys" 2>$null | Out-Null
            $needVenv = ($LASTEXITCODE -ne 0)
        } catch { $needVenv = $true }
    }
    if ($needVenv) {
        Write-AzLog -Level WARN "Agent venv missing or broken; rebuilding."
        $setup = Join-Path $cfg.BinDir 'Setup-AgentVenv.ps1'
        if (Test-Path $setup) {
            & $setup -VenvDir (Join-Path $cfg.InstallRoot 'agent-env')
        }
    }

    # Re-register firewall, service, scheduled tasks (each idempotent).
    Ensure-FirewallRules
    if (Test-Path $venvPython) {
        Register-AiZombieService -PythonExe $venvPython `
            -ServerScript (Join-Path $cfg.AgentDir 'server.py') `
            -Port $cfg.ChatPort
    }
    if (Test-Path (Join-Path $cfg.BinDir 'Health-Check.ps1')) {
        Register-HealthScheduledTask -ScriptPath (Join-Path $cfg.BinDir 'Health-Check.ps1')
    }
    Register-BackupScheduledTask -InstallerPath (Join-Path $PSScriptRoot 'Install.ps1')

    if (Get-Service -Name $cfg.ServiceName -ErrorAction SilentlyContinue) {
        Restart-Service -Name $cfg.ServiceName
        Write-AzLog -Level OK "Restarted $($cfg.ServiceName)."
    }
}

function Invoke-Backup {
    Assert-Administrator
    $zip = New-AiZombieBackup
    Write-AzLog -Level OK "Backup: $zip"
}

function Invoke-Restore {
    Assert-Administrator
    if (-not $Path) { throw "restore requires -Path <backup.zip>" }
    Restore-AiZombieBackup -Path $Path -Force:$Force
}

function Invoke-Uninstall {
    & (Join-Path $PSScriptRoot 'Uninstall.ps1') -AssumeYes:($script:AzConfig.NonInteractive)
}

# ---------------------------------------------------------------------
# Helpers used only by install
# ---------------------------------------------------------------------

function Copy-Payload {
    param([string]$SourceRoot, [string]$DestRoot)
    $src = Join-Path $SourceRoot 'payload'
    if (-not (Test-Path $src)) {
        throw "Payload directory missing: $src"
    }
    Write-AzLog "Copying payload tree from '$src' to '$DestRoot'."
    # robocopy keeps it idempotent: same source/dest = no-op.
    $args = @("`"$src`"", "`"$DestRoot`"", '/E', '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    Start-Process -FilePath 'robocopy.exe' -ArgumentList $args -Wait -NoNewWindow -PassThru | Out-Null
    # robocopy exit codes 0-7 are success; 8+ is failure.
}

function Install-CoreDependencies {
    param([switch]$IncludeTailscale)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-AzLog -Level WARN "winget is not available. Install 'App Installer' from the Microsoft Store, then re-run."
        return
    }
    foreach ($id in @('Python.Python.3.12', 'OpenJS.NodeJS.LTS', 'Git.Git')) {
        Install-WinGetPackage -Id $id | Out-Null
    }
    if ($IncludeTailscale) {
        Install-WinGetPackage -Id 'tailscale.tailscale' | Out-Null
    }
}

# ---------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------

switch ($Subcommand) {
    'install'   { Invoke-Install }
    'verify'    { Invoke-Verify }
    'doctor'    { Invoke-Doctor }
    'repair'    { Invoke-Repair }
    'uninstall' { Invoke-Uninstall }
    'backup'    { Invoke-Backup }
    'restore'   { Invoke-Restore }
}
