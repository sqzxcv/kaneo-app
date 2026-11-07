$ErrorActionPreference = 'Stop'
$packages = @(Get-ChildItem 'build/installers/*-setup.exe')
if ($packages.Count -ne 1) { throw 'Expected exactly one installer.' }
$installer = $packages[0].FullName
$installed = Join-Path $env:RUNNER_TEMP "Kaneo-install-$([guid]::NewGuid())"
$setup = Start-Process $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installed`"") -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Installer failed: $($setup.ExitCode)" }
$app = $null
try {
    foreach ($name in @('kaneo_app.exe', 'flutter_windows.dll', 'vcruntime140.dll', 'msvcp140.dll', 'data/app.so')) {
        if (-not (Test-Path (Join-Path $installed $name))) { throw "Installed file missing: $name" }
    }
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class KaneoWindowProbe {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
}
'@
    $app = Start-Process (Join-Path $installed 'kaneo_app.exe') -PassThru
    $deadline = (Get-Date).AddSeconds(45)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        $app.Refresh()
        if ($app.HasExited) { throw "Installed app exited: $($app.ExitCode)" }
        $rect = New-Object KaneoWindowProbe+Rect
        if ($app.MainWindowHandle -ne 0 -and [KaneoWindowProbe]::GetWindowRect($app.MainWindowHandle, [ref]$rect)) {
            $width = $rect.Right - $rect.Left
            $height = $rect.Bottom - $rect.Top
            if ($width -ge 960 -and $height -ge 700) {
                @{ width = $width; height = $height; installedFrom = (Split-Path $installer -Leaf) } |
                    ConvertTo-Json | Set-Content 'build/installers/windows-startup.json'
                $ready = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Installed Windows app never produced its minimum Flutter window.' }
    Write-Output 'Installed Windows app launched and configured its desktop window.'
} finally {
    if ($app -and -not $app.HasExited) { Stop-Process -Id $app.Id -Force }
    $uninstaller = Join-Path $installed 'unins000.exe'
    if (Test-Path $uninstaller) {
        $removed = Start-Process $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
        if ($removed.ExitCode -ne 0) { throw "Uninstall failed: $($removed.ExitCode)" }
    }
}
if (Test-Path (Join-Path $installed 'kaneo_app.exe')) { throw 'Uninstall left the application executable behind.' }
