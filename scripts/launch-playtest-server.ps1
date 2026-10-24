# Usage: .\scripts\launch-playtest-server.ps1 [-Mods DontSpillTheBeans] [-Reset]
# Starts a local DEDICATED server for multiplayer testing, isolated in .\playtest\Server (-cachedir), so the normal
# ~\Zomboid saves, mods and server settings are never read or written. Then connect the playtest client to it:
#   .\scripts\launch-playtest.ps1 -Connect     (joins 127.0.0.1 as admin; first login creates the character)
# Server console: playtest\Server\server-console.txt (and the window this opens). -Reset wipes the server world first.
# Server-side Lua errors show in that log; client-side ones in playtest\Zomboid\console.txt.
param([string[]]$Mods = @('DontSpillTheBeans'), [switch]$Reset, [string]$Admin = 'admin', [string]$AdminPassword = 'dstb')
$repo  = Split-Path $PSScriptRoot
$cache = Join-Path $repo 'playtest\Server'
$game  = 'W:\SteamLibrary\steamapps\common\ProjectZomboid'
$name  = 'dstbtest'

if ($Reset -and (Test-Path $cache)) { Remove-Item (Join-Path $cache 'Saves') -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $cache 'db') -Recurse -Force -ErrorAction SilentlyContinue; 'reset    server world and accounts' }
New-Item -ItemType Directory -Force (Join-Path $cache 'mods'), (Join-Path $cache 'Server') | Out-Null

foreach ($m in $Mods) {
    $src  = Join-Path $repo "mods\$m"
    $link = Join-Path $cache "mods\$m"
    if (-not (Test-Path $src)) { Write-Warning "no such mod folder: $src"; continue }
    if (-not (Test-Path $link)) { New-Item -ItemType Junction -Path $link -Target $src | Out-Null; "linked   $m" }
}

# Server settings: no empty-pause (so the world keeps running), no password, no Lua checksum (client and server read the same
# junctioned files anyway), not public.
$ini = Join-Path $cache "Server\$name.ini"
if (-not (Test-Path $ini)) {
@"
PublicName=DSTB test server
Public=false
Open=true
Password=
PauseEmpty=false
SteamVAC=false
DoLuaChecksum=false
DefaultPort=16261
UDPPort=16262
Map=Muldraugh, KY
Mods=$($Mods -join ';')
PVP=false
SafetySystem=false
"@ | Set-Content $ini -Encoding UTF8
    "wrote    $ini"
}

# Quiet world for driving tests: no zombies, easy vehicle use, fast days.
$sandbox = Join-Path $cache "Server\${name}_SandboxVars.lua"
if (-not (Test-Path $sandbox)) {
@"
SandboxVars = {
    VERSION = 6,
    Zombies = 6,
    VehicleEasyUse = true,
    CarSpawnRate = 5,
    ChanceHasGas = 1,
    InitialGas = 2,
    CarGeneralCondition = 1,
    StarterKit = false,
}
"@ | Set-Content $sandbox -Encoding UTF8
    "wrote    $sandbox"
}

# Same command line as ProjectZomboidServer.bat, plus our data folder, server name and admin account.
$java = Join-Path $game 'jre64\bin\java.exe'
$javaArgs = @(
    '--enable-native-access=ALL-UNNAMED', '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED',
    '-XX:+UseZGC', '-XX:-CreateCoredumpOnCrash', '-XX:-OmitStackTraceInFastThrow', '-Xmx3072m',
    '-Djava.library.path=./natives/;./natives/win64/;./', '-cp', './;projectzomboid.jar',
    'zombie.network.GameServer', "-cachedir=$cache", '-servername', $name, '-adminusername', $Admin, '-adminpassword', $AdminPassword, '-nosteam'
)
"server   $name on 127.0.0.1:16261 (admin: $Admin / $AdminPassword), data: $cache"
Start-Process $java -ArgumentList $javaArgs -WorkingDirectory $game
