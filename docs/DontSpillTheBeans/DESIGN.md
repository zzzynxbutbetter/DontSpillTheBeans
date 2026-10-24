# Don't Spill the Beans — design

ModId: `DontSpillTheBeans` · source: `mods/DontSpillTheBeans/` · Workshop title: **Don't Spill the Beans** · status: **feature-complete prototype; the spill rules, vehicles, hot spills, sounds and tooltips have been played in single player; stumbles, traits, souring, the inventory tint, the scent integration and everything in multiplayer are written but not yet played — see "Implementation status" and "Known gaps"**
Must be written multiplayer-aware from the start (see root `CLAUDE.md`). Lua only; no Java patching.

## Goal
Make storing open containers of food/liquid in moving storage impractical or dangerous unless the right
precautions are taken. Realism first; the main gameplay implication (zombie attraction via smell) is still to be ideated.

## Core rule
An **open container holding food or liquid** that is stored in a **container that moves** may spill when the character moves.

- Open containers: bowls, cups, mugs, plates, glasses, open jars, etc.
- Moving storage: backpacks, worn clothing with pockets, vehicle trunk/seat containers, carried bags.
- Not moving storage: containers on the ground / in world furniture (does not spill).
- Trigger: the character moves while the item is stored. **Physics is deliberately light** — no acceleration or real
  physics modelling; imperfect realism is fine.
- **On foot**: spill accumulates **over time** according to the character's locomotion state. Each state has its own
  rate: `crouched/sneaking` < `walking` < `running` < `sprinting` (standing still = 0).
- **Vaulting** (climbing over fences/windows/walls) is an **instantaneous event**: one fixed chunk of spill per vault,
  not a rate over time. Tripping, being bumped or knocked down and falling count as the same kind of event.
- **Traits** scale what is lost: Graceful / Clumsy on foot, Speed Demon / Sunday Driver at the wheel (see "Traits").
- **Vehicles**: spill accumulates over time from **vehicle velocity alone** (speed), with its **own rate curve and Sandbox
  multiplier**, separate from on-foot rates. A global scale would make driving absurdly punishing. Standing/parked = 0.
- Liquids spill much more easily than foods (a per-type multiplier applies on top of all the rates above).

## Prevention (no spill)
- Held in **Equipped Primary / Secondary** hands.
- Nested inside a **Plastic Bag** or **Lunchbox** (the filled container must be inside it).
- **Sealed/closed containers never spill**: water bottles, boxes of food, lidded jars. *Open* jars do spill unless protected as above.
- **Frozen** food/fluids don't spill. As they thaw they start to spill unless stored properly.

## Consequences
1. **Contents decrease**: fluid amount drops (liquids); nutrition/hunger value drops (foods).
2. **The storing container becomes "Dirty"** (backpack, clothing, etc.) and needs washing.
3. **Other items in that container may also get Dirty / wet / otherwise degraded** (chance-based).
   - Items **nested in their own container are immune** (e.g. bandage in a first-aid kit inside the same backpack).
4. **Hot spills** (hot food/liquid) can give minor **burns on torso/legs** when the storage is worn clothing.
   Should heal faster than fire burns.
5. **Smell:** food and edible drinks leave scent that Starving Zombies can use (see "Scent"), and a bag with anything but water spilled in it goes off after seepage starts, giving its carrier the Bad Smell moodle (see "Souring").
6. **Audio cues:** built (see "Sounds"): contents shuffling in a moving bag, emptying, burns and foaming over. **Player feedback only — zombies must NOT react to
   these sounds** (local emitter; never `WorldSoundManager.addSound`). Zombie attraction, if any, comes only from the separate scent mechanic.

## Original open questions (all answered; the sections further down describe the result)
- **Scent:** the Java has no smell model for zombies, so the optional Starving Zombies integration adds scent to the player (see "Scent"); the mod itself makes no world noise.
- **Open vs sealed:** rule tables in `DSTB_Config.lua` filled by the markup tools (see "Spill rules" and "Tooling").
- **Moving:** the owning client reports locomotion every 2 s (`DSTB_Motion`), the server watches vehicles itself (`Spill.vehicleTick`).
- **Dirty bags:** only bags with a `BloodLocation` can hold engine dirt (respected); wetness is the mod's own (`DSTB_Wet`).
- **Burns:** a vanilla body-part burn with a small strength (see "Hot spills").
- **Tuning:** one sandbox page, see "Player-facing features".
- **Server vs client:** the server decides everything; clients report motion and play sounds.

## Starting points in the game code (recon notes from the first phase, kept for reference; the implementation sections below are authoritative)
Java (read `reference/game-java/zombie/...`; call from Lua through the exposed methods):
- Fluids: `entity/components/fluids/FluidContainer.java` (amount, `Fluid`, `FluidConsume`, `FluidUtil`, `FluidProperties`,
  `SealedFluidProperties`) — also check how the vanilla Lua in `reference/game-media/lua/client/Fluids/` empties/transfers.
- Food: `inventory/types/Food.java` — `getHungChange/setHungChange`, `getThirstChange`, `getCalories`, `getHeat/setHeat`
  (hot detection), `isFrozen`, `isRotten`, `isCookedInMicrowave`.
- Dirtiness/wetness: `inventory/types/Clothing.java` — `getDirtiness/setDirtiness`, `getWetness/setWetness`, `isDirty`,
  blood level methods. Verify what applies to bags (`InventoryContainer`) vs clothing, and for the "other items affected" roll.
- Burns: `characters/BodyDamage/BodyPart.java` — `setBurned`, `getBurnTime/setBurnTime`, `AddDamage`, `setAdditionalPain`.
- Events (`Lua/LuaEventManager.java`): `OnPlayerMove`, `OnPlayerUpdate`, `OnTick`, `EveryOneMinute`.
- Sound: `WorldSoundManager.addSound(source,x,y,z,radius,volume)` for zombie-audible noise; `GameSounds` for custom
  audio banks (custom sound files need a sound script in the mod).
- Vanilla items: `Bowl`, `GlassTumbler`, `GlassWine`, `Lunchbox`, `Lunchbag`, `PaperBag`, etc. in `reference/game-media/scripts/`.
  Locate the plastic bag item(s) and mugs/cups/jars with a fresh search (my quick grep did not confirm exact names).

