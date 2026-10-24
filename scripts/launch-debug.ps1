# Launches PZ directly (not via Steam) with -debug so you get the debug menu, Lua console and quick reloads.
# Your normal Steam launch options are untouched. Steam must be running.
$game = 'W:\SteamLibrary\steamapps\common\ProjectZomboid'
Start-Process "$game\ProjectZomboid64.exe" -ArgumentList '-debug' -WorkingDirectory $game
