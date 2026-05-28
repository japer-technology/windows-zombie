# Common.ps1
# ----------
# Shared helpers for Install.ps1 and Uninstall.ps1.
#
# Sourced via: . (Join-Path $PSScriptRoot 'Common.ps1')
#
# Conventions:
#   * Every function is idempotent. Re-running install must converge.
#   * Functions that mutate state return $true on a change, $false on
#     no-op, so the caller can render `[changed]` vs `[ok]`.
#   * No silent failures. Every catch path either re-throws or logs at
#     ERROR via Write-AzLog.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Configuration (overridable via environment, mirroring the bash legacy)
# ---------------------------------------------------------------------

if (-not $script:AzConfig) {
    function _Coalesce { param([object[]]$Values) foreach ($v in $Values) { if ($null -ne $v -and "$v" -ne '') { return $v } } return $null }
    $script:AzConfig = [ordered]@{
        AgentUser     = (_Coalesce @($env:ZOMBIE_USER, 'zombie'))
        InstallRoot   = (_Coalesce @($env:AI_ZOMBIE_ROOT, (Join-Path $env:ProgramData 'AiZombie')))
        ChatPort      = [int](_Coalesce @($env:ZOMBIE_CHAT_PORT, 7878))
        ServiceName   = 'Windows11Zombie-Chat'
        HealthTask    = 'Windows11Zombie-Health'
        FirewallGroup = 'Windows11 Zombie'
        NonInteractive= [bool]($env:ZOMBIE_NONINTERACTIVE -eq '1')
    }
    # Re-derive dependent paths from the install root so callers that
    # mutate AzConfig.InstallRoot get a consistent view.
    Update-AzPaths
}

function Update-AzPaths {
    $root = $script:AzConfig.InstallRoot
    $script:AzConfig.BinDir       = Join-Path $root 'bin'
    $script:AzConfig.AgentDir     = Join-Path $root 'agent'
    $script:AzConfig.EtcDir       = Join-Path $root 'etc'
    $script:AzConfig.SecretsDir   = Join-Path $root 'secrets'
    $script:AzConfig.SecretsFile  = Join-Path (Join-Path $root 'secrets') 'env'
    $script:AzConfig.LogDir       = Join-Path $root 'logs'
    $script:AzConfig.StateDir     = Join-Path $root 'state'
    $script:AzConfig.SkillsDir    = Join-Path $root 'skills'
    $script:AzConfig.PolicyFile   = Join-Path (Join-Path $root 'etc') 'policy.yaml'
    $script:AzConfig.PolicyDir    = Join-Path (Join-Path $root 'etc') 'skills.d'
    $script:AzConfig.PiSettings   = Join-Path (Join-Path $root 'pi') 'settings.json'
    $script:AzConfig.AuditLog     = Join-Path (Join-Path $root 'logs') 'audit.log'
    $script:AzConfig.InstallLog   = Join-Path (Join-Path $root 'logs') 'install.log'
}

# ---------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------

function Write-AzLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','DRY')][string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'DRY'   { 'Magenta' }
        default { 'Cyan' }
    }
    $tag = switch ($Level) {
        'OK'    { '[+]' }
        'WARN'  { '[!]' }
        'ERROR' { '[x]' }
        'DRY'   { '[dry]' }
        default { '[i]' }
    }
    Write-Host "$tag $Message" -ForegroundColor $color
    try {
        if ($script:AzConfig.InstallLog -and (Test-Path (Split-Path $script:AzConfig.InstallLog -Parent))) {
            $ts = (Get-Date -Format 's')
            "$ts $Level $Message" | Add-Content -Path $script:AzConfig.InstallLog -Encoding UTF8
        }
    } catch {
        # Logging failures must never abort the installer.
    }
}

# ---------------------------------------------------------------------
# Admin / environment checks
# ---------------------------------------------------------------------

function Assert-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated PowerShell session (Run as Administrator)."
    }
}

function Assert-Windows11 {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) {
        throw "Cannot detect operating system."
    }
    if ($os.Caption -notmatch 'Windows') {
        throw "Unsupported OS: $($os.Caption). Windows 11 is required."
    }
    $build = [int]($os.BuildNumber)
    if ($build -lt 22000) {
        Write-AzLog -Level WARN "Detected Windows build $build; Windows 11 (build >= 22000) is the supported target."
    }
}

function Test-ValidAgentUsername {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -in @('Administrator','SYSTEM','LocalSystem','Guest','root','nobody')) { return $false }
    # Windows local usernames: 1-20 chars; we further restrict to a
    # parity-compatible alphabet so the same name works on Linux too.
    return ($Name -match '^[a-zA-Z][a-zA-Z0-9._-]{0,19}$')
}

