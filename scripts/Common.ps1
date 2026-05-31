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

if (-not (Test-Path Variable:script:AzConfig) -or -not $script:AzConfig) {
    function _Coalesce { param([object[]]$Values) foreach ($v in $Values) { if ($null -ne $v -and "$v" -ne '') { return $v } } return $null }
    $script:AzConfig = [ordered]@{
        AgentUser     = (_Coalesce @($env:ZOMBIE_USER, 'zombie'))
        InstallRoot   = (_Coalesce @($env:AI_ZOMBIE_ROOT, (Join-Path $env:ProgramData 'AiZombie')))
        ChatPort      = [int](_Coalesce @($env:ZOMBIE_CHAT_PORT, 7878))
        ServiceName   = 'WindowsZombie-Chat'
        HealthTask    = 'WindowsZombie-Health'
        FirewallGroup = 'Windows Zombie'
        NonInteractive= [bool]($env:ZOMBIE_NONINTERACTIVE -eq '1')
    }
    # Re-derive dependent paths from the install root so callers that
    # mutate AzConfig.InstallRoot get a consistent view.
    Update-AzPaths
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

# Minimum Windows build we treat as a first-class target. 17763 is
# Windows 10 1809, the first release with modern WinGet/App Installer
# support and stable New-NetFirewallRule behaviour. Windows 11 starts at
# build 22000; both are supported by this project.
$script:MinSupportedWindowsBuild = 17763
$script:Windows11MinBuild        = 22000

function Assert-SupportedWindows {
    <#
    .SYNOPSIS
        Verify the host is a supported Windows release (Windows 10 1809+
        or Windows 11) before mutating the system.

    .DESCRIPTION
        Windows Zombie targets both Windows 10 (build >= 17763, i.e.
        1809) and Windows 11 (build >= 22000). The privileged surfaces it
        uses -- services, Scheduled Tasks, Defender Firewall, ACLs, and
        WinGet -- all shipped in Windows 10 1809, so the floor is a soft,
        warn-only guard rather than a hard block. This keeps the lenient
        posture of the original installer while making both versions
        first-class targets.
    #>
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) {
        throw "Cannot detect operating system."
    }
    if ($os.Caption -notmatch 'Windows') {
        throw "Unsupported OS: $($os.Caption). Windows 10 (1809+) or Windows 11 is required."
    }
    $build = [int]($os.BuildNumber)
    $edition = if ($build -ge $script:Windows11MinBuild) { 'Windows 11' } else { 'Windows 10' }
    if ($build -lt $script:MinSupportedWindowsBuild) {
        Write-AzLog -Level WARN ("Detected Windows build $build; the tested floor is " +
            "$($script:MinSupportedWindowsBuild) (Windows 10 1809). Continuing, but this " +
            "build is older than the supported range.")
    } else {
        Write-AzLog "Detected $edition (build $build); within the supported range."
    }
}

# Backwards-compatible alias for callers/scripts that still reference the
# original Windows 11-only gate name.
Set-Alias -Name Assert-Windows11 -Value Assert-SupportedWindows -Scope Script

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
            -FullName "Windows Zombie AI SysAdmin" `
            -Description "AI Systems Administrator account managed by windows-zombie." `
            -PasswordNeverExpires:$true -UserMayNotChangePassword:$true | Out-Null
    }
    if (-not (Get-LocalGroupMember -Group 'Administrators' -Member $AgentUser -ErrorAction SilentlyContinue)) {
        Add-LocalGroupMember -Group 'Administrators' -Member $AgentUser
        Write-AzLog -Level OK "Added '$AgentUser' to the local Administrators group."
    }
}