## Motion APIs (found by grep; semantics unverified)
- Locomotion state (`characters/IsoGameCharacter.java`, `IsoPlayer.java`): `isSprinting`, `isRunning`, `isSneaking`,
  `isPlayerMoving` / `isMoving`, `IsoPlayer.isWalking`, `isClimbing`. Walking = moving and not running/sprinting/sneaking.
  Rate = f(state) per elapsed time; no position-delta math needed on foot.
- Vaulting: `isClimbing()` plus animation variables seen in the fence-climb state code (`ClimbFence`, `ClimbingFence`,
  `ClimbFenceStarted`, `ClimbFenceOutcome`); vanilla Lua has `ISClimbOverFence` and anim sets under `AnimSets/player/`
  (`climbfence`, `climbwindow`, `climbwall`). Open: pick one reliable trigger so each vault fires **once** (e.g. edge of the
  climbing flag false->true, or the start of the timed action) and decide which of fence/window/wall count.
- Vehicle (`vehicles/BaseVehicle.java`): `getCurrentSpeedKmHour`, `getCurrentAbsoluteSpeedKmHour`, `getSpeed2D`,
  `getLinearVelocity`. Use speed only. Check whether this is readable on the server and on non-driver clients.
- Events: `OnPlayerUpdate` (per tick, per local player) is the natural place to accumulate time-based spill;
  throttle (every N ticks, scale by elapsed time). `OnPlayerMove`, `OnTick`, `EveryOneMinute` also exist.
- Vehicle occupants/containers (trunk, seats, glovebox) hold items that move with the vehicle, not the character — need a
  cheap way to enumerate them and decide which side is responsible.

## Multiplayer notes
- Server is authoritative for: spill amounts, contents changes, dirtying, burns. Clients only play sounds/UI.
- Movement is known on the owning client; send compact, rate-limited summaries to the server via
  `sendClientCommand("DontSpillTheBeans", ...)` and validate there (clamp distance/speed). Vehicles: prefer server-side vehicle data.
- Item/fluid changes must replicate (check the right sync calls for inventory items and FluidContainers).
- Avoid per-tick scans of every player's whole inventory; scan only when movement crosses a threshold, and index candidates.
- Test: single player first, then a hosted session with two clients, then dedicated server.

## Suggested phases (all done except the multiplayer hardening)
1. **Recon**: confirm APIs above, decide "open container" detection, "moving" detection, "dirty" for bags.
2. **MVP (SP-correct, MP-shaped)**: liquid spill from open containers in worn/backpack containers on movement; reduce fluid; dirty the bag. Shared config + Sandbox options.
3. Food spill, prevention rules (hands, plastic bag, lunchbox, sealed/jars), nested-container immunity, frozen/thaw.
4. Collateral damage to other items, hot-spill burns, audio cues.
5. Vehicles (trunk/seat), then smell/scent design.
6. Multiplayer hardening and tuning.

## Implementation status
Code: `mods/DontSpillTheBeans/42/media/lua/` (+ `sandbox-options.txt`, JSON translations in `shared/Translate/EN/`). Last updated 2026-10-23.
**Played in single player by the user:** liquid and food spill, frozen and cold rules, item-card lines, emptying a bag, bag and clothing wetness and dirt, seepage, third-party compat (VFE, Pomp's, Sapph's, MRE), vehicles (driving, towing, rolling empty cars; a dedicated server with one client confirmed the vehicle speeds), hot spills, and the whole sound system (2026-10-23 checklist: every layer, fades, loops, hearing variants, nested muffling, levels next to Dynamic Gear Rattling).
**Written, not yet played:** stumble and fall spills, the Graceful / Clumsy / Speed Demon / Sunday Driver traits, souring and the Bad Smell moodle, the inventory tint, the carried-bag cache, seepage for pocket and hand-held bags, the seepage-inheritance rework, auto-equip of "At 100%" items, washer/dryer processing, rain and sweat wetting, the Starving Zombies scent, and **everything in real multiplayer** (sound relay, hot burns, scent, fizz, washer, dryer, nested seepage).

### Files
- `shared/DSTB_Config.lua` – tunables and rule tables (extendable by other mods): `OpenContainerNames`, `OpenFluidItems`, `SealedFluidItems`, `SealedWhenFull`,
  `ProtectiveContainers`, `FoodExempt`, `FoodExemptWhenUneaten`, rates, seepage, wetness and washer numbers, plus the sandbox helpers
  (`isEnabled`, `wetEnabled`, `dirtyEnabled`, `foodSpillEnabled`, `atFullMode`, `emptySeconds`, `autoEquipEnabled`, `sourEnabled`, `traitFactor`, `drivingFactor`).
- `shared/DSTB_Spill.lua` – authoritative logic. `openKind` decides what can spill; `hint` tells the player (same rules, so they cannot disagree);
  `apply` accrues per-item spill debt and applies it in steps; `vehicleTick`, `seep`, `contaminateAll`, `applyEnvironment`, `findBag`, `foamOnClothing`.