# ---------------------------------------------------------------------
# Filesystem + ACLs
# ---------------------------------------------------------------------

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) { return $false }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    return $true
}

function Set-AiZombieAcl {
    <#
    .SYNOPSIS
        Apply the standard ACL to an install-root path.
    .DESCRIPTION
        Grants:
          * Administrators — FullControl (inherited)
          * SYSTEM         — FullControl (inherited)
          * <AgentUser>    — Read+Execute (or ReadWrite for state/log/secrets)
        Removes built-in Users to keep the tree non-world-readable.
        This is the NTFS equivalent of the legacy ``chown root:zombie``
        + ``chmod 0750/0640`` pair.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AgentUser,
        [ValidateSet('Read','ReadWrite','ReadOnlySecrets')][string]$AgentAccess = 'Read'
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $acl = Get-Acl -LiteralPath $Path

    # Start from a clean slate: disable inheritance and remove existing
    # explicit rules so an upgrade picks up tightened ACLs.
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        $null = $acl.RemoveAccessRule($rule)
    }

    $inh   = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    $prop  = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow

    $admins = New-Object System.Security.Principal.SecurityIdentifier(
        [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $system = New-Object System.Security.Principal.SecurityIdentifier(
        [System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)

    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $admins, 'FullControl', $inh, $prop, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $system, 'FullControl', $inh, $prop, $allow)))

    try {
        $agent = New-Object System.Security.Principal.NTAccount($AgentUser)
        $rights = switch ($AgentAccess) {
            'ReadWrite'        { 'Modify' }
            'ReadOnlySecrets'  { 'Read' }
            default            { 'ReadAndExecute' }
        }
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $agent, $rights, $inh, $prop, $allow)))
    } catch {
        Write-AzLog -Level WARN "Could not grant ACL to '$AgentUser' on '$Path': $($_.Exception.Message)"
    }

    Set-Acl -LiteralPath $Path -AclObject $acl
}

# ---------------------------------------------------------------------
# Account management
# ---------------------------------------------------------------------