function New-RandomPassword {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The plaintext is generated locally in this function from a CSPRNG, is never persisted or displayed, and must be wrapped as a SecureString for New-LocalUser.')]
    [CmdletBinding()]
    param()
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
        Create or update the WindowsZombie-Chat service.
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
            DisplayName= "Windows Zombie chat (AI SysAdmin)" `
            obj= "LocalSystem" | Out-Null
    }
    sc.exe description $ServiceName "Loopback-only AI Systems Administrator chat service for windows-zombie." | Out-Null
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
        -Description "windows-zombie periodic health check." | Out-Null
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
    $existing = Get-NetFirewallRule -DisplayName "windows-zombie chat: deny remote inbound" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName "windows-zombie chat: deny remote inbound" `
            -Group $Group -Direction Inbound -Action Block -Protocol TCP `
            -LocalPort $ChatPort -RemoteAddress Any `
            -Description "Loopback-only invariant: the chat service must not be reachable from any non-loopback interface." `
            -Profile Any | Out-Null
        Write-AzLog -Level OK "Created firewall block for inbound TCP/$ChatPort."
    } else {
        Set-NetFirewallRule -DisplayName "windows-zombie chat: deny remote inbound" -LocalPort $ChatPort | Out-Null
    }
}

# ---------------------------------------------------------------------
# Legacy migration (windows-zombie -> windows-zombie rename)
# ---------------------------------------------------------------------

function Remove-LegacyServiceArtifact {
    <#
    .SYNOPSIS
        Remove service/task/firewall artifacts created by pre-rename
        (``Windows11Zombie-*``) installs so an in-place upgrade does not
        orphan them alongside the new ``WindowsZombie-*`` resources.
    .DESCRIPTION
        User data under ``C:\ProgramData\AiZombie\`` is unaffected: only
        the externally named OS resources (Windows Service, Scheduled
        Tasks, and the Defender Firewall rule/group) are renamed, so this
        migration simply tears the legacy-named ones down. The installer
        then recreates them under the new names. Idempotent and safe to
        run on a clean machine (every lookup tolerates "not found").
    #>
    [CmdletBinding()]
    param()

    $legacyServices = @('Windows11Zombie-Chat')
    $legacyTasks    = @('Windows11Zombie-Health', 'Windows11Zombie-Backup')
    $legacyFwRule   = 'windows11-zombie chat: deny remote inbound'
    $legacyFwGroup  = 'Windows11 Zombie'

    foreach ($svc in $legacyServices) {
        if ($svc -eq $script:AzConfig.ServiceName) { continue }
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            Write-AzLog -Level WARN "Migrating legacy service '$svc' to '$($script:AzConfig.ServiceName)'."
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            sc.exe delete $svc | Out-Null
        }
    }

    foreach ($task in $legacyTasks) {
        if ($task -eq $script:AzConfig.HealthTask) { continue }
        if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
            Write-AzLog -Level WARN "Removing legacy scheduled task '$task'."
            Unregister-ScheduledTask -TaskName $task -Confirm:$false
        }
    }

    if ($legacyFwGroup -ne $script:AzConfig.FirewallGroup) {
        Get-NetFirewallRule -Group $legacyFwGroup -ErrorAction SilentlyContinue |
            ForEach-Object {
                Write-AzLog -Level WARN "Removing legacy firewall rule '$($_.DisplayName)'."
                Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue
            }
    }
    Get-NetFirewallRule -DisplayName $legacyFwRule -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue }
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
# Windows Zombie secrets. ACL'd to SYSTEM + Administrators + $AgentUser.
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

# ---------------------------------------------------------------------
# Backup / restore
# ---------------------------------------------------------------------

