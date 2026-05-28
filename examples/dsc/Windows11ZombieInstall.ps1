Configuration Windows11ZombieInstall {
    param(
        [string]$ReleaseVersion = '0.0.0',
        [string]$StageDir = 'C:\ProgramData\windows11-zombie-src'
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node 'localhost' {
        File Stage {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = $StageDir
        }

        Script Install {
            DependsOn = '[File]Stage'
            GetScript = { @{ Result = (Test-Path "$using:StageDir\scripts\Install.ps1") } }
            TestScript = {
                $svc = Get-Service -Name 'Windows11Zombie-Chat' -ErrorAction SilentlyContinue
                return ($svc -and $svc.Status -eq 'Running')
            }
            SetScript = {
                $zip = Join-Path $using:StageDir 'release.zip'
                $url = "https://github.com/japer-technology/windows11-zombie/releases/download/v$using:ReleaseVersion/windows11-zombie-$using:ReleaseVersion.zip"
                Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
                Expand-Archive -Path $zip -DestinationPath $using:StageDir -Force
                & (Join-Path $using:StageDir 'scripts\Install.ps1') install -AssumeYes
            }
        }
    }
}
