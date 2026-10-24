# Usage: .\scripts\link-mod.ps1 [ModName]   (no arg = link every mod in .\mods)
# Creates a junction in %USERPROFILE%\Zomboid\mods pointing at the source folder here.
# Refuses to touch anything in Zomboid\mods that isn't already a junction to this repo.
param([string]$Name)
$src  = Join-Path (Split-Path $PSScriptRoot) 'mods'
$dest = Join-Path $env:USERPROFILE 'Zomboid\mods'
$mods = if ($Name) { ,(Get-Item (Join-Path $src $Name)) } else { Get-ChildItem $src -Directory }
foreach ($m in $mods) {
    $link = Join-Path $dest $m.Name
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -eq 'Junction' -and $item.Target -contains $m.FullName) { "ok       $($m.Name) (already linked)"; continue }
        "SKIPPED  $($m.Name): $link already exists and is not our junction"; continue
    }
    New-Item -ItemType Junction -Path $link -Target $m.FullName | Out-Null
    "linked   $($m.Name) -> $($m.FullName)"
}
