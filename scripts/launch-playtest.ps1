# Usage: .\scripts\launch-playtest.ps1 [-Mods DontSpillTheBeans,Other] [-Connect]
# -Connect joins the local test server (start it first with launch-playtest-server.ps1; log in as admin / dstb).
# Launches PZ in -debug against an ISOLATED data folder (.\playtest\Zomboid) via -cachedir, so your
# normal ~\Zomboid saves, mods, options and console.txt are never read or written.
# Mods from .\mods are junctioned into the playtest folder; edit source files in place and re-launch (or reload Lua in debug).
# First run: create a new Sandbox world in the playtest instance, enable the mod on it. Watch with: .\scripts\tail-console.ps1 -Playtest
param([string[]]$Mods = @('DontSpillTheBeans'), [switch]$Connect)
$repo  = Split-Path $PSScriptRoot
$cache = Join-Path $repo 'playtest\Zomboid'
$game  = 'W:\SteamLibrary\steamapps\common\ProjectZomboid'
New-Item -ItemType Directory -Force (Join-Path $cache 'mods') | Out-Null

foreach ($name in $Mods) {
    $src  = Join-Path $repo "mods\$name"
    $link = Join-Path $cache "mods\$name"
    if (-not (Test-Path $src)) { Write-Warning "no such mod folder: $src"; continue }
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -eq 'Junction') { "ok       $name (already linked)"; continue }
        Write-Warning "SKIPPED $name`: $link exists and is not a junction"; continue
    }
    New-Item -ItemType Junction -Path $link -Target $src | Out-Null
    "linked   $name -> $src"
}

# Playtest-only helper mod (repo: scripts\playtest-mod\DSTBPlaytest): starts Patrick's Debug Scenario with the DSTB vehicle test setup.
$helperSrc  = Join-Path $PSScriptRoot 'playtest-mod\DSTBPlaytest'
$helperLink = Join-Path $cache 'mods\DSTBPlaytest'
if (-not (Test-Path $helperLink)) { New-Item -ItemType Junction -Path $helperLink -Target $helperSrc | Out-Null; 'linked   DSTBPlaytest (playtest helper)' }

# Make sure the default mod list (used by debug scenarios and new worlds) has the helper and the food mods we have rules for.
$defaults = Join-Path $cache 'mods\default.txt'
if (Test-Path $defaults) {
    $text = Get-Content $defaults -Raw
    $missing = @('DSTBPlaytest', 'SapphCooking_B42', 'bdtmre', 'StarvingZombies') | Where-Object { $text -notmatch "mod = $_," }
    if ($missing) {
        $add = ($missing | ForEach-Object { "    mod = $_," }) -join "`r`n"
        $text = $text -replace '(mods\s*\{
?
)', "`$1$add`r`n"
        Set-Content $defaults $text -NoNewline
        "added to default mod list: $($missing -join ', ')"
    }
}

# Seed display/input options once so the playtest instance opens like your normal one (copy only; never written back).
$opts = Join-Path $cache 'options.ini'
$real = Join-Path $env:USERPROFILE 'Zomboid\options.ini'
if (-not (Test-Path $opts) -and (Test-Path $real)) { Copy-Item $real $opts; 'seeded   options.ini from your normal install' }

"data dir: $cache"
$gameArgs = @('-debug', "-cachedir=$cache")
if ($Connect) {
    # The test server runs without Steam, and a Steam client can only join Steam servers. -nosteam on the command line is read
    # too late (Steam mode is fixed when the class loads), so start the game the way the launcher would, but with
    # -Dzomboid.steam=0 (see ProjectZomboid64.json for the original JVM options).
    $javaArgs = @('-Djava.awt.headless=true', '--enable-native-access=ALL-UNNAMED', '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED',
        '-Xmx8192m', '-Dzomboid.steam=0', '-Dzomboid.znetlog=1', '-Djava.library.path=win64/;.',
        '-XX:-CreateCoredumpOnCrash', '-XX:-OmitStackTraceInFastThrow', '-XX:+UseZGC',
        '-cp', '.;projectzomboid.jar', 'zombie.gameStates.MainScreenState') + $gameArgs + @('-nosteam', '+connect', '127.0.0.1')
    Start-Process "$game\jre64\bin\java.exe" -ArgumentList $javaArgs -WorkingDirectory $game
} else {
    Start-Process "$game\ProjectZomboid64.exe" -ArgumentList $gameArgs -WorkingDirectory $game
}
