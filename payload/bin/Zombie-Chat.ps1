<#
.SYNOPSIS
    Print the chat URL, RDP/SSH tunnel example, and the operator's
    debugging entry points for windows11-zombie.
#>
[CmdletBinding()]
param()

$port = if ($env:ZOMBIE_CHAT_PORT) { $env:ZOMBIE_CHAT_PORT } else { 7878 }
$host = [System.Net.Dns]::GetHostName()
$installRoot = if ($env:AI_ZOMBIE_ROOT) { $env:AI_ZOMBIE_ROOT } else { Join-Path $env:ProgramData 'AiZombie' }

@"
Windows 11 Zombie chat
----------------------

Local URL:
  http://127.0.0.1:$port/

Remote (from a device on your Tailscale network):
  ssh -L ${port}:127.0.0.1:${port} zombie@$host
  # then open http://127.0.0.1:$port/ in your local browser
  # — or use Remote Desktop: mstsc /v:$host:3389

Service control (run from an elevated shell):
  Get-Service Windows11Zombie-Chat
  Restart-Service Windows11Zombie-Chat
  Get-WinEvent -LogName Application -MaxEvents 100 | Where-Object ProviderName -match 'Windows11Zombie'

Health and diagnostics:
  & '$installRoot\bin\Health-Check.ps1'
  & '$installRoot\bin\Collect-Diagnostics.ps1'
  & '$installRoot\bin\Secrets-Edit.ps1'

Audit log:
  & '$installRoot\bin\Audit-Recent.ps1'                       # last 25 entries
  & '$installRoot\bin\Audit-Recent.ps1' -Follow               # stream new entries
  & '$installRoot\bin\Audit-Recent.ps1' -Type tool_call,provider_error
  & '$installRoot\bin\Audit-Recent.ps1' -All

Verbose audit (testing only):
  [Environment]::SetEnvironmentVariable('ZOMBIE_AUDIT_VERBOSE','1','Machine')
  Restart-Service Windows11Zombie-Chat
"@
