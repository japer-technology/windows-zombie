<#
.SYNOPSIS
    GUI input helper used by the agent's gui.click and gui.type tools.

.DESCRIPTION
    Implements two narrow actions only:
      Click  — move the cursor and click at absolute screen coordinates
      Type   — send Unicode keystrokes via SendKeys

    The agent runtime calls this script with a closed argument shape;
    free-form scripting is intentionally out of scope.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Click','Type')][string]$Action,
    [int]$X = 0,
    [int]$Y = 0,
    [ValidateSet('1','2','3')][string]$Button = '1',
    [string]$Text = ''
)

Add-Type -AssemblyName System.Windows.Forms

switch ($Action) {
    'Click' {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Mouse {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
'@ -ErrorAction SilentlyContinue
        [Mouse]::SetCursorPos($X, $Y) | Out-Null
        Start-Sleep -Milliseconds 50
        $down = switch ($Button) { '1' { 0x0002 } '2' { 0x0020 } '3' { 0x0008 } }
        $up   = switch ($Button) { '1' { 0x0004 } '2' { 0x0040 } '3' { 0x0010 } }
        [Mouse]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
        [Mouse]::mouse_event($up,   0, 0, 0, [UIntPtr]::Zero)
        Write-Host "clicked $X,$Y button=$Button"
    }
    'Type' {
        # SendKeys treats {}+^%~ as control characters; escape them.
        $escaped = $Text -replace '([+^%~(){}\[\]])', '{$1}'
        [System.Windows.Forms.SendKeys]::SendWait($escaped)
        Write-Host "typed $($Text.Length) char(s)"
    }
}
