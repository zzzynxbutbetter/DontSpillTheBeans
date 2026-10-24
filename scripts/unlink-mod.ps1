# Usage: .\scripts\unlink-mod.ps1 ModName  -- removes only the junction, never the source files.
param([Parameter(Mandatory)][string]$Name)
$link = Join-Path $env:USERPROFILE "Zomboid\mods\$Name"
$item = Get-Item $link -Force -ErrorAction Stop
if ($item.LinkType -ne 'Junction') { throw "$link is not a junction; refusing to remove." }
$item.Delete()
"unlinked $Name"
