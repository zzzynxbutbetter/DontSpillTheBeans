# Syntax-checks every .lua file under mods/ (or the given mod folder) with LuaJIT, which parses Lua 5.1 like the game's Kahlua.
# It cannot catch runtime errors or wrong API calls, only syntax. Also flags `goto` / `::label::`, which LuaJIT accepts and Kahlua does not.
# Install once: winget install DEVCOM.LuaJIT
param([string]$Mod = "")

$luajit = (Get-Command luajit -ErrorAction SilentlyContinue).Source
if (-not $luajit) { $luajit = "$env:LOCALAPPDATA\Programs\LuaJIT\bin\luajit.exe" }
if (-not (Test-Path $luajit)) { Write-Error "luajit not found (winget install DEVCOM.LuaJIT)"; exit 2 }

$root = Join-Path $PSScriptRoot "..\mods"
if ($Mod) { $root = Join-Path $root $Mod }
$bad = 0; $n = 0
foreach ($f in Get-ChildItem $root -Recurse -Filter *.lua) {
    $n++
    $out = & $luajit (Join-Path $PSScriptRoot "check-lua.lua") $f.FullName 2>&1
    if ($LASTEXITCODE -ne 0) { $bad++; Write-Host "SYNTAX  $($f.FullName)`n        $out" -ForegroundColor Red }
    $g = Select-String -Path $f.FullName -Pattern '^\s*goto\s|::\w+::' | Select-Object -First 1
    if ($g) { $bad++; Write-Host "GOTO    $($f.FullName):$($g.LineNumber) (Kahlua has no goto)" -ForegroundColor Red }
}
Write-Host "$n files checked, $bad problem(s)"
exit ([int]($bad -gt 0))