function Ensure-AgentAccount {
    param(
        [Parameter(Mandatory)][string]$AgentUser,
        [securestring]$Password
    )
    $existing = Get-LocalUser -Name $AgentUser -ErrorAction SilentlyContinue
    if ($existing) {
        Write-AzLog "User '$AgentUser' already exists."
    } else {
        if (-not $Password) {
            # Generate a strong random password. The operator never
            # needs it: the service is started by sc/SCM, and the
            # interactive workflow is via `net user $AgentUser /reset`.
            $Password = New-RandomPassword
        }
        Write-AzLog "Creating local user '$AgentUser' (password is randomly generated and never displayed)."
        New-LocalUser -Name $AgentUser -Password $Password `
            -FullName "Windows 11 Zombie AI SysAdmin" `
            -Description "AI Systems Administrator account managed by windows11-zombie." `
            -PasswordNeverExpires:$true -UserMayNotChangePassword:$true | Out-Null
    }
    if (-not (Get-LocalGroupMember -Group 'Administrators' -Member $AgentUser -ErrorAction SilentlyContinue)) {
        Add-LocalGroupMember -Group 'Administrators' -Member $AgentUser
        Write-AzLog -Level OK "Added '$AgentUser' to the local Administrators group."
    }
}

function New-RandomPassword {
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    try {
        $plain = [System.Web.Security.Membership]::GeneratePassword(32, 6)
    } catch {
        # Fallback when System.Web is unavailable (PowerShell Core 7+).
        $bytes = New-Object byte[] 24
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $plain = [Convert]::ToBase64String($bytes) + '!Aa1'
    }
    ConvertTo-SecureString -String $plain -AsPlainText -Force
}

# ---------------------------------------------------------------------
# Service registration
# ---------------------------------------------------------------------

function Register-AiZombieService {
    <#
    .SYNOPSIS
        Create or update the Windows11Zombie-Chat service.
    .DESCRIPTION
        Uses sc.exe so the service can run a Python venv under a
        deterministic working directory without dragging NSSM in as a
        new runtime dependency. Auto-start; restart on failure with a
        5-second backoff for the first three failures, then 60 s.
    #>
    [CmdletBinding()]
    param(
        [string]$ServiceName = $script:AzConfig.ServiceName,
        [Parameter(Mandatory)][string]$PythonExe,
        [Parameter(Mandatory)][string]$ServerScript,
        [Parameter(Mandatory)][int]$Port,
        [string]$AgentUser = $script:AzConfig.AgentUser
    )

    $binArgs = @(
        '"' + $PythonExe + '"'
        '"' + $ServerScript + '"'
        '--host'; '127.0.0.1'
        '--port'; $Port
    )
    $binPath = ($binArgs -join ' ')

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-AzLog "Service '$ServiceName' exists; reconfiguring binPath."
        sc.exe config $ServiceName binPath= "$binPath" start= auto | Out-Null
    } else {
        Write-AzLog "Registering service '$ServiceName'."
        # ObjectName= LocalSystem keeps install simple; an operator may
        # later move the service to the dedicated agent account via
        # sc.exe config + the Log-on-as-a-service privilege grant.
        sc.exe create $ServiceName binPath= "$binPath" start= auto `
            DisplayName= "Windows 11 Zombie chat (AI SysAdmin)" `
            obj= "LocalSystem" | Out-Null
    }
    sc.exe description $ServiceName "Loopback-only AI Systems Administrator chat service for windows11-zombie." | Out-Null
    sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/60000 | Out-Null
}

function Register-HealthScheduledTask {
    param(
        [string]$TaskName = $script:AzConfig.HealthTask,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger2 = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(5)) `
        -RepetitionInterval (New-TimeSpan -Minutes 15) `
        -RepetitionDuration ([TimeSpan]::FromDays(3650))
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -RunOnlyIfNetworkAvailable
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($trigger, $trigger2) `
        -Settings $settings -Principal $principal `
        -Description "windows11-zombie periodic health check." | Out-Null
}

# ---------------------------------------------------------------------
# Defender Firewall
# ---------------------------------------------------------------------

function Ensure-FirewallRules {
    param([int]$ChatPort = $script:AzConfig.ChatPort,
          [string]$Group = $script:AzConfig.FirewallGroup)

    # Loopback-only: explicitly block inbound to the chat port from
    # any non-loopback interface. (Loopback traffic is exempt from
    # filtering on Windows by default.)
    $existing = Get-NetFirewallRule -DisplayName "windows11-zombie chat: deny remote inbound" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "windows11-zombie chat: deny remote inbound" `
            -Group $Group -Direction Inbound -Action Block -Protocol TCP `
            -LocalPort $ChatPort -RemoteAddress Any `
            -Description "Loopback-only invariant: the chat service must not be reachable from any non-loopback interface." `
            -Profile Any | Out-Null
        Write-AzLog -Level OK "Created firewall block for inbound TCP/$ChatPort."
    } else {
        Set-NetFirewallRule -DisplayName "windows11-zombie chat: deny remote inbound" -LocalPort $ChatPort | Out-Null
    }
}

# ---------------------------------------------------------------------
# Package install (winget + choco fallback)
# ---------------------------------------------------------------------

function Install-WinGetPackage {
    param([Parameter(Mandatory)][string]$Id,
          [string]$Source = 'winget')
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-AzLog "winget install $Id"
        $null = winget install --id $Id --source $Source --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-AzLog -Level WARN "winget install $Id exited $LASTEXITCODE; falling back to choco if available."
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $chocoId = $Id.Split('.')[ -1 ].ToLowerInvariant()
        Write-AzLog "choco install $chocoId"
        choco install $chocoId -y --no-progress | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    Write-AzLog -Level WARN "Neither winget nor choco is available; cannot install $Id."
    return $false
}

# ---------------------------------------------------------------------
# Secrets file
# ---------------------------------------------------------------------

function Ensure-SecretsFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$AgentUser = $script:AzConfig.AgentUser
    )
    if (Test-Path -LiteralPath $Path) { return }
    $parent = Split-Path $Path -Parent
    Ensure-Directory $parent | Out-Null
    $template = @"
# Windows 11 Zombie secrets. ACL'd to SYSTEM + Administrators + $AgentUser.
# Pick ONE provider and paste its key. All providers are routed through
# @earendil-works/pi-ai; see docs/CONFIGURATION.md.
#
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
# GEMINI_API_KEY=...
# XAI_API_KEY=...
# OPENROUTER_API_KEY=...
# MISTRAL_API_KEY=...
# GROQ_API_KEY=...
#
# Optional:
# ZOMBIE_PROVIDER=openai
# ZOMBIE_MODEL=gpt-4o-mini
# ZOMBIE_CHAT_PORT=7878
"@
    Set-Content -LiteralPath $Path -Value $template -Encoding UTF8
    Set-AiZombieAcl -Path $Path -AgentUser $AgentUser -AgentAccess ReadOnlySecrets
}
