<#
.SYNOPSIS
    Capture a PNG screenshot of the primary display (gui.screenshot
    backend for the agent runtime).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutPath)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp    = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$g      = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

Write-Host $OutPath
