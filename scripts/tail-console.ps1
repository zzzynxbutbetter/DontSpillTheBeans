# Live-tail the game's console log, optionally filtered: .\scripts\tail-console.ps1 DontSpillTheBeans
# Add -Playtest to follow the isolated instance started by launch-playtest.ps1.
param([string]$Filter = '.', [switch]$Playtest)
$base = if ($Playtest) { Join-Path (Split-Path $PSScriptRoot) 'playtest\Zomboid' } else { Join-Path $env:USERPROFILE 'Zomboid' }
$log = Join-Path $base 'console.txt'
while (-not (Test-Path $log)) { Start-Sleep 1 }
Get-Content $log -Wait -Tail 30 | Select-String $Filter