function New-AiZombieBackup {
    <#
    .SYNOPSIS
        Snapshot the windows-zombie state, secrets, config, and logs.
    .DESCRIPTION
        Produces a timestamped zip under ``<InstallRoot>\state\backups\``
        with a ``SHA256SUMS`` manifest so ``Restore-AiZombieBackup``
        can verify integrity.

        Captured by default:
          * ``etc\``            policy, settings, skills.d
          * ``secrets\env``     provider keys (ACL'd; treat the zip
                                as sensitive)
          * ``state\conversations.db`` via SQLite ``.backup``
          * ``state\health.json``
          * ``logs\audit.log``  with hash chain intact

        The full install tree (the payload + venv) is excluded — it is
        reproducible from the release zip.

        Caller is responsible for elevation. Returns the path to the
        created zip.
    #>
    [CmdletBinding()]
    param(
        [string]$DestDir,
        [int]$Retain = 14
    )
    $cfg = $script:AzConfig
    if (-not $DestDir) {
        $DestDir = Join-Path $cfg.StateDir 'backups'
    }
    Ensure-Directory $DestDir | Out-Null

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tempBase = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
    $stage = Join-Path $tempBase "windows-zombie-backup-$stamp"
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Path $stage | Out-Null
    # Canonicalize the staging path. On Windows $env:TEMP can be an 8.3 short
    # path (e.g. RUNNER~1) while Get-ChildItem returns long-form FullNames, so
    # a substring offset against the short path would corrupt manifest entries.
    $stage = (Get-Item -LiteralPath $stage).FullName

    try {
        if (Test-Path $cfg.EtcDir) {
            Copy-Item -Recurse -Force $cfg.EtcDir (Join-Path $stage 'etc')
        }
        if (Test-Path $cfg.SecretsFile) {
            $sDest = Join-Path $stage 'secrets'
            Ensure-Directory $sDest | Out-Null
            Copy-Item -Force $cfg.SecretsFile (Join-Path $sDest 'env')
        }
        if (Test-Path $cfg.StateDir) {
            $stDest = Join-Path $stage 'state'
            Ensure-Directory $stDest | Out-Null
            $db = Join-Path $cfg.StateDir 'conversations.db'
            if (Test-Path $db) {
                # Prefer SQLite online backup if sqlite3.exe is on PATH;
                # fall back to a plain copy after a Stop-Service hint.
                $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
                if ($sqlite) {
                    & $sqlite.Source $db ".backup '$(Join-Path $stDest 'conversations.db')'" | Out-Null
                } else {
                    Copy-Item -Force $db (Join-Path $stDest 'conversations.db')
                }
            }
            $hj = Join-Path $cfg.StateDir 'health.json'
            if (Test-Path $hj) { Copy-Item -Force $hj $stDest }
        }
        if (Test-Path $cfg.LogDir) {
            $lDest = Join-Path $stage 'logs'
            Ensure-Directory $lDest | Out-Null
            foreach ($n in @('audit.log', 'install.log', 'events.log')) {
                $src = Join-Path $cfg.LogDir $n
                if (Test-Path $src) { Copy-Item -Force $src $lDest }
            }
        }

        # Manifest
        $manifestPath = Join-Path $stage 'SHA256SUMS'
        $entries = Get-ChildItem -Recurse -File -Path $stage |
            Where-Object { $_.FullName -ne $manifestPath } |
            Sort-Object FullName |
            ForEach-Object {
                $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower()
                $rel = [System.IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
                "$hash  $rel"
            }
        $entries | Set-Content -LiteralPath $manifestPath -Encoding ascii

        $zip = Join-Path $DestDir "windows-zombie-state-$stamp.zip"
        if (Test-Path $zip) { Remove-Item -Force $zip }
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        Write-AzLog -Level OK "Wrote backup $zip"
    } finally {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }

    if ($Retain -gt 0) {
        Get-ChildItem -File -Path $DestDir -Filter 'windows-zombie-state-*.zip' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $Retain |
            ForEach-Object {
                Remove-Item -Force $_.FullName -ErrorAction SilentlyContinue
                Write-AzLog "Pruned old backup $($_.Name)"
            }
    }

    return $zip
}

function Restore-AiZombieBackup {
    <#
    .SYNOPSIS
        Restore a windows-zombie backup zip into the install root.
    .DESCRIPTION
        Verifies the ``SHA256SUMS`` manifest inside the zip, lays the
        files back into ``<InstallRoot>\{etc,secrets,state,logs}``,
        and re-applies the standard ACLs.

        Refuses to overwrite a running install unless ``-Force`` is
        passed and the service is stopped first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Backup not found: $Path"
    }
    $cfg = $script:AzConfig
    if (Get-Command Get-Service -ErrorAction SilentlyContinue) {
        $svc = Get-Service -Name $cfg.ServiceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running' -and -not $Force) {
            throw "Service $($cfg.ServiceName) is running. Stop it first or pass -Force."
        }
    }

    $tempBase = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
    $stage = Join-Path $tempBase ("windows-zombie-restore-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $stage = (Get-Item -LiteralPath $stage).FullName
    try {
        Expand-Archive -LiteralPath $Path -DestinationPath $stage -Force

        $manifest = Join-Path $stage 'SHA256SUMS'
        if (-not (Test-Path $manifest)) {
            throw "Backup is missing SHA256SUMS manifest: $Path"
        }
        foreach ($entry in Get-Content -LiteralPath $manifest) {
            if (-not $entry) { continue }
            $parts = $entry -split '\s+', 2
            if ($parts.Count -ne 2) { continue }
            $expected = $parts[0].ToLower()
            $rel = $parts[1]
            $file = Join-Path $stage ($rel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $file)) {
                throw "Backup manifest references missing file: $rel"
            }
            $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLower()
            if ($actual -ne $expected) {
                throw "Backup integrity check failed for $rel (expected $expected, got $actual)"
            }
        }
        Write-AzLog -Level OK "Backup integrity verified ($($(Get-Content $manifest).Count) entries)."

        # Restore tree-by-tree.
        foreach ($pair in @(
            @{ Src = 'etc';     Dst = $cfg.EtcDir },
            @{ Src = 'secrets'; Dst = $cfg.SecretsDir },
            @{ Src = 'state';   Dst = $cfg.StateDir },
            @{ Src = 'logs';    Dst = $cfg.LogDir }
        )) {
            $srcPath = Join-Path $stage $pair.Src
            if (-not (Test-Path $srcPath)) { continue }
            Ensure-Directory $pair.Dst | Out-Null
            Copy-Item -Recurse -Force (Join-Path $srcPath '*') $pair.Dst
        }

        # Re-apply ACLs (no-op if the agent user isn't present yet).
        if (Get-Command Get-Acl -ErrorAction SilentlyContinue) {
            Set-AiZombieAcl -Path $cfg.LogDir     -AgentUser $cfg.AgentUser -AgentAccess ReadWrite
            Set-AiZombieAcl -Path $cfg.StateDir   -AgentUser $cfg.AgentUser -AgentAccess ReadWrite
            Set-AiZombieAcl -Path $cfg.SecretsDir -AgentUser $cfg.AgentUser -AgentAccess ReadOnlySecrets
        }

        Write-AzLog -Level OK "Restore complete from $Path"
    } finally {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }
}

function Register-BackupScheduledTask {
    <#
    .SYNOPSIS
        Register a daily ``WindowsZombie-Backup`` Scheduled Task.
    #>
    param(
        [string]$TaskName = 'WindowsZombie-Backup',
        [Parameter(Mandatory)][string]$InstallerPath,
        [string]$RunAt = '03:00'
    )
    $action  = New-ScheduledTaskAction -Execute 'pwsh.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$InstallerPath`" backup"
    $trigger = New-ScheduledTaskTrigger -Daily -At $RunAt
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' `
        -LogonType ServiceAccount -RunLevel Highest

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal `
        -Description "windows-zombie daily state backup." | Out-Null
}
