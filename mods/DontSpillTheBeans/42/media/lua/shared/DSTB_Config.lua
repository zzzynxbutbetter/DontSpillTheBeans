-- Tunables and classification tables shared by client and server.
-- Other mods can extend the tables at load time, e.g.
--   DontSpillTheBeans.Config.OpenContainerNames["MyCupName"] = true

DontSpillTheBeans = DontSpillTheBeans or {}
local DSTB = DontSpillTheBeans

DSTB.MODULE = "DontSpillTheBeans"

DSTB.Config = {
    -- FluidContainer ContainerName values (from item scripts) that are open to the air.
    -- Bottles, cans, cartons, canteens, jerrycans and lidded jars are deliberately absent.
    OpenContainerNames = {
        Mug = true, Teacup = true, CupPlastic = true, Glass = true, Bowl = true, Dish = true,
        Goblet = true, Goblet_Wood = true, Goblet_Silver = true, Goblet_Gold = true,
        Silver_Cup = true, Gold_Cup = true, Copper_Cup = true, Metal_Cup = true,
        Pot = true, Saucepan = true, Bucket = true, ["Large Bucket"] = true,
    },

    -- Per-item overrides of the container-name rule above, filled in by the generated DSTB_Compat_*_Containers
    -- files (see docs/DontSpillTheBeans/tools/food-rules). Keys are item full types. Precedence in openKind:
    -- SealedFluidItems > SealedWhenFull > OpenFluidItems > OpenContainerNames.
    OpenFluidItems = {},       -- always open: spills whenever it holds something
    SealedFluidItems = {},     -- sealed/closed: never spills

    -- Items whose contents are shielded: an open container of LIQUID nested inside one of these never spills.
    -- (Food is shielded by ANY nested container, see Spill.scan; these also shield liquids.) Filled in by the generated
    -- DSTB_Compat_*_Containers files, like the other per-item tables.
    ProtectiveContainers = {},

    -- Percent of a container's full amount lost per spill, by locomotion state and by kind: liquids (and drinks such as tea)
    -- spill more easily than food. One spill happens every SpillIntervalSeconds of that activity. These are the defaults
    -- of the sandbox options of the same names.
    SpillIntervalSeconds = 3,
    FootPercent = {
        liquid = { sneak = 10, walk = 15, run = 25, sprint = 40 },
        food = { sneak = 5, walk = 10, run = 12, sprint = 15 },
    },
    VaultPercent = { liquid = 75, food = 25 },   -- lost in one vault (fence / window / wall climb)

    -- Vehicles (the driver's seat/trunk/glovebox contents, and whatever the player carries while riding) spill from
    -- speed alone. Bands are upper km/h limits: below the first = parked/idle, then crawl, city, road, highway.
    VehicleBandsKmh = { 3, 15, 45, 80 },
    VehiclePercent = {
        liquid = { crawl = 5, city = 10, road = 25, highway = 40 },
        food = { crawl = 0, city = 2, road = 5, highway = 15 },
    },

    -- Spill is applied in discrete steps so item syncs/dirt happen per event, not per tick.
    SpillStepLitres = 0.01,
    ColdFluidBelowHeat = 1.0,  -- liquids do not freeze, so a fluid item colder than this item heat counts as frozen and
                               -- cannot spill. 1.0 = any cold item, the ones the inventory shades blue (fridge/freezer
                               -- floor is 0.2). Set to 0 to turn the rule off.
    SpillStepFood = 0.05,      -- fraction of a full portion lost per food spill step
    DrinkLitres = 0.25,        -- volume assumed for a liquid-flagged Food whose script has no hunger or thirst value to estimate it from
    ThirstPerLitre = 50,       -- water's own ThirstChange per litre; a liquid Food's whole portion is taken as its larger hunger or thirst value over this
    DirtPerStep = 0.025,
    FoodDirtPerStep = 0.10,    -- loose food is messier than a liquid: dirt added to the bag per food spill step
    WetnessPerLitre = 500,     -- clothing wetness (0..100) added per litre spilled onto it
    BagDryPerHour = 40,        -- bag wetness (0..100) lost per in-game hour while carried (vanilla loose clothing does 20)
    WornDryFactor = 0.5,       -- a worn bag dries at this fraction of that: worn clothing dries slowly in vanilla (body layers, no air)

    -- Environmental wetting of worn bags, per signal-hour (signal 0..1 as in vanilla: rain intensity, sweat).
    BagRainPerHour = 100,
    BagSweatPerHour = 100,

    -- Washing machine: bags inside get cleaned (dirt per in-game minute, 0..1 scale) and soaked, and so does
    -- everything inside them.
    WasherBagDirtPerMinute = 0.02,
    DryerNutritionPer5Min = 2.0, -- nutrition points (script units: a bowl of soup is 15) a dryer takes out of a pure drink every 5 minutes, scaled by how liquid the food is (thirst share); a cycle is 90 minutes

    -- Items with a vanilla wet state other than Clothing wetness: dry item -> its wet counterpart.
    -- (Vanilla only has towels and dish cloths; extend for modded items.)
    WetVariants = {
        ["Base.BathTowel"] = "Base.BathTowelWet",
        ["Base.DishCloth"] = "Base.DishClothWet",
    },

    -- A spilled-in bag worn long enough seeps into the clothing under it. Order (lowest first): by body part, legs, feet,
    -- torso, arms, head; within each outside in, except that socks come before shoes. Keys are body location ids
    -- without the "base:" prefix, lowercase. Locations not listed (e.g. modded ones) are ranked from the body parts the
    -- garment covers, see wornLayers in DSTB_Spill.lua.
    ClothingOrder = {
        -- legs
        pantsextra = 10,
        pants = 11, pants_skinny = 11, shortpants = 11, shortsshort = 11, skirt = 11, longskirt = 11, legs1 = 11, legs5 = 11,
        underwear = 12, underwearbottom = 12,
        -- feet
        socks = 20, shoes = 21,
        -- torso
        torsoextra = 30, torsoextravest = 30, torsoextravestbullet = 30, cuirass = 30,
        jacket = 31, jacket_bulky = 31, jacket_down = 31, jackethat = 31, jackethat_bulky = 31, jacketsuit = 31, bathrobe = 31, fullrobe = 31,
        sweater = 32, sweaterhat = 32, jersey = 32,
        shirt = 33, fulltop = 33,
        dress = 34, longdress = 34, torso1legs1 = 34, fullsuit = 34, fullsuithead = 34, fullsuithead_scba = 34, boilersuit = 34, bodycostume = 34,
        shortsleeveshirt = 35, tshirt = 35, torso1 = 35,
        tanktop = 36,
        underweartop = 37, underwearextra1 = 38, underwearextra2 = 38,
        -- arms
        hands = 50, handsleft = 50, handsright = 50,
        -- head
        hat = 60, fullhat = 60, scarf = 61, neck = 61, mask = 62, maskfull = 62, maskeyes = 63, eyes = 63,
    },
    SeepAfterMinutes = 15,     -- worn minutes with spilled contents inside before it starts seeping
    SeepMinWet = 25,           -- bag wetness needed to wet clothing (vanilla's "Wet" threshold)
    SeepMinDirt = 0.5,         -- bag dirt (0..1) needed to dirty clothing
    SeepWetPerStep = 75,       -- clothing wetness (0..100) the first garment in the order gets per 10 in-game minutes at full
                               -- bag wetness (scaled down to 50% for a barely wet bag). Must clearly outpace vanilla drying of
                               -- worn clothing, otherwise even the first layers do not stay wet.
    SeepInherit = 0.6,         -- the most each next garment down the body gets of what the one before it got (wetness and dirt),
                               -- reached by a fully soaked bag; a barely wet one hands on far less (see handedOn in DSTB_Spill.lua)
    FoamInherit = 0.6,         -- the same for foam from a carbonated drink, reached when the foam soaks the first garment through
    SeepDirtPerStep = 0.05,    -- clothing dirt (0..1) added per 10 in-game minutes of seeping, when the sandbox option is on
    ContentsDirtPerStep = 0.10, -- dirt (0..1) added per 10 in-game minutes to what is loose in a spilled-in bag
    ContentsWetPerStep = 1000, -- wetness (0..100) passed per 10 in-game minutes to what is loose in a spilled-in bag (1000 = at once)

    -- Hot spills: a hot liquid or food (item heat above HotAbove, vanilla's "hot" mark for cooking is 1.6, the maximum
    -- is 3) spilling out of something the character wears or carries in their pockets can scald the skin under it.
    HotAbove = 1.6,
    BurnChance = 0.25,         -- chance that a hot spill scalds: per spill step for pockets (it lands straight on the
                               -- clothing), once per hot spill for a worn bag (when it seeps through, see below)
    HotSeepAfterMinutes = 15,  -- a hot spill in a worn bag soaks through to the body after this long, instead of SeepAfterMinutes
    BurnTimeMin = 0.1,           -- burn strength (BodyPart burn time) at HotAbove ...
    BurnTimeMax = 2,          -- ... and at the maximum heat. Vanilla fire burns are 50-100, so these heal far sooner.

    -- Fizzy drinks: a carbonated drink (Config.CarbonatedItems) that is opened (first drunk from, full) after the
    -- character has exercised foams over and loses part of its contents. "Shake" builds up from sprinting, running and
    -- vaulting (never from driving) and fades with a half-life.
    FizzMaxLoss = 0.60,        -- share of the contents lost when the shake is full
    FizzFullShakeSeconds = 8,  -- seconds of sprinting (running counts half, a vault counts one second) for a full shake
    FizzFadeSeconds = 5,       -- half-life of the shake, in real seconds
    FizzMinShake = 0.1,        -- below this fraction of a full shake nothing foams over

    -- Foam from a carbonated drink sprays over the clothes in this order (lowest first): by body part, hands, arms,
    -- torso, head, legs, feet; within each outside in, except that socks come before shoes. Long-sleeve tops count as arms
    -- (they cover them), tops that only cover the torso, dresses and suits as torso. Keys are body location ids without
    -- the "base:" prefix, lowercase; locations not listed (modded) are placed by the body parts the garment covers.
    FizzOrder = {
        -- hands
        hands = 1, handsleft = 1, handsright = 1,
        -- arms
        jacket = 2.1, jacket_bulky = 2.1, jacket_down = 2.1, jackethat = 2.1, jackethat_bulky = 2.1, jacketsuit = 2.1, bathrobe = 2.1, fullrobe = 2.1,
        sweater = 2.2, sweaterhat = 2.2, jersey = 2.2,
        shirt = 2.3, fulltop = 2.3,
        -- torso
        torsoextra = 3.1, torsoextravest = 3.1, torsoextravestbullet = 3.1, cuirass = 3.1,
        dress = 3.2, longdress = 3.2, torso1legs1 = 3.2, fullsuit = 3.2, fullsuithead = 3.2, fullsuithead_scba = 3.2, boilersuit = 3.2, bodycostume = 3.2,
        shortsleeveshirt = 3.3, tshirt = 3.3, torso1 = 3.3,
        tanktop = 3.4,
        underweartop = 3.5, underwearextra1 = 3.6, underwearextra2 = 3.6,
        -- head
        hat = 4.1, fullhat = 4.1, scarf = 4.2, neck = 4.2, mask = 4.3, maskfull = 4.3, maskeyes = 4.4, eyes = 4.4,
        -- legs
        pantsextra = 5.1,
        pants = 5.2, pants_skinny = 5.2, shortpants = 5.2, shortsshort = 5.2, skirt = 5.2, longskirt = 5.2, legs1 = 5.2, legs5 = 5.2,
        underwear = 5.3, underwearbottom = 5.3,
        -- feet
        socks = 6.1, shoes = 6.2,
    },

    -- Scent (needs the Starving Zombies mod, Workshop 3396867685): spilled food and edible drinks leave a smell on
    -- the bag or garment they soaked into, which adds to how far zombies smell the player. Like the mod's own blood
    -- smell it lasts until washed out: it follows the item's dirt. Distances are in tiles.
    FoodScentPerPortion = 6,   -- per whole portion of food lost
    LiquidScentPerLitre = 3,    -- per litre of an edible liquid lost (milk, juice, soda, alcohol; not water or fuel)
    ScentCapPerItem = 8,        -- most scent one bag or garment holds
    ScentSpilledFactor = 2,     -- a bag with spilled food/drink still inside smells this many times stronger ...
    ScentEmptiedFactor = 1,     -- ... and once that has been emptied out (but the stain not washed) this many times (1 = as clothing)
    ScentMaxTotal = 24,         -- most scent added to the player in all

    -- Sounds (client only, see DSTB_Audio.lua). A bag with this much spilled in it (portions of food, litres of liquid,
    -- portions of liquid food) makes its walking sound at full volume; less is quieter, down to SoundMinFactor.
    SoundFullFood = 1.5,
    SoundFullLiquid = 0.4,
    SoundFullDrink = 1.0,
    SoundMinFactor = 0.25,

    -- Traits: the share of what is lost to spilling and foaming over that a Graceful character avoids, and the extra a
    -- Clumsy one loses (sandbox: percent). Both traits at once multiply.
    GracefulReduce = 0.5,   -- x0.5; Clumsy's x1.4 is its mirror image in log terms at half the strength, as the trait costs say
    ClumsyIncrease = 0.4,

    -- Driving traits: the share of what is lost to spilling and foaming over that a Speed Demon driver avoids, and the
    -- extra a Sunday Driver loses (sandbox: percent). They replace Graceful / Clumsy while driving.
    SpeedDemonReduce = 0.25,    -- x0.75; Sunday Driver's x1.33 is its exact mirror image (the two cost +1 / -1)
    SundayDriverIncrease = 0.33,

    -- Souring: a bag with anything but water spilled in it (food, liquid food, fuel, milk...) goes off when its seepage starts, and gives whoever carries it
    -- the "Bad Smell" level of the NoxiousSmell moodle (never more) while it is carried in the open, i.e. not shut in
    -- another bag, until it is emptied or washed. SourSmellRate is the corpse-sickness rate that moodle reads: anything
    -- above 0 and up to 0.001 is its lowest level.
    SourSmellRate = 0.0005,
    -- A bag that has gone off also gives the moodle while it lies on the ground (or any tile) within this many tiles of the player.
    SmellRadius = 3,

    -- Client -> server motion report limits (server-side validation).
    ReportIntervalSec = 2.0,
    MaxReportSec = 10.0,
    MaxVaultsPerReport = 3,
}

-- Tunables the sandbox options can override. Everything else in DSTB.Config is the default used when an option is
-- missing (an older save) or for values not offered as options.
local PERCENT = {
    FizzMaxLoss = "FizzMaxLossPercent", BurnChance = "BurnChancePercent", DirtPerStep = "DirtLiquidPercent",
    FoodDirtPerStep = "DirtFoodPercent", SeepDirtPerStep = "SeepDirtPercent", SeepInherit = "SeepInheritPercent", FoamInherit = "FoamInheritPercent",
    GracefulReduce = "GracefulReducePercent", ClumsyIncrease = "ClumsyIncreasePercent",
    SpeedDemonReduce = "SpeedDemonReducePercent", SundayDriverIncrease = "SundayDriverIncreasePercent",
    SeepMinDirt = "SeepMinDirtPercent", ContentsDirtPerStep = "ContentsDirtPercent",
}
local PLAIN = {
    DryerNutritionPer5Min = true, SeepAfterMinutes = true, HotSeepAfterMinutes = true, SeepWetPerStep = true, BagDryPerHour = true, BagRainPerHour = true,
    BagSweatPerHour = true, BurnTimeMin = true, BurnTimeMax = true, FoodScentPerPortion = true, LiquidScentPerLitre = true,
    ScentCapPerItem = true, ScentMaxTotal = true, WetnessPerLitre = true, SeepMinWet = true, ContentsWetPerStep = true,
    ScentSpilledFactor = true, SmellRadius = true, ScentEmptiedFactor = true, FizzFullShakeSeconds = true, FizzFadeSeconds = true,
}

function DSTB.getSandbox()
    return SandboxVars and SandboxVars.DontSpillTheBeans or nil
end

-- A tunable's current value: the sandbox option if set, otherwise the default in DSTB.Config.
function DSTB.value(key)
    local sv = DSTB.getSandbox()
    if sv then
        local option = PERCENT[key]
        if option then
            local v = tonumber(sv[option])
            if v then return v / 100 end
        elseif PLAIN[key] then
            local v = tonumber(sv[key])
            if v then return v end
        end
    end
    return DSTB.Config[key]
end

-- Seconds between spills while moving: the per-spill percentages are lost once per this long.
function DSTB.spillInterval()
    local sv = DSTB.getSandbox()
    local v = sv and tonumber(sv.SpillIntervalSeconds) or DSTB.Config.SpillIntervalSeconds
    return math.max(1, v)
end

local function cap(word) return word:sub(1, 1):upper() .. word:sub(2) end

-- Fraction of a container's full amount lost per second on foot ("sneak", "walk", "run", "sprint") or in a vehicle band
-- ("crawl", "city", "road", "highway"), for kind "liquid" or "food". The options are percent lost per spill, one spill
-- every spillInterval() seconds; a drink counts as a liquid.
local function perSecond(prefix, key, kind, default)
    local sv = DSTB.getSandbox()
    kind = kind == "food" and "food" or "liquid"
    local v = sv and tonumber(sv[prefix .. cap(key) .. cap(kind)])
    if v == nil then v = default[kind][key] end
    return v / 100 / DSTB.spillInterval()
end

function DSTB.footRate(state, kind) return perSecond("FootRate", state, kind, DSTB.Config.FootPercent) end

function DSTB.vehicleRate(band, kind) return perSecond("VehicleRate", band, kind, DSTB.Config.VehiclePercent) end

-- Fraction of a container's full amount lost in one vault.
function DSTB.vaultSpill(kind)
    local sv = DSTB.getSandbox()
    kind = kind == "food" and "food" or "liquid"
    local v = sv and tonumber(sv["VaultSpill" .. cap(kind)])
    if v == nil then v = DSTB.Config.VaultPercent[kind] end
    return v / 100
end

-- Upper speed limits (km/h) of the idle, crawl, town and road vehicle bands, in order.
function DSTB.vehicleBandLimits()
    local sv = DSTB.getSandbox()
    local limits = {}
    for i, name in ipairs({ "VehicleSpeedIdle", "VehicleSpeedCrawl", "VehicleSpeedCity", "VehicleSpeedRoad" }) do
        limits[i] = sv and tonumber(sv[name]) or DSTB.Config.VehicleBandsKmh[i]
    end
    table.sort(limits)
    return limits
end

function DSTB.isEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.Enabled ~= false
end

-- Global scale on all spill, set by the debug tools only (SP only); there is no sandbox option for it.
function DSTB.rateMultiplier()
    return DSTB.debugMultiplier or 1.0
end

-- Whether vehicle speed makes things spill at all, and whether a vehicle being towed counts.
function DSTB.vehicleSpillEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.VehicleSpills ~= false
end

function DSTB.towedSpillEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.TowedVehicleSpills ~= false
end

-- How far (tiles) from the nearest player a vehicle with nobody in it still spills its cargo while it rolls; 0 = never.
function DSTB.unattendedRange()
    local sv = DSTB.getSandbox()
    local r = sv and tonumber(sv.UnattendedVehicleRange)
    if r == nil then r = 60 end
    return math.max(0, r)
end

-- Whether hot spills can burn the character.
function DSTB.hotBurnsEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.HotSpillBurns ~= false
end

-- Scale on the scent spills give off (0 = none). Only does anything with Starving Zombies running.
function DSTB.scentMultiplier()
    local sv = DSTB.getSandbox()
    local m = sv and tonumber(sv.ScentMultiplier)
    if m == nil then m = 1 end
    return math.max(0, m)
end

-- The game's activated mod ids, for the optional Starving Zombies integration (the release and the WIP build).
function DSTB.scentEnabled()
    local sv = DSTB.getSandbox()
    if sv and sv.SpilledScent == false then return false end
    if not DSTB.dirtyEnabled() then return false end   -- the smell is washed out with the dirt, so it needs the dirt
    if DSTB.scentMultiplier() <= 0 then return false end
    if DSTB.scentModActive == nil then   -- the mod list cannot change while the game runs
        local mods = getActivatedMods()
        DSTB.scentModActive = mods ~= nil and (mods:contains("StarvingZombies") or mods:contains("StarvingZombiesWIP"))
    end
    return DSTB.scentModActive
end

-- Whether a seeping worn bag also dirties the clothing under it (off by default: seepage only wets).
function DSTB.seepDirtEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.SeepDirt ~= false
end

-- Whether a cold liquid (item heat below Config.ColdFluidBelowHeat) counts as frozen and cannot spill.
function DSTB.coldLiquidsSafe()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.ColdLiquidsSafe ~= false
end

-- Whether rain and sweat wet worn bags (spills wetting them is the separate WetClothing option).
function DSTB.washerFillsEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.WasherFillsContainers ~= false
end

function DSTB.dryerEmptiesEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.DryerEmptiesOpenContainers ~= false
end

function DSTB.envWetEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.RainSweatWetsBags ~= false
end

-- Whether carbonated drinks foam over when opened after exercise.
function DSTB.fizzEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.FizzEnabled ~= false
end

function DSTB.dirtyEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.DirtyContainers ~= false
end

-- Whether food carried loose in the character's own pockets (no bag) spills too.
function DSTB.foodInPocketsEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.FoodSpillsInPockets ~= false
end

function DSTB.foodSpillEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.FoodSpillage ~= false
end

-- How the "At 100%" foods are treated: "sealed" = always exempt (as if opened packaging stayed sealed),
-- "whole" = exempt only while uneaten, "off" = no exemption (they spill like any other food).
function DSTB.atFullMode()
    local sv = DSTB.getSandbox()
    if sv and sv.AtFullAsSealed == true then return "sealed" end
    if sv and sv.AtFullRules == false then return "off" end
    return "whole"
end

-- Whether eating or drinking part of a still-whole "At 100%" item takes it into the hands first.
function DSTB.autoEquipEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.AutoEquipAtFull ~= false
end

-- Whether bags with food spilled in them go off after a while and make their carrier smell.
function DSTB.sourEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.BagsSour ~= false
end

-- Multiplier on what a driver loses to spilling and foaming over: Speed Demons lose less, Sunday Drivers more. `driver`
-- may be nil or not a player (no driver, a zombie...): 1.
function DSTB.drivingFactor(driver)
    if not driver or not instanceof(driver, "IsoPlayer") then return 1 end
    local factor = 1
    if driver:hasTrait(CharacterTrait.SPEED_DEMON) then factor = factor * (1 - DSTB.value("SpeedDemonReduce")) end
    if driver:hasTrait(CharacterTrait.SUNDAY_DRIVER) then factor = factor * (1 + DSTB.value("SundayDriverIncrease")) end
    return math.max(0, factor)
end

-- Multiplier on what a character loses to spilling and foaming over: Graceful lose less, Clumsy more.
function DSTB.traitFactor(player)
    local factor = 1
    if player:hasTrait(CharacterTrait.GRACEFUL) then factor = factor * (1 - DSTB.value("GracefulReduce")) end
    if player:hasTrait(CharacterTrait.CLUMSY) then factor = factor * (1 + DSTB.value("ClumsyIncrease")) end
    return math.max(0, factor)
end

-- Seconds the "Empty Spilled Contents" action takes (the unequip/re-equip around it is extra).
function DSTB.emptySeconds()
    local sv = DSTB.getSandbox()
    local s = sv and tonumber(sv.EmptyDurationSeconds) or 6
    return math.max(0.5, math.min(60, s))
end

function DSTB.wetEnabled()
    local sv = DSTB.getSandbox()
    return sv == nil or sv.WetClothing ~= false
end

-- Liquids that are sealed while the container is 100% full (factory sealed: cans, bottles, cartons) but spill
-- once opened, i.e. any amount missing. Keys are item full types. Filled in by the generated DSTB_Compat_*_Containers files.
DSTB.Config.SealedWhenFull = {}

-- Liquid foods (tea, coffee, soups, stews...): they spill at the liquid rates and wet what they spill on as well as
-- stain it, at the volume estimated from its hunger and thirst (see drinkLitres in DSTB_Spill.lua). Filled in by the
-- generated DSTB_Compat_* files from the "Liquid" flag of the food markup pages; nothing is guessed from the item.
DSTB.Config.LiquidFoods = {}

-- Carbonated drinks (fluid containers) that foam over when opened after exercise. Filled in by the generated
-- DSTB_Compat_*_Containers files from the "Fizzy" flag of the container markup pages.
DSTB.Config.CarbonatedItems = {}

-- Foods exempt from the loose-food mechanic (neither crushed nor dirtying the bag): sauces, hard candy, packaged
-- snacks, frozen packs... Closed cans and jars are exempt by rule (see openKind), not listed here. Filled in by the
-- generated DSTB_Compat_* files from the food markup pages.
DSTB.Config.FoodExempt = {}

-- Foods that are safe only while they are still whole: a food whose portion has been eaten into is open and can
-- spill like any other. "Whole" compares the item's stored nutrition with its full value, so cooling, freezing,
-- staleness and cooking (which only change the *effective* value) never make a whole item look eaten.
-- Filled in the same way.
DSTB.Config.FoodExemptWhenUneaten = {}

-- Zupperware (Workshop 3782290703, mod id FreshBoxPortions): a "Portioned Meal" is food sealed in a Zupperware
-- tub, so it counts as closed and safe to carry.
DSTB.Config.FoodExempt["FreshBoxPortions.FreshBoxFood"] = true
