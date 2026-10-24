# Don't Spill the Beans

A Project Zomboid (Build 42.21) mod. Open food and drink spills when carried loose in pockets, bags or a vehicle; it
makes a mess, seeps through clothes, goes off and smells, burns if hot and foams if shaken. Lua only, written for
multiplayer (the server decides, clients report). See [docs/DontSpillTheBeans/DESIGN.md](docs/DontSpillTheBeans/DESIGN.md)
for how it works and [docs/DontSpillTheBeans/WORKSHOP.txt](docs/DontSpillTheBeans/WORKSHOP.txt) for the Workshop page text.

## Layout
- `mods/DontSpillTheBeans/` the mod (`42/mod.info`, `42/media/...`, `common/`).
- `docs/DontSpillTheBeans/` design notes, Workshop description, and `tools/food-rules/` (generates the per-mod item rules in `shared/DSTB_Compat_*.lua`).
- `assets/DontSpillTheBeans/` source art; the source WAV files are not in the repo (see `CREDITS.md`).
- `scripts/` `master-audio.py` (source WAVs to the shipped OGGs and sound script), `check-lua.ps1` (syntax check with LuaJIT:
  `winget install DEVCOM.LuaJIT`), `link-mod.ps1` / `unlink-mod.ps1`, `launch-playtest*.ps1` (an isolated game instance that
  never touches your saves), `tail-console.ps1`.

## Trying it
`.\scripts\link-mod.ps1 DontSpillTheBeans`, then enable it on a test save. Never test on a save you care about.

## License
Code: MIT ([LICENSE](LICENSE)). Sounds: edited freesound.org clips under their own licenses ([CREDITS.md](CREDITS.md)).
