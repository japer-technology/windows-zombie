# Deploying windows11-zombie via Microsoft Intune

This guide packages windows11-zombie as a Win32 app for Microsoft
Intune so it can be deployed to Azure AD–joined Windows 11 devices.

## 1. Prepare the source folder

```powershell
# Download a tagged release (or run build.ps1 package locally)
mkdir intune-stage
Expand-Archive windows11-zombie-<version>.zip -DestinationPath intune-stage
```

## 2. Build the .intunewin

Use the [Microsoft Win32 Content Prep Tool](https://learn.microsoft.com/mem/intune/apps/apps-win32-prepare).

```powershell
IntuneWinAppUtil.exe -c intune-stage -s scripts\Install.ps1 -o dist
```

## 3. Create the Win32 app in Intune

| Field | Value |
| --- | --- |
| Install command | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install.ps1 install -AssumeYes` |
| Uninstall command | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall.ps1 -AssumeYes` |
| Install behaviour | System |
| Device restart behaviour | No specific action |
| Detection rule | File: `C:\ProgramData\AiZombie\bin\windows11-zombie.cmd` exists |
| Return codes | 0 = success, 3010 = soft reboot |
| Requirements | OS edition: Windows 11 Pro / Ent / Edu; 64-bit; PowerShell 7 |

## 4. Assignments

Target a pilot Azure AD group first. Use the Health-Check task to
monitor; the `state\health.json` file can be uploaded to a Log Analytics
workspace via the Azure Monitor agent for fleet-wide visibility.

## 5. Validation

After deployment, verify on a target device:

```powershell
Get-Service Windows11Zombie-Chat
windows11-zombie verify
```

See also: [OPERATIONS.md](./OPERATIONS.md), [RECOVERY.md](./RECOVERY.md).
