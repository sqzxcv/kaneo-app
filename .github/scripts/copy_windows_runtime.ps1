$ErrorActionPreference = 'Stop'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'Visual C++ tools were not found.' }
$crt = Get-ChildItem "$installation\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { throw 'The redistributable x64 VC runtime was not found.' }
$bundle = 'build/windows/x64/runner/Release'
Copy-Item "$($crt.FullName)\*.dll" $bundle
foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    if (-not (Test-Path "$bundle/$name")) { throw "Missing runtime library: $name" }
}
Write-Output 'Copied the redistributable application-local x64 VC runtime.'
