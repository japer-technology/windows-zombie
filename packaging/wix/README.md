# WiX (MSI) skeleton

`Windows11Zombie.wxs` lays down the unzipped payload to
`%ProgramFiles%\windows11-zombie\` and runs `Install.ps1 install` as a
custom action. Build with WiX 4:

```powershell
wix build packaging\wix\Windows11Zombie.wxs -o dist\windows11-zombie.msi
```

The MSI is intended for Group Policy / Intune deployment. Detection
rule: existence of `%ProgramData%\AiZombie\bin\windows11-zombie.cmd`.
Uninstall command: `Install.ps1 uninstall -AssumeYes`.
