$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$installDir = Join-Path $toolsDir 'app'
if (Test-Path (Join-Path $installDir 'scripts\Uninstall.ps1')) {
    & (Join-Path $installDir 'scripts\Uninstall.ps1') -AssumeYes
}
