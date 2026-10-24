# Don't Spill the Beans

A Project Zomboid (Build 42.21) mod. Open food and drink spills when carried loose in pockets, bags or a vehicle; it
makes a mess, seeps through clothes, goes off and smells, burns if hot and foams if shaken. Lua only, written for
multiplayer (the server decides, clients report). See [docs/DontSpillTheBeans/DESIGN.md](docs/DontSpillTheBeans/DESIGN.md)
for how it works.

## Layout
- `mods/DontSpillTheBeans/` the mod (`42/mod.info`, `42/media/...`, `common/`).
- `docs/DontSpillTheBeans/` design notes and `tools/food-rules/` (generates the per-mod item rules in `shared/DSTB_Compat_*.lua`).
- `assets/DontSpillTheBeans/` source art (the source audio is not in the repo, see `CREDITS.md`).

## Trying it
Copy or link `mods/DontSpillTheBeans` into your `Zomboid/mods` folder and enable it on a test save. Never test on a save you care about.

## License
Code: MIT ([LICENSE](LICENSE)). Sounds: edited freesound.org clips under their own licenses ([CREDITS.md](CREDITS.md)).