- `shared/DSTB_Wet.lua` – bag wetness (ModData), "(Wet)" naming and tooltip, what is spilled in a bag (`bagAmounts`, `spilledAmounts`) and souring (`goOff`, `makeSour`). `shared/DSTB_Fizz.lua` – fizzy drinks (shake, foaming over). `DSTB_Wash.lua` – sink washing. `DSTB_Washer.lua` – washer/dryer; with `WasherFillsContainers` an open fluid container directly inside a washed bag has its contents replaced by 20-100% of its capacity in water, once per wash (the machine's `run` id is stored on the item), and any food in an open vessel (`isFoodInOpenVessel`: has a ReplaceOnUse and is not exempt) becomes the empty vessel holding water. With `DryerEmptiesOpenContainers` a dryer empties open fluid containers directly inside a bag completely and takes `DryerNutritionPer5Min` (2; script units, prorated per minute) times the food's thirst share (thirst / (hunger + thirst): tea 1, soup 0.5) out of liquid-flagged foods (hunger and thirst each) until they become their empty vessel; other foods are untouched by the dryer. Both vanilla cycles are 90 in-game minutes (`cycleLengthMinutes` in `ClothingWasherLogic` / `ClothingDryerLogic`), so with the default a mug of tea (20) is gone after 10 steps (50 minutes), a bowl of soup (15, half thirst) after 15 (75 minutes), a bucket of soup (40) only loses 18 and a tin of soup (mostly hunger) about 5.
- `shared/DSTB_Compat.lua` loads the generated `DSTB_Compat_<Mod>.lua` (food rules) and `DSTB_Compat_<Mod>_Containers.lua` (fluid containers, bags) for
  Vanilla, VFE (3577903007), Pomp's (2792348686), Sapph's Cooking (3409143790) and MRE (3765409550). Vanilla loads first. Each file only sets entries keyed
  by full item type, so a mod that is not installed is harmless and any combination works.
- `server/DSTB_Server.lua` – validates client reports, applies spills, `emptySpilled`, the sound relay (`soundState`, `soundRequest`), debug commands (`debugGive`, `debugMultiplier`, `debugSoil`, `debugSour`...), the ten-minute and one-minute ticks.
- `client/` – `DSTB_Motion` (samples locomotion, vaults and stumbles, rain, sweat; sends every 2 s), `DSTB_Client` (halo text and server messages), `DSTB_Menu` + `DSTB_EmptyAction`
  (Empty Spilled Contents), `DSTB_Names` (keeps "(Wet)" names in step), `DSTB_Tooltip` (item-card lines), `DSTB_Audio` (sounds), `DSTB_Carried` (cache of what the bags hold), `DSTB_Smell` (Bad Smell moodle), `DSTB_Tint` (inventory rows), `DSTB_AutoEquip` ("At 100%" items), `DSTB_Options` (Mod Options page), `DSTB_Scent` (Starving Zombies), `DSTB_Debug` (debug-only menu).

### Spill rules (current)
- **Liquids** spill from open fluid containers at any depth unless a protective container (plastic bag, lunchbox, cooler, cookie jar, grocery bag) shields them.
  Per-item precedence: cold (item heat below `ColdFluidBelowHeat`=1.0, i.e. the blue inventory shading; liquids cannot freeze in vanilla, so cold counts as frozen) →
  factory-sealed (script `Opened=false`) → `SealedFluidItems` → `SealedWhenFull` (spills once not full) → `OpenFluidItems` → container-name rule.
- **Food** loose directly in a carried bag is crushed (nutrition loss, dirty bag); any nested container keeps it safe; food loose in the pockets spills too unless the sandbox option `FoodSpillsInPockets` is off.
  Skipped: foods with no nutrition, `FoodExempt`, closed cans/jars (by rule), `FoodExemptWhenUneaten` while whole. "Whole" compares raw `getHungChange()` with `getBaseHunger()`,
  so cooking, staleness and freezing never make an item look eaten. Frozen food is solid and never spills while it stays frozen (like cold liquids); it spills normally again once thawed. Food-type drinks (tea in a mug) spill like liquids.
- **Consequences:** water only wets; other liquids wet and dirty; food only dirties. The storing bag gets wetness and dirt; a spilled-in bag the player carries seeps into clothing
  (by body part: legs, feet, torso, arms, head; outside in within each, socks before shoes; dresses, suits and unlisted garments by location or coverage, see `Config.ClothingOrder`) at 75 wet per step, passed down the body as described under "Seepage down the body".
- **Bag wetness** is ours (vanilla bags have none): rain, sweat soak-through, broken windshield, sink washing; dries 40/h when carried and half that when worn (`WornDryFactor`; worn clothing dries slowly in vanilla). Vanilla wording: "Wet" above 25, "Soaked" at 100,
  "(Wet)" name prefix unless the player renamed the bag. A spilled-in bag keeps its wetness until emptied or washed.
- **Washer/dryer:** cannot start with a spilled-in bag inside. Bags in a running machine are tracked and processed every game minute: bag dirt cleans gradually,
  directly contained clothing/towels get wet or dry (swapping to wet variants), nested containers shield. Dryer dries bags at the clothing rate.

### Vehicles
Speed-based spill with its own bands and rates (`VehicleBandsKmh`, `VehiclePercent`: crawl, city, road, highway, separate for liquids and food; all sandbox options). The **server watches the vehicles itself** (`Spill.vehicleTick`, about once a second from `Events.OnTick` in `DSTB_Server.lua`);
clients report nothing about vehicles. For each vehicle above the lowest band it spills (1) what each player aboard carries (same candidates as on foot)
and (2) loose cargo in the vehicle's containers (seats, trunk, glovebox, including bags in them; loose items with no bag are simply lost). A towed vehicle
takes its speed from whatever tows it, since its own physics may be off. Cargo of a vehicle with nobody aboard is attributed to the nearest player within the sandbox range (needed for item syncing; no message is shown). Written, not yet playtested.
**Verified in a hosted session (dedicated server + one client, 2026-10-20):** a remote driver's speed read on the server matches the distance the car travels
(within ~10%); a towed vehicle with nobody in it reports its own speed, equal to the tow car's, and the cargo of both cars spilled together; loose cargo in a
bag in the trunk wets the bag. Unoccupied parked vehicles read 0 and show phantom "moves" of 100+ km/h in the probe when they stream in; that is a position jump, not
motion, which is why speed is never derived from distance travelled.
**Empty rolling vehicle:** in multiplayer a client may only apply physics to a vehicle it has authority over (`hasAuthorization`), and an unoccupied vehicle belongs to the
server, which runs no vehicle physics, so an empty car cannot be shoved or roll (a debug shove from outside did nothing; the same shove from inside the car worked). Nothing to
handle there. The workshop mod "More Car Features" (3520758551) lets a character leave a moving car, but its code deliberately forces the *driver* to stop first in multiplayer ("car desync is bad"), so an abandoned moving car happens in single player only; passengers hopping out leave the driver driving. In single player an empty car is simulated locally and its speed reads normally; verified in a single-player test with the debug roll from outside the car: the empty car's `reported` speed tracks `moved` (e.g. 111.9 vs 99.1 km/h), and its trunk/seat cargo spilled while it rolled. An unoccupied vehicle's spill is attributed to the nearest player within the sandbox range `UnattendedVehicleRange` (default 60 tiles, 0 = off; note it has no effect in multiplayer, where empty vehicles cannot roll). The game stops simulating a vehicle once the chunks around it are unloaded, but how far that is was not measured, so the range is a setting rather than a claim. Only someone aboard gets the "Spilled!" message; cargo spilling in a car the player is not in is silent.
Debug menu > "Toggle vehicle probe" logs, once a second, every vehicle that moves by reported speed OR by distance travelled.

### Player-facing features
- **Overhead note** when something spills, written as a thought and at most two lines per tick: "Something spilled in my backpack." (the bag's plain lower-case
  name, or the player's own name for it; "my pockets" for loose pocket spills), "Something spilled in several places." when more than one container of the
  character spilled, and a separate "Something spilled in my car." when cargo in the vehicle the player is in spilled. Lines are joined with `[br/]`.
- **Empty Spilled Contents:** bag is taken off (worn or held), emptied onto the tile, then put back (a bag that was inside another bag goes back into it, not into the pockets). Emptying time is a sandbox option (default 6 s at normal speed;
  action time runs at 0.8 x 60 = 48 units per second, scales with game speed, vanilla mood/pain delays apply).
- **Item card line** for anything the mod touches (also items lying on the ground, and empty fluid containers: "Will spill once filled, unless in a protective container"): "Safe to carry in a bag", "...while uneaten", "...while full", "Frozen: Safe to carry in a bag",
  "Spills unless in a protective container", "Crushed if loose. Safe in a nested container.", bags: "Prevents spillage" /
  "Does not prevent spillage". Where spilling in the pockets is possible the wording is "Safe to carry" ("...until thawed") instead of "in a bag". Bag cards also show "Wetness: N%" and "Dirt: N%" (from 5%), and a bag with something spilled in it says so (and says when it has gone off). Implemented by borrowing the item's single tooltip line during render. No line for empty containers, foods with no nutrition,
  or when the mechanic is off. Mod Options (client): sound volumes and the inventory tint.
- **Sandbox:** one page (extra pages would clutter the page list), split into sections by do-nothing toggles used as headings (`SectionGeneral`, ... labelled "---- MOVEMENT ----"). All defaults equal the values in `DSTB_Config.lua`; code reads them through `DSTB.value(key)`, `DSTB.footRate(state, kind)`, `DSTB.vehicleRate(band, kind)`, `DSTB.vaultSpill(kind)`, `DSTB.vehicleBandLimits()` and `DSTB.spillInterval()`, which fall back to the Config default when an option is missing. Spill amounts are written as percent of the full amount lost per spill, one spill every `SpillIntervalSeconds` (3) of that activity (internally percent / 100 / interval per second, accumulated as spill debt in small steps). Liquids (and drinks such as tea) and food have separate values, liquids spill more easily. There is no overall or vehicle multiplier option; the debug menu's "Spill rate xN" (single player) still scales everything via `DSTB.debugMultiplier`.
  - *General:* Enabled, SpillIntervalSeconds, EmptyDurationSeconds, DirtyContainers, WetClothing (liquids only; foods flagged as liquid count as liquids for wetting, at the volume estimated from the food (see below)), ColdLiquidsSafe (cold liquids count as frozen; on).
  - *Movement* (% per spill, liquid / food): sneak 10/5, walk 15/10, run 25/12, sprint 40/15; climbing or falling 75/25 (`VaultSpillLiquid/Food`: climbing over a fence, window or wall, tripping, being bumped or knocked down, falling), GracefulReducePercent (50), ClumsyIncreasePercent (40).
  - *Food:* FoodSpillage, FoodSpillsInPockets, AtFullRules ("At 100%" foods exempt while whole), AtFullAsSealed (off by default: "At 100%" foods never spill).
  - *Vehicles:* VehicleSpills, TowedVehicleSpills, UnattendedVehicleRange (60), % per spill liquid / food: crawl 5/0, town 10/2, road 25/5, highway 40/15; band limits VehicleSpeedIdle/Crawl/City/Road (km/h: 3/15/45/80), SpeedDemonReducePercent (25), SundayDriverIncreasePercent (33).
  - *Bags and Clothing:* SeepAfterMinutes (15), HotSeepAfterMinutes (15), RainSweatWetsBags (on), SeepMinWet (25), SeepMinDirtPercent (50), ContentsWetPerStep (1000), ContentsDirtPercent (10), SeepWetPerStep (75), SeepInheritPercent (60), FoamInheritPercent (60), DirtLiquidPercent (2.5), DirtFoodPercent (10), WasherFillsContainers (on), DryerEmptiesOpenContainers (on), DryerNutritionPer5Min (2), WetnessPerLitre (500), SeepDirt (on by default: seepage also dirties clothing), SeepDirtPercent (5), BagsSour (on), SmellRadius (3), AutoEquipAtFull (on), BagDryPerHour (40), BagRainPerHour (100), BagSweatPerHour (100).
  - *Hot Spills:* HotSpillBurns, BurnChancePercent (25), BurnTimeMin (0.1), BurnTimeMax (2).
  - *Fizzy drinks:* FizzEnabled, FizzMaxLossPercent (60), FizzFullShakeSeconds (8), FizzFadeSeconds (5).
  - *Scent:* SpilledScent, ScentMultiplier, ScentSpilledFactor (2; from when the bag goes off), ScentEmptiedFactor (1; emptied bags and clothing), FoodScentPerPortion (6), LiquidScentPerLitre (3), ScentCapPerItem (8), ScentMaxTotal (24).
  - Not options (still in Config only): the item and container rule tables, spill step sizes, clothing order, hot threshold (1.6), worn drying factor, the washer and dryer speeds.

### Tooling (`docs/DontSpillTheBeans/tools/food-rules/`, generated HTML gitignored)
`build.py` makes `food-rules-<Key>.html` (spill / exempt / at-100% markup per food, with icons) and `build_containers.py` makes `containers-<Key>.html` (open /
sealed / sealed-when-full for fluid containers; protective / plain for bags) for Vanilla, VFE, Pomps, Sapph, MRE. The user saves a progress json; `export-lua.py`
and `export-containers.py` turn it into the compat modules. Re-run them (and re-mark new items) when a mod updates. The user's progress files live in that folder.

### Playtesting
`.\scripts\launch-playtest.ps1` starts the game with `-debug -cachedir=<repo>\playtest\Zomboid` (separate saves, mods, options, console.txt). The Workshop mods must be enabled
on the test save to appear. `.\scripts\tail-console.ps1 -Playtest DontSpillTheBeans` to watch. Right-click the ground > "DSTB (debug)" > "Give item" (grouped by case, each
labelled with the behaviour to expect, modded groups greyed when not installed) and the spill-rate multiplier. In debug, `reloadLuaFile("media/lua/shared/<file>")`
reloads a single file (config/compat files are safe; files that register events would duplicate handlers).
`launch-playtest.ps1` also links `scripts/playtest-mod/DSTBPlaytest` (a playtest-only helper mod, never shipped) and adds it plus Sapph's Cooking and MRE to the playtest
default mod list. It makes Patrick's Debug Scenario (a vanilla debug scenario: no zombies, repaired car and key beside you, on the Muldraugh highway) launch straight from
the main menu and sets up the vehicle test: worn pack with a mug and apple, mugs/apple in the trunk, a mug in the front passenger seat, a duffel with a mug in the trunk,
spill rate x10 and the vehicle probe on. Errors: `playtest/Zomboid/console.txt` (search "Don't Spill the Beans"); `tail-console.ps1 -Playtest` follows it.
**Multiplayer on one machine:** `.\scripts\launch-playtest-server.ps1` starts a local dedicated server (`playtest\Server`, isolated, no zombies, admin `admin` / `dstb`, `-Reset`
wipes its world); `.\scripts\launch-playtest.ps1 -Connect` starts the client (without Steam, matching the server) already pointed at 127.0.0.1. One client is enough to see a *remote* driver from the server's side
(two clients would need two Steam accounts); the in-menu Host option makes the host a local player, which is not the same thing. In the session, as admin: debug menu >
"Add test cargo to the nearest vehicle" and "Toggle vehicle probe"; server-side errors go to `playtest\Server\server-console.txt`.

### Hot spills
A spill step from an item hotter than `Config.HotAbove` (1.6 on the 0..3 item-heat scale; `Food:getHeat()` for food, `getItemHeat()` for fluid items) can scald the character (`BurnChance`, 25% per step). From the pockets it burns an upper leg at once. Inside a bag that lies against the body (worn, on a hotbar slot or loose in the pockets, directly or through nested bags: `bodyCarrier`) the spill does not burn at the moment it happens: that bag remembers the heat (`DSTB_hot`), and after `HotSeepAfterMinutes` (15 by default, like ordinary seepage) the hot liquid soaks through and gets one `BurnChance` roll on the upper torso (lower torso for fanny/belt packs), announced with "Ow! Something hot soaked through my X!". Emptying the bag forgets it. A bag loose in the pockets burns an upper leg; a worn bag or one on a hotbar slot, the torso. A bag held in a hand, and vehicle cargo, never burn. The burn is a vanilla body-part burn with a small strength (`BurnTimeMin`..`BurnTimeMax`, 0.1..2 by heat; vanilla fire burns are 50-100) so it heals sooner; it is set on the server and sent with `syncBodyPart`. The overhead note becomes "Ow! Something hot spilled in my X!". Sandbox `HotSpillBurns` turns it off. Bag tooltips show the live wetness percentage (computed when the card is drawn, since bags dry lazily). Debug builds log each hot spill and its seep roll. Debug menu: "Hot" group in "Give item".

### Scent (Starving Zombies integration)
Optional; needs Starving Zombies (Workshop 3396867685; ids `StarvingZombies` / `StarvingZombiesWIP`, `loadModAfter` in our mod.info). That mod keeps how far zombies smell the local player in `player:getModData().szSmell` (tiles), recomputed about once a second from **blood** only (not dirt) and stamped in `szUpdate`; its zombie logic only reads the local player, on the client controlling the zombie. `client/DSTB_Scent.lua` adds our scent to `szSmell` right after each of its recomputations. It has no concept of vehicles or parked objects, so only scent on the player counts: vehicle cargo never gives scent (a bag that took a spill keeps its own scent and counts when carried).

- Source: food spilled gives `FoodScentPerPortion` (6 tiles per portion lost); edible liquids (primary fluid Beverage or Alcoholic and not Water, Hazardous or Medical: milk, juice, soda, beer...) and drink-type foods give `LiquidScentPerLitre` (3 per litre). Water, tainted water, petrol, bleach and rubbing alcohol give none (they do make a bag go off, see "Souring": that is the smell of the bag to the character, not what zombies smell). Sandbox: `SpilledScent` (on/off) and `ScentMultiplier` (the scale, 0 = none).
- Storage: item ModData `DSTB_scent` (capped per item) with `DSTB_scentDirt`, the item's dirt when recorded; a bag gets it from spills inside it, the innermost worn garment from spills in the pockets. Scent only ever comes from our own spills; dirt from other sources (vanilla, other mods) never adds to it. The item's dirt is read only as a washed-or-not signal: effective base scent is stored scent x min(1, dirt now / peak dirt since recorded), where the peak (`DSTB_scentDirt`) is raised by the ten-minute pass whatever caused the dirt, so a half wash halves the smell even if it only removed other dirt, and extra dirt from elsewhere never adds scent. Scent is switched off entirely when the DirtyContainers option is off (nothing could wash it out). A ten-minute server pass settles the stored value to what is left. A bag carries a state: `fresh` while the spilled food/drink is still inside it (x1 until the contents go off, i.e. when seepage starts and `DSTB_sour` is set, the same moment as the Bad Smell moodle; from then x `ScentSpilledFactor`, 2; with `BagsSour` off, x2 from the spill), `emptied` after "Empty Spilled Contents" without washing (x `ScentEmptiedFactor`, 1: the same as clothing); only washing removes the rest. Pocket spills on clothing have no state (x1).
- Sum over the player's inventory (nested bags too), capped by `ScentMaxTotal`. Synced through the existing item mod-data sync, so it works in multiplayer. Debug menu: "Show my scent".

### Fizzy drinks
A carbonated drink (`Config.CarbonatedItems`, filled by the "Fizzy" flag of the container markup pages through `DSTB_Compat_<Key>_Containers.lua`; the obvious vanilla ones are seeded) that is drunk from while still full foams over if the character has exercised: part of the contents is lost on top of what they drink. The game has no separate "open" step for sealed cans and bottles (drinking is the opening), so the first drink from a full container is the trigger; `shared/DSTB_Fizz.lua` wraps `ISDrinkFluidAction:start` and `:serverStart` (server or single player only) and moves the action's start fill level down by what foamed so the drink still gets what was intended. The foam sprays over the character's clothes: the litres lost wet (at `WetnessPerLitre`) and, unless it is plain water, stain (at the liquid dirt rate per cl) the worn garments in the order of `Config.FizzOrder`: by body part, hands, arms, torso, head, legs, feet, outside in within each (socks before shoes). Gloves are the hands; long-sleeve tops (jackets, robes, sweaters, shirts) count as arms; vests, dresses, suits, short-sleeve tops and underwear tops as torso; hats, scarves, masks as head; pants then underwear as legs; socks then shoes as feet. The first garment takes what it can hold and the rest overflows to the next. Unlisted (modded) locations are placed by coverage. The shake is kept per player on the server from the reported on-foot motion (sprint 1/s, run 0.5/s, vault 1; never from driving, which only lets it fade) and fades with a half-life. Sandbox (section "Fizzy drinks"): FizzEnabled, FizzMaxLossPercent (60), FizzFullShakeSeconds (8), FizzFadeSeconds (5); config-only: FizzMinShake (0.1). The item card of a full carbonated drink says it foams over. Limits: only drinks that are fluid-container items; the gameplay numbers are unplaytested. Debug menu: a "Carbonated" give group and "Fizz: set my shake to full".

### Sounds
Source clips are in `assets/DontSpillTheBeans/` (24-bit stereo WAV: clips edited by the mod author from freesound.org; sources and licenses in `CREDITS.md`). `scripts/master-audio.py` trims, normalises and encodes them to `media/sound/DontSpillTheBeans/*.ogg` (plus `...M` muffled variants, a 600 Hz double low-pass) and writes `media/scripts/DontSpillTheBeans/DSTB_Sounds.txt` (sounds `DSTB_Burn`, `DSTB_DryWalk`, `DSTB_LiquidWalk`, `DSTB_WetWalk`, `DSTB_EmptyBase`, `DSTB_EmptyDry`, `DSTB_EmptyLiquid`, `DSTB_EmptyWet`, `DSTB_FoamOver`, each with an `M` twin). `dry_dump.wav` is unused. Rerun the script after changing any source clip (`--measure` prints the loudness numbers). The sound script parser only understands `/* */` comments; any other comment line before `module` breaks the whole file and every sound silently fails to exist (the generated header is a block comment for that reason).

Loudness: files are mastered to -23 LUFS (or as loud as -1 dBTP allows), and every clip's script `volume` brings it to its target in the game. Reference = Dynamic Gear Rattling, whose files are quiet and carry script volumes of 0.11 to 0.3, so its in-game levels (file loudness + script volume, tiled-clip LUFS) are: backpack rustle -35.5, clothes rustle -42.4, attached items -39.5, light rustle -49.1; `REF_LUFS` = -39. Burn and foam sounds are matched to -39 exactly (measured on the encoded files, within 0.3 dB); the emptying loops are 2 dB under it (`EMPTY_BELOW_REF`) and the walk sounds 4 dB under it at their loudest (`WALK_BELOW_REF`; full of spilled contents, running), as they are meant to sound like shuffling inside the bag; the muffled variants are 3 dB under their normal twins. (Both offsets were set by ear in the 2026-10-23 playtest: walk sounds were a little quiet and the emptying sounds a little loud at first.) The clip `volume` multiplies with the volume Lua passes.

Playback (`client/DSTB_Audio.lua`, local emitter only: never a world sound, so zombies cannot hear it):
- Walk sounds: while any carried bag (nested ones too) has `DSTB_spilled` (looked up through `DSTB.Carried`, only when a step is due), the cadence is Dynamic Gear Rattling's (ticks between sounds: walk 16, run 13.5, sprint 12.5, sneak 17, sneak+run 14.5, aiming from Nimble; skipped when still, in a vehicle, climbing, down) and so is the volume model (x1.25 run, x1.4 sprint, x0.75 sneak, x0.85 sneak+run and aiming; random 1-19% off; x(1 - zoom/6)). One sound per kind present: dry food (`DryWalk`), liquid (`LiquidWalk`), liquid-flagged food (`WetWalk`), each scaled by how much of that is in the bags: `0.25 + 0.75 x min(1, amount / full)` (`SoundFullFood` 1.5 portions, `SoundFullLiquid` 0.4 L, `SoundFullDrink` 1 portion). The amounts are kept on the bag (`DSTB_amtFood/Liquid/Drink`, added by the server when something spills in, cleared with the soiled flag when emptied or washed). Bags carried directly (worn, in a hand, hotbar, loose in the inventory) play the normal sounds; a spilled-in bag inside another bag plays the muffled variants (the same ones used for Hard of Hearing), each kind layered separately; the relay carries both sets (`food/liquid/drink` and `nfood/nliquid/ndrink`). Spills in the pockets make no sound. A bag soiled before the amounts existed counts as some dry food. All sounds are the same whatever bag or clothing is worn. Other players are heard too, as in Dynamic Gear Rattling: for every other online player within 10 tiles the client runs the same timer from their replicated movement state and plays the sounds at their position (`PlayWorldSoundImpl`, audio only, no noise for zombies). What their bags hold only the server can see, so it relays it: `soundState` (`id` = online id, `food`, `liquid`, `drink`) goes to everybody whenever a player's totals change (checked after each motion report and after an emptying), and a client that meets a player it has no state for asks (`soundRequest`, at most every 30 s) and is sent everybody's. All sounds layer: each kind present plays its own sound at the same moment.
- `EmptyBase` always plays through the Empty Spilled Contents action, and layered with it `EmptyDry` / `EmptyLiquid` / `EmptyWet` for each kind the bag held, all started with the action, faded in over 0.15 s, and faded out together when it ends (0.6 s; 0.15 s if it is interrupted or instant). They are loops (`loop = true` in the sound script, which the game honours for loose-file clips), so a long "empty duration" does not run out of sound; as a failsafe they fade out by themselves 3 s after the action should have ended. A sound that has already finished is not touched (its emitter may already be in use by another sound). `master-audio.py` makes the loops (`make_loop`): it searches each source for the stretch of 3 s or more whose two ends match best in level and spectrum (and are not lulls), takes that as the body and crossfades (equal power, 0.25 s) its last part into the material just before its start, so the wrap continues exactly as the clip does. `empty_base` and `empty_dry` turned out to repeat themselves exactly (ends differ by 0.0 dB), `empty_liquid` and `empty_wet` match within about 2 dB in spectrum. The intros and tails of the sources are therefore not used; the muffled variants are filtered round the loop (three copies, the middle kept) so their seam stays clean.
- `Burn` when a hot spill burns (pockets: the `burn` flag of a spill event; worn bag: the `scalded` message). `FoamOver` with the "It foamed over!" text.
- Hearing: the game's Deaf / Hard of Hearing filters are FMOD *event* parameters, which sounds made of loose files (played as raw channels) never receive, so they are done here: Deaf plays nothing; Hard of Hearing plays the muffled variants. Dynamic Gear Rattling only skips its sounds for Deaf, and ignores Hard of Hearing. This is an approximation of the vanilla filter, whose exact curve is inside the sound bank. Low health does not muffle sound in vanilla: no sound bank uses a `PlayerHealth` parameter (the Java one is only read by the music threat code and is nearly constant), so it is deliberately not done here.
- Options (Options > Mods > Don't Spill the Beans, shared page in `DSTB_Options`): master, walk and event volume sliders; the inventory tint tick box.
- Debug menu: "Sounds" previews each one-shot and soils the worn bag with chosen amounts (`debugSoil`).

**Credits for the Workshop page:** the walk-sound timing and volume model are taken from Dynamic Gear Rattling (Workshop 3808152720), and its sounds were the loudness reference.

### Holding "At 100%" items
`client/DSTB_AutoEquip.lua` wraps `ISInventoryPaneContextMenu.onDrinkFluid` and `eatItem`: when a still-whole "At 100%" item (`Spill.isAtFull`: a full sealed-when-full container, or an uneaten food exempt only while uneaten, with the "At 100%" rules on) is eaten or drunk only in part (not "all", not an opening recipe), it is first equipped (`equipWeapon`: a free hand, else it replaces the primary hand item; two-handed items empty both) and vanilla's transfer to the main inventory and "return it to its container" step are skipped for it, so it stays in the hand, where nothing spills. Sandbox `AutoEquipAtFull` (on); off = vanilla (it goes back into the bag). Items that always spill are not touched.

### Seepage down the body
While a bag the player carries is spilled in (and until it is emptied), it seeps wherever it is carried; the time is counted every ten minutes. Worn, on a hotbar slot (it hangs on the body, so it counts as worn) or loose in the pockets (`touchesClothing`) it wets, and with `SeepDirt` (on by default) dirties, the clothing under it; held in a hand it leaks outside the clothes and affects none (but still counts as seeping, so what spilled in it goes off). Every ten minutes after `SeepAfterMinutes` the garments under it are soaked in the seepage order (legs, feet, torso, arms, head; `Config.ClothingOrder`): the first gets the full amount (`SeepWetPerStep`, scaled by the bag's wetness; `SeepDirtPerStep` with seepage dirt on), and each next one gets `SeepInherit` (60%, sandbox `SeepInheritPercent`) of what the one before it got, whether or not that one could hold it. So the trickle reaches the socks and shoes, instead of waiting for everything before them to be full. The fraction handed on scales with severity (`handedOn`): `SeepInherit x bag wetness` (dirt: x bag dirt), so a bag at 40% wetness hands on 24% (75*0.7 = 52, then 12, 3, <1: two garments) while a soaked one hands on 60% (75, 45, 27, 16, 10, 6, 3.5, 2: seven or eight, shoes included). A handed-on amount under 1 wetness (0.01 dirt) ends the trickle.

Foam (`foamOnClothing`) uses the same rule with `FoamInherit` (60%) scaled by how soaked the first garment gets (litres x `WetnessPerLitre` / 100): 0.1 L is 50 wetness at 30% (50, 15, 4.5, 1.4), 0.2 L or more is 60% (100, 60, 36, 22, 13, 8, 5...). Bag cards show "Dirt: N%" (the engine draws only decals for bags).

### Seepage into the carrying bag
A spilled-in bag inside another carried bag (`seepIntoCarrier` in `Spill.seep`) seeps into the bag carrying it, on the same ten-minute tick and after the same `SeepAfterMinutes`: the carrier gets wet at the seepage rate (`SeepWetPerStep` scaled by the inner bag's wetness, if it is wet enough) and dirty (`SeepDirtPerStep`, only with seepage dirt on and a dirty enough inner bag, and only if the carrier can hold dirt). The carrier is not marked as spilled in, so it never seeps onwards. A protective carrier takes nothing. Hot spills do not travel this way.

### Bags that cannot get dirty
Only 39 of the 308 vanilla bag items have a `BloodLocation` (schoolbag, hiking bags, ALICE pack...). The rest (the duffel bag, toolboxes, cases, totes...) cannot hold engine dirt (`ItemVisual` dirt is kept per covered body part), so spills never dirty them: that vanilla behaviour is respected and the mod keeps no dirt value of its own. Wetness is the mod's own and works on every bag.

### Liquid foods
`Config.LiquidFoods` (the "Liquid" flag of the food markup pages through `DSTB_Compat_<Key>.lua`) marks tea, coffee, soups, stews and the like: they spill at the liquid rates but stain at the food dirt amount, say "Spills" on the item card, and wet what they spill on as well as stain it, at a volume estimated from the food (its larger hunger or thirst value over `ThirstPerLitre` = 50, water's own thirst per litre: a mug of tea 0.4 L, a bowl of soup 0.3 L; `DrinkLitres` 0.25 L if it has neither). Soups and other foods with a hunger value still smell like food. Nothing is guessed from the item; the pages only suggest (a blue underline) foods that leave an open vessel behind or have a liquidy name.

### Stumbles and falls
Entering the `bumped`, `falldown`, `falling` or `knockeddown` animation state counts as one event (`DSTB_Motion.lua`), at most once per 3 s so one tumble is not counted twice. It is reported with the vaults (`vaults` in the motion report, same server-side clamp) and spills the vault amount, so a fall is exactly like climbing a fence: there is no separate switch. The two sandbox options are labelled "Climbing or falling" (`VaultSpillLiquid/Food`) and their tooltips list the ways it comes into play (climbing, vaulting, tripping, being bumped or knocked down, falling). It also adds to a drink's fizz shake, like a vault does.

### Traits
`DSTB.traitFactor(player)`: Graceful x(1 - `GracefulReducePercent`, 50%), Clumsy x(1 + `ClumsyIncreasePercent`, 40%); both multiply. Applied to the amount lost to spilling on foot (`Spill.apply`) and to the amount a drink foams away (`Fizz`), wherever the character is: the foam of a drink opened in a car is the same as one opened outside for the same shake, and the driving traits have nothing to do with foam.

`DSTB.drivingFactor(driver)`: Speed Demon x(1 - `SpeedDemonReducePercent`, 25%), Sunday Driver x(1 + `SundayDriverIncreasePercent`, 33%). Applied in `Spill.vehicleTick` to everything that vehicle spills, using the vehicle's *driver*: loose cargo, what the driver carries and what every passenger carries (the passengers' own traits do not matter for this). No driver, or a towed vehicle: 1. Graceful / Clumsy do not apply to vehicle spills. Neither pair touches seepage, burns or scent. The defaults are chosen so that the pairs balance: Graceful x0.5 is worth twice Clumsy's x1.4 in log terms (the game charges 4 points for Graceful and refunds 2 for Clumsy), and Speed Demon x0.75 is the exact mirror of Sunday Driver x1.33 (+1 / -1 points).

### Souring
A bag with **anything but water** spilled in it (food, liquid food, and every other liquid: fuel, milk, juice, bleach...) goes off **when its seepage starts** (`Wet.goOff`, called from `Spill.seep` once the bag has seeped for `SeepAfterMinutes` / `HotSeepAfterMinutes` and, for a bag inside another bag, from `seepIntoCarrier`): `DSTB_sour` in its ModData, cleared by `clearSoiled` (emptying or washing). What went in is known from the spill: food and drinks leave amounts (`DSTB_amtFood/Drink`), and a liquid that is not water-only (`isWaterOnlySource()`) sets `DSTB_smelly`; a bag with only water in it never goes off. Seepage happens wherever the bag is carried, so it goes off worn, on a hotbar slot, in a hand or loose in the pockets alike; a bag in a protective container does not seep at all (`seepIntoCarrier` skips it), so it does not go off while shut in. Carrying such a bag **in the open** (worn, hotbar, in a hand or loose in the main inventory) gives the **Bad Smell** level of the NoxiousSmell moodle and never more (`DSTB_Smell.lua`). A bag that went off inside another bag does not smell while it is shut in (only directly carried bags are counted) and does as soon as it is taken out. Emptying the bag removes the smell once the action completes (the server clears the flag, the client's one-second cache is cleared with it). Lua has no setter for a moodle, and the game recomputes it every update from `getCorpseSicknessRate()`, so the rate is set to `SourSmellRate` (0.0005, above 0 and under the 0.001 of the next level) on every player update and tick, only when the real rate is 0, so corpses win. That rate is a display value only: the sickness stat is added from a separate local, so it makes nobody ill. The moodle does not show if the "decaying corpse health impact" sandbox option is None. Whether the rate survives until the moodle's own update (order within a frame is not visible in the Java) is to be checked in game. A gone-off bag **lying on a tile** (a world item on the ground, not one shut in a container there) gives the same moodle to a player within sandbox `SmellRadius` tiles (0 to 12, default 3, 0 = off) on the same floor: `DSTB_Smell.lua` scans the squares in that radius at most once a second per player, looking at each world object's `DSTB_sour`. Whether a bag dropped by another player carries its ModData to this client is to be checked in multiplayer. Sandbox `BagsSour`. The item card says it has gone off. Debug menu: "Make the spilled contents of my bag go off".

### Inventory tint
Rows of bags with something spilled in them are tinted yellow-green, a murkier, sicklier olive once they have gone off (both at 0.13 opacity) (`DSTB_Tint.lua`). The pane draws its rows in one function with no per-item hook, so `ISInventoryPane.renderdetails` is wrapped and, after it, the pane's own row list is read: `self.items` has one entry per drawn row, in order (the item, or for the first row of a stack the stack, whose `items[1]` is the item), and row i is drawn at `(i - 1) * itemHgt + headerHgt`. That list is what the pane itself uses to know which item is under the mouse, so the tint lands on the right row for any layout. The first version replayed vanilla's row walk and, worse, wrapped the function while the mod loaded: Better Containers (42.21) replaces `renderdetails` outright while loading, after this mod, which discarded the wrapper (no tint at all). The wrapper is therefore installed on `Events.OnGameStart`, after every mod has loaded. Mod Options tick box "Tint spilled-in bags green in the inventory" (client setting, on).

### Carried-bag cache
The local player's bags (nested ones too) are scanned by `DSTB.Carried.get` (`DSTB_Carried.lua`), at most once a second, and again at once after `Carried.invalidate()`, which the client calls when the server reports a spill and when an emptying completes. The shuffling sounds only ask when a step is actually due (a few times a second while moving), and take the volumes from what the bags hold at that step, so each spill is heard from the next step on. The smell reads the same cache. Remote players' sounds use the state the server relays and need no scan. The server's own scan for the relay runs once per motion report.

### Possible later
- **Skills:** Nimble or Fitness reducing the spill rate, Heavy Load or Panic raising it. Not planned for now.
- **Resealing:** an action to close a container with a lid or cap, or wrap food, to make it safe. Not planned for now; a possible future addition.

### Known gaps
- Spill time uses real seconds, not game speed; server-side locomotion is client-reported (clamped by the time budget).
- Written but not yet played: stumble spills, the traits, souring (in particular whether the Bad Smell moodle holds steady each frame), the inventory tint, bag seepage for pocket and hand-held bags, the Starving Zombies scent, and all of the above in multiplayer. Hot-spill burn numbers need tuning (defaults 25% chance, strength up to 2).
- The tint relies on the pane keeping `self.items` in row order (vanilla and Better Containers do); a mod that replaces `renderdetails` after game start would drop it (it can be switched off in Mod Options).
- Skill-based tuning (Nimble, Fitness, Heavy Load, Panic) and resealing are ideas only (see "Possible later").
- Vehicle speed bands are client-reported (clamped by the time budget, and only counted while the server sees the player in a vehicle).
- Items from mod updates fall back to default rules until re-marked.
- Wet-variant swapping and washer behaviour for modded clothing are untested. Modded items that have a wet counterpart (like vanilla towels) are not detected: the game does not expose an item's dry/wet pair to Lua, so only `Config.WetVariants` entries swap and anything else is treated as an item that cannot get wet (a deliberate choice: few popular mods add such items).
- Translations exist in English only.
