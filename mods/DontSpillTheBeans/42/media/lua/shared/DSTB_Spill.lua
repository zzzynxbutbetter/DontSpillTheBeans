-- Core spill logic. Authoritative: call only on the server (or in single player, where the
-- server-side command handler runs in the same process). Never call this from client-only code.

require "DSTB_Config"
require "DSTB_Wet"
require "DSTB_Compat"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local Spill = {}
DSTB.Spill = Spill

local MAX_NEST_DEPTH = 4

-- A closed can or jar: canned food that has not been opened yet (opening leaves an empty vessel behind, which
-- is what ReplaceOnUse is), or home-canned preserved food.
local function isClosedPackage(item)
    if item:getReplaceOnUse() then return false end
    return item:getStringItemType() == "CannedFood" or item:hasTag(ItemTag.PRESERVED_FOOD) or Config.SealedJars[item:getFullType()] == true
end

-- Whether a Food item has any nutrition to lose. Unpackable bundles (hotdog pack, bun bags, candy package) are
-- Food items with no hunger or thirst value: they just turn into loose food when opened, so they are ignored.
local function hasNutrition(item)
    if item:getBaseHunger() ~= 0 then return true end
    local script = item:getScriptItem()
    return script ~= nil and script:getThirstChange() ~= 0
end

-- True while a Food item has not been eaten into. Compares the stored (raw) nutrition with the full value;
-- cooked/burnt/stale/rotten/frozen/cold only change what getHungerChange() reports, never these fields.
local function isUneaten(item)
    local base = item:getBaseHunger()
    if base ~= 0 then return math.abs(item:getHungChange()) >= math.abs(base) - 0.0005 end
    local script = item:getScriptItem()
    local thirst = script and script:getThirstChange() or 0
    if thirst ~= 0 then return math.abs(item:getThirstChangeUnmodified()) >= math.abs(thirst / 100) - 0.0005 end
    return item:getCurrentUses() >= item:getMaxUses()   -- no hunger or thirst value: counted in uses
end

-- What `item` is for spilling purposes, given how deep it sits (0 = the player's own inventory, 1 = directly in
-- a carried bag, 2+ = inside a container inside the bag):
--   "liquid" open fluid container, at any depth (unless a protective container shields it, see scan);
--   "drink"  Food flagged as liquid (Config.LiquidFoods: tea, soup, stew...), spills and wets like a liquid;
--   "food"   any other Food, crushed/melted when loose in a bag. Any nested container keeps it safe;
--   (frozen Food and cold liquids do not spill at all while they stay frozen)
--   nil      cannot spill: sealed, empty, frozen liquid, exempt (or exempt while uneaten), a closed can/jar, or safely contained.
-- Whether a non-empty fluid container would spill, ignoring temperature: "sealed" (never), "full" (sealed only while
-- full; this one is) or "spills". A container with an opening step (its script names an OpeningRecipe: bottled beer and
-- wine, the cans and cartons Vessel Fixes seals, Vanilla Foods Expanded's drinks) is sealed until the player opens it and
-- spills from then on even while still full: opening it is the deliberate "are you sure?". For the rest the per-item
-- tables win (SealedWhenFull stands in for a sealed state the item itself does not have, so full cans spill only once
-- drunk from); otherwise a container the player cannot open or empty (script Opened = false, which stays false even after
-- drinking) counts as sealed, and the rest go by container name.
local function fluidVerdict(item, fc)
    if item:getOpeningRecipe() then return fc:canPlayerEmpty() and "spills" or "sealed" end
    local id = item:getFullType()
    if Config.SealedFluidItems[id] then return "sealed" end
    if Config.SealedWhenFull[id] then
        return fc:getAmount() < fc:getCapacity() - 0.0005 and "spills" or "full"
    end
    if Config.OpenFluidItems[id] then return "spills" end
    if not fc:canPlayerEmpty() then return "sealed" end
    return Config.OpenContainerNames[fc:getContainerName()] and "spills" or "sealed"
end

local function openKind(item, depth)
    local fc = item:getFluidContainer()
    if fc then
        if fc:isEmpty() then return nil end
        if DSTB.coldLiquidsSafe() and item:getItemHeat() < Config.ColdFluidBelowHeat then return nil end   -- cold (blue in the inventory) counts as frozen
        return fluidVerdict(item, fc) == "spills" and "liquid" or nil
    end
    if instanceof(item, "Food") then
        if not DSTB.foodSpillEnabled() then return nil end
        if depth > 1 or (depth == 0 and not DSTB.foodInPocketsEnabled()) then return nil end
        local id = item:getFullType()
        if not hasNutrition(item) then return nil end
        if Config.FoodExempt[id] or isClosedPackage(item) then return nil end
        if Config.FoodExemptWhenUneaten[id] then
            local mode = DSTB.atFullMode()
            if mode == "sealed" or (mode == "whole" and isUneaten(item)) then return nil end
        end
        if item:isFrozen() then return nil end   -- solid while it stays frozen
        return Config.LiquidFoods[id] and "drink" or "food"
    end
    return nil
end

-- Whether `item` is an open fluid container: one that spills whenever it holds something (also when empty; a
-- sealed-when-full one counts once it has been opened). The washing machine fills these with water.
function Spill.isOpenFluidContainer(item)
    local fc = item:getFluidContainer()
    if not fc then return false end
    return fluidVerdict(item, fc) == "spills"
end

-- Whether `item` is an "At 100%" item that is still whole: a full sealed-when-full container, or an uneaten food that is
-- exempt only while uneaten. Eating or drinking part of it makes it spillable (see the auto-equip in DSTB_AutoEquip).
function Spill.isAtFull(item)
    if not DSTB.isEnabled() then return false end
    local fc = item:getFluidContainer()
    if fc then
        return Config.SealedWhenFull[item:getFullType()] == true and not fc:isEmpty() and fluidVerdict(item, fc) == "full"
    end
    if instanceof(item, "Food") then
        local id = item:getFullType()
        if not DSTB.foodSpillEnabled() or not Config.FoodExemptWhenUneaten[id] or not hasNutrition(item) then return false end
        if Config.FoodExempt[id] or isClosedPackage(item) then return false end
        return DSTB.atFullMode() == "whole" and isUneaten(item)
    end
    return false
end

-- Whether `item` is a Food that sits in an open vessel (soup in a bowl, tea in a mug, pasta in a pot): it has a
-- ReplaceOnUse item and is not an exempt packaged food. The washing machine ruins these.
function Spill.isFoodInOpenVessel(item)
    if not instanceof(item, "Food") or not item:getReplaceOnUse() or not hasNutrition(item) then return false end
    return not Config.FoodExempt[item:getFullType()]
end

-- Whether `item` is a Food flagged as liquid (Config.LiquidFoods: soup, tea...). The dryer acts on these only.
function Spill.isLiquidFood(item)
    return instanceof(item, "Food") and Config.LiquidFoods[item:getFullType()] == true and hasNutrition(item)
end

-- What to tell the player about `item` when it is carried loose in a bag, as a suffix of a
-- Tooltip_DontSpillTheBeans_Hint<suffix> key; nil when the mod has nothing to say (not a container or food it touches,
-- an empty container, or the mechanic is switched off). Mirrors openKind's rules, so it can never disagree with it.
local function hintSuffix(item)
    if not DSTB.isEnabled() then return nil end
    local fc = item:getFluidContainerFromSelfOrWorldItem()   -- an item lying on the ground only has it on its world item
    if fc then
        local verdict = fluidVerdict(item, fc)
        if fc:isEmpty() then return verdict == "sealed" and "EmptySafe" or "EmptySpills" end
        if verdict == "sealed" then return "Safe" end
        if verdict == "full" then return "SafeWhenFull" end
        return DSTB.coldLiquidsSafe() and item:getItemHeat() < Config.ColdFluidBelowHeat and "SafeFrozen" or "Spills"
    end
    if instanceof(item, "Food") then
        if not DSTB.foodSpillEnabled() or not hasNutrition(item) then return nil end
        local id = item:getFullType()
        if Config.FoodExempt[id] or isClosedPackage(item) then return "Safe" end
        if Config.FoodExemptWhenUneaten[id] then
            local mode = DSTB.atFullMode()
            if mode == "sealed" then return "Safe" end
            if mode == "whole" and isUneaten(item) then return "SafeWhole" end
        end
        if item:isFrozen() then return "SafeFrozen" end
        if Config.LiquidFoods[id] then return "Spills" end
        if not DSTB.foodInPocketsEnabled() and getPlayer() and item:getContainer() == getPlayer():getInventory() then return nil end
        return "Crushed"
    end
    if instanceof(item, "InventoryContainer") then
        return Config.ProtectiveContainers[item:getFullType()] and "Protective" or "Plain"
    end
    return nil
end

-- The "safe" hints say "in a bag" unless things spill in the pockets too (liquids always do, food when the sandbox
-- option is on): then they are the "Carry" variants, which say nothing about where.
local SAFE_HINTS = { Safe = true, SafeWhole = true, SafeWhenFull = true, SafeFrozen = true, EmptySafe = true }

function Spill.hint(item)
    local suffix = hintSuffix(item)
    if suffix and SAFE_HINTS[suffix] and (item:getFluidContainerFromSelfOrWorldItem() or DSTB.foodInPocketsEnabled()) then
        return suffix .. "Carry"
    end
    return suffix
end

-- How much of a Food item's portion is left, 0..1 (vanilla derives its weight the same way); nil when the
-- item has no hunger or thirst value to measure by.
local function foodFraction(item)
    local base = item:getBaseHunger()
    if base ~= 0 then return math.max(0, math.min(1, item:getHungChange() / base)) end
    local script = item:getScriptItem()
    local thirst = script and script:getThirstChange() or 0
    if thirst ~= 0 then return math.max(0, math.min(1, item:getThirstChangeUnmodified() * 100 / thirst)) end
    return nil
end

-- Litres in a whole portion of a liquid-flagged Food: its larger hunger or thirst value (script units, as water's
-- ThirstChange is per litre) over Config.ThirstPerLitre, so a mug of tea (thirst 20) is 0.4 L, a bowl of soup (15) 0.3 L
-- and a bucket of it (40) 0.8 L. Config.DrinkLitres when the script gives nothing to go by.
local function drinkLitres(item)
    local script = item:getScriptItem()
    if not script then return Config.DrinkLitres end
    local size = math.max(math.abs(script:getHungerChange()), math.abs(script:getThirstChange()))
    return size > 0 and size / Config.ThirstPerLitre or Config.DrinkLitres
end

-- Takes `lost` (fraction of a full portion) out of a Food item: nutrition scales down with it, and when it
-- is gone the item turns into its empty vessel if it has one (as vanilla's "pour out"), else it is destroyed.
local function spillFood(player, item, before, lost)
    local after = before - lost
    if after <= 0.02 then
        item:setCurrentUses(1)
        item:UseAndSync()
        return
    end
    local k = after / before
    item:setHungChange(item:getHungChange() * k)
    item:setThirstChange(item:getThirstChangeUnmodified() * k)
    item:setCalories(item:getCalories() * k)
    item:setCarbohydrates(item:getCarbohydrates() * k)
    item:setLipids(item:getLipids() * k)
    item:setProteins(item:getProteins() * k)
    syncItemFields(player, item)
end

local function isHeld(player, item)
    return player:isPrimaryHandItem(item) or player:isSecondaryHandItem(item)
end

-- The item each player is eating or drinking right now never spills (see DSTB_Consuming): username -> { id, ms }. The
-- client reports when the action starts and ends; the entry also lapses on its own in case an end report never comes.
local CONSUMING_LAPSE_MS = 30000
local consuming = {}

-- Server / SP: `id` = the item's ID while an eat or drink action runs on it, nil when it is over.
function Spill.setConsuming(player, id)
    consuming[tostring(player:getUsername())] = id and { id = id, ms = getTimestampMs() } or nil
end

local function isConsuming(player, item)
    local c = consuming[tostring(player:getUsername())]
    return c ~= nil and c.id == item:getID() and getTimestampMs() - c.ms < CONSUMING_LAPSE_MS
end

-- Collects {item, storing, kind} for everything the player carries that can spill. A protective container
-- (plastic bag, lunchbox, cooler...) shields everything inside it; food is additionally safe in any nested container.
-- storing is the bag holding it, or nil when it sits directly in the player's own inventory.
-- vehicle = true when `container` is part of a vehicle (seat, trunk, glovebox): things lying loose in it are
-- treated like things loose in a bag, and `storing` stays nil (there is no bag to take the mess).
local function scan(player, container, storing, out, depth, vehicle)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if depth < MAX_NEST_DEPTH and not Config.ProtectiveContainers[item:getFullType()] then
                scan(player, item:getInventory(), item, out, depth + 1, vehicle)
            end
        elseif (vehicle or not isHeld(player, item)) and not isConsuming(player, item) then
            local kind = openKind(item, (vehicle and storing == nil) and 1 or depth)
            if kind then out[#out + 1] = { item = item, storing = storing, kind = kind, vehicle = vehicle } end
        end
    end
end

function Spill.collectCandidates(player)
    local out = {}
    scan(player, player:getInventory(), nil, out, 0)
    return out
end

-- Loose cargo in the containers (seats, trunk, glovebox) of `vehicle`, scanned like a bag.
local function scanVehicle(player, vehicle, out)
    for i = 0, vehicle:getPartCount() - 1 do
        local container = vehicle:getPartByIndex(i):getItemContainer()
        if container then scan(player, container, nil, out, 0, true) end
    end
end

-- Dirt on a bag/clothing item on the engine's 0..1 per-body-part scale; false if it cannot get dirty. (Most bags, e.g.
-- the duffel bag, toolboxes and cases, have no blood location in vanilla and never get dirty: that is respected.)
local function addDirt(item, amount)
    local types = item:getBloodClothingType()
    if not types or types:isEmpty() then return false end
    local parts = BloodClothingType.getCoveredParts(types)
    if not parts then return false end
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        item:setDirt(part, item:getDirt(part) + amount)
    end
    if instanceof(item, "Clothing") then
        item:setDirtiness(math.min(100, item:getDirtiness() + amount * 100))
    end
    return true
end

local function dirtLevel(item)
    local types = item:getBloodClothingType()
    if not types or types:isEmpty() then return 0 end
    local parts = BloodClothingType.getCoveredParts(types)
    if not parts then return 0 end
    local top = 0
    for i = 0, parts:size() - 1 do top = math.max(top, item:getDirt(parts:get(i))) end
    return top
end

Spill.dirtLevel = dirtLevel

-- Where a garment sits in the spill order when its body location is not in Config.ClothingOrder (modded
-- items, odd locations): by the body parts it covers. nil = ignore it.
local function rankFromCoverage(item)
    local types = item:getBloodClothingType()
    if not types or types:isEmpty() then return nil end
    local parts = BloodClothingType.getCoveredParts(types)
    if not parts then return nil end
    local feet, head, torso, legs, hands = false, false, false, false, false
    for i = 0, parts:size() - 1 do
        local name = tostring(parts:get(i))
        if name:find("Foot") then feet = true
        elseif name:find("Hand") then hands = true
        elseif name:find("Head") or name:find("Neck") then head = true
        elseif name:find("Torso_Upper") or name:find("Arm") then torso = true
        elseif name:find("Leg") or name:find("Groin") or name:find("Torso_Lower") then legs = true
        end
    end
    if hands and not (torso or legs) then return 50 end
    if torso then return 33 end
    if legs then return 11 end
    if feet then return 21 end
    if head then return 60 end
    return nil
end

-- Worn clothing in the order spills reach it: by body part (legs, feet, torso, arms, head), outside in within each,
-- socks before shoes (see Config.ClothingOrder; unlisted garments are placed by coverage).
local function wornLayers(player)
    local worn = player:getWornItems()
    local list = {}
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and instanceof(item, "Clothing") then
            local id = tostring(worn:getLocation(item)):lower():gsub("^[^:]*:", "")
            local rank = Config.ClothingOrder[id] or rankFromCoverage(item)
            if rank then list[#list + 1] = { rank = rank, item = item } end
        end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.item:getID() < b.item:getID()
    end)
    return list
end

-- Where a garment sits in the order foam from a carbonated drink reaches it (Config.FizzOrder) when its body location is
-- not listed: by the body parts it covers (arms and torso = a long-sleeve top). nil = ignore it.
local function fizzRankFromCoverage(item)
    local types = item:getBloodClothingType()
    if not types or types:isEmpty() then return nil end
    local parts = BloodClothingType.getCoveredParts(types)
    if not parts then return nil end
    local feet, head, torso, arms, legs, hands = false, false, false, false, false, false
    for i = 0, parts:size() - 1 do
        local name = tostring(parts:get(i))
        if name:find("Foot") then feet = true
        elseif name:find("Hand") then hands = true
        elseif name:find("Head") or name:find("Neck") then head = true
        elseif name:find("Arm") then arms = true
        elseif name:find("Torso_Upper") then torso = true
        elseif name:find("Leg") or name:find("Groin") or name:find("Torso_Lower") then legs = true
        end
    end
    if hands and not (torso or arms or legs) then return 1 end
    if arms then return 2.3 end
    if torso then return 3.3 end
    if head then return 4.1 end
    if legs then return 5.2 end
    if feet then return 6.2 end
    return nil
end

-- Worn clothing in the order foam from a carbonated drink reaches it (see Config.FizzOrder).
local function foamLayers(player)
    local worn = player:getWornItems()
    local list = {}
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and instanceof(item, "Clothing") then
            local id = tostring(worn:getLocation(item)):lower():gsub("^[^:]*:", "")
            local rank = Config.FizzOrder[id] or fizzRankFromCoverage(item)
            if rank then list[#list + 1] = { rank = rank, item = item } end
        end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.item:getID() < b.item:getID()
    end)
    return list
end

-- Pour `amount` of wetness (0..100 units) or dirt (0..1) onto the worn layers (by default in seepage order, or the
-- given list of { item = ... }). Without `inherit` the first layer takes what it can hold and the rest overflows to the
-- next one; with `inherit` (0..1) every layer gets its own share instead: the first `amount`, each next one `inherit`
-- times what the one before it got, however much that one could actually hold (seepage trickling down the body); it
-- stops once what is handed on is too little to notice. Returns what was left over because every layer was full (or
-- nothing is worn).
local function addToLayers(player, kind, amount, layers, inherit)
    local remaining, touched = amount, false
    for _, layer in ipairs(layers or wornLayers(player)) do
        local item = layer.item
        local room, give
        if kind == "wet" then
            room = 100 - item:getWetness()
            give = math.min(room, remaining)
            if give > 0 then item:setWetness(item:getWetness() + give) end
        else
            room = (100 - item:getDirtiness()) / 100
            give = math.min(room, remaining)
            if give > 0 and not addDirt(item, give) then give = 0 end
        end
        if give > 0 then
            remaining = remaining - give
            touched = true
            syncItemFields(player, item)
        end
        if inherit then
            amount = amount * inherit
            remaining = amount
            if amount < (kind == "wet" and 1 or 0.01) then break end
        elseif remaining <= 0.001 then break end
    end
    if touched then
        player:resetModelNextFrame()
        syncVisuals(player)
    end
    return remaining
end

-- How far a trickle reaches down the body: each garment gets `share` (the option, at most 1) of the one before it,
-- scaled by how severe the soaking is (0..1). A light seep or a small foam therefore dies out after a garment or two,
-- while a heavy one runs all the way down to the shoes.
local function handedOn(share, severity)
    return share * math.max(0, math.min(1, severity))
end

local function itemDirt(item)
    if instanceof(item, "Clothing") then return item:getDirtiness() / 100 end
    return dirtLevel(item)
end

-- Things directly inside a spilled-in bag pick up what is sloshing around in it, up to the bag's own level:
-- clothing gets wet (and dirty if the spill stains), nested bags too, towels swap to their wet version.
-- Whatever is inside a nested container is shielded (we never look in), and plastic bags / lunchboxes are
-- waterproof. wetStep (0..100) and dirtStep (0..1) cap how much each item takes per call.
-- Scent only ever comes from spills of ours: the amount is recorded on the item when it happens (DSTB_scent), and dirt
-- from any other source (vanilla, other mods) never adds to it. The item's dirt is only read as a "has it been washed"
-- signal: DSTB_scentDirt is the most dirt it has had since the scent was recorded (settleScent raises it as dirt of any
-- kind builds up), and the scent scales with how much of that is left, so a half wash halves the smell.
local function baseScent(item)
    local md = item:getModData()
    local s = md.DSTB_scent
    if not s or s <= 0 then return 0 end
    local d0 = md.DSTB_scentDirt
    if d0 and d0 > 0 then s = s * math.min(1, itemDirt(item) / d0) end
    return s
end

-- What a bag smells of now: stronger once the spilled food/drink inside it has gone off (when its seepage starts: the same
-- moment as the Bad Smell moodle, DSTB_sour; with souring switched off, from the spill itself), weaker once that has been
-- emptied out without the stain being washed (DSTB_scentState "fresh" / "emptied").
local function scentOf(item)
    local s = baseScent(item)
    if s <= 0 then return 0 end
    local md = item:getModData()
    if md.DSTB_scentState == "fresh" and (md.DSTB_sour or not DSTB.sourEnabled()) then return s * DSTB.value("ScentSpilledFactor") end
    return s * DSTB.value("ScentEmptiedFactor")   -- an emptied bag, or clothing something spilled on
end
Spill.scentOf = scentOf

-- inside = true for a bag the spill went into (its contents are now spilled inside it).
local function addScent(player, item, amount, inside)
    local md = item:getModData()
    md.DSTB_scent = math.min(DSTB.value("ScentCapPerItem"), baseScent(item) + amount)
    md.DSTB_scentDirt = itemDirt(item)
    if inside then md.DSTB_scentState = "fresh" end
    syncItemModData(player, item)
end

-- A bag with scent has had its spilled contents emptied out (not yet washed): the smell drops. The caller syncs.
function Spill.scentEmptied(bag)
    local md = bag:getModData()
    if md.DSTB_scentState == "fresh" then md.DSTB_scentState = "emptied" end
end

-- Spilled in the pockets: the smell goes into the innermost worn garment.
local function addScentToClothing(player, amount)
    local layers = wornLayers(player)
    if layers[1] then addScent(player, layers[1].item, amount) end
end

-- Calls fn(item) for everything in `container`, nested bags included.
local function eachCarried(container, fn, depth)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        fn(item)
        if depth < MAX_NEST_DEPTH and instanceof(item, "InventoryContainer") then eachCarried(item:getInventory(), fn, depth + 1) end
    end
end

-- Total scent on what the player carries and wears, for Starving Zombies (client). Vehicles and the ground never count.
function Spill.playerScent(player)
    local total, parts = 0, {}
    eachCarried(player:getInventory(), function(item)
        local s = scentOf(item)
        if s > 0 then
            total = total + s
            parts[#parts + 1] = { name = item:getDisplayName(), scent = s }
        end
    end, 0)
    return math.min(DSTB.value("ScentMaxTotal"), total) * DSTB.scentMultiplier(), parts
end

-- Server, every ten minutes: once dirt has been washed out, make the stored scent match what is left (so new dirt of
-- another kind cannot bring it back) and forget scent that has gone.
function Spill.settleScent(player)
    eachCarried(player:getInventory(), function(item)
        local md = item:getModData()
        if md.DSTB_scent then
            local s = baseScent(item)
            if s < 0.05 then
                md.DSTB_scent, md.DSTB_scentDirt, md.DSTB_scentState = nil, nil, nil
                syncItemModData(player, item)
            elseif s < md.DSTB_scent - 0.01 then
                md.DSTB_scent, md.DSTB_scentDirt = s, itemDirt(item)
                syncItemModData(player, item)
            elseif itemDirt(item) > (md.DSTB_scentDirt or 0) + 0.01 then
                md.DSTB_scentDirt = itemDirt(item)   -- dirt from elsewhere: a later wash is judged against it
                syncItemModData(player, item)
            end
        end
    end, 0)
end

local function contaminateContents(player, bag, wetStep, dirtStep)
    local wetTarget = DSTB.wetEnabled() and DSTB.Wet.get(bag) or 0
    local dirtTarget = (bag:getModData().DSTB_stain and DSTB.dirtyEnabled()) and dirtLevel(bag) or 0
    if wetTarget <= 0 and dirtTarget <= 0 then return end
    local inv = bag:getInventory()
    local items = inv:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if not Config.ProtectiveContainers[item:getFullType()] then
            local touched, swapped = false, false
            if instanceof(item, "Clothing") then
                if wetTarget > item:getWetness() then
                    item:setWetness(math.min(wetTarget, item:getWetness() + wetStep))
                    touched = true
                end
            elseif instanceof(item, "InventoryContainer") then
                local level = DSTB.Wet.get(item)
                if wetTarget > level then
                    DSTB.Wet.setLevel(player, item, math.min(wetTarget, level + wetStep))
                    touched = true
                end
            else
                local wetType = Config.WetVariants[item:getFullType()]
                if wetType and wetTarget >= 50 then
                    local wet = instanceItem(wetType)
                    wet:setFavorite(item:isFavorite())
                    inv:Remove(item)
                    sendRemoveItemFromContainer(inv, item)
                    inv:AddItem(wet)
                    sendAddItemToContainer(inv, wet)
                    swapped = true
                end
            end
            if not swapped and dirtTarget > itemDirt(item) then
                if addDirt(item, math.min(dirtTarget - itemDirt(item), dirtStep)) then touched = true end
            end
            if touched then syncItemFields(player, item) end
        end
    end
end

-- Every ten in-game minutes: spilled-in bags the player carries (worn or not) keep soaking what is in them,
-- including things put in after the spill.
local function contaminateIn(player, container, depth)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if DSTB.Wet.isSoiled(item) then
                contaminateContents(player, item, DSTB.value("ContentsWetPerStep"), DSTB.value("ContentsDirtPerStep"))
            end
            if depth < MAX_NEST_DEPTH then contaminateIn(player, item:getInventory(), depth + 1) end
        end
    end
end

function Spill.contaminateAll(player)
    contaminateIn(player, player:getInventory(), 0)
end

-- What the player calls a bag in the feedback text: their own name for it if they renamed it, otherwise the plain
-- item name in lower case ("backpack", never "Backpack (Wet)").
local function containerName(bag)
    if not bag then return nil end
    if bag:isCustomName() then return bag:getName() end
    local script = bag:getScriptItem()
    return string.lower(script and script:getDisplayName() or bag:getDisplayName())
end

-- How hot an item is on the engine's scale (1 = room temperature, above 1.6 = hot, 3 = the maximum).
local function heatOf(item)
    if instanceof(item, "Food") then return item:getHeat() end
    return item:getItemHeat()
end

-- The bag a bag sits in or is that lies against the body, looking through nested bags: worn, on a hotbar slot, or loose
-- in the pockets (not one held in a hand). nil if none of them does.
local function bodyCarrier(player, bag)
    local depth = 0
    while bag and depth <= MAX_NEST_DEPTH + 1 do
        if player:isEquippedClothing(bag) or bag:getAttachedSlot() > -1 then return bag end
        local container = bag:getContainer()
        if container == player:getInventory() and not bag:isEquipped() then return bag end
        bag = container and container:getContainingItem() or nil
        depth = depth + 1
    end
    return nil
end

-- Maybe scalds the skin under what the hot spill came out of: legs for pockets, torso for a worn bag (the waist for
-- belt and fanny packs). Burns here are mild and heal far sooner than a fire burn. The server owns body damage, so
-- this runs there and is synced to the owner. Returns true if the character got burnt.
local function scald(player, carrier, heat, spills)
    -- Each hot spill step is a chance to burn, so a bag that took many of them is likelier to.
    local chance = 1 - (1 - DSTB.value("BurnChance")) ^ (spills or 1)
    if ZombRand(100) >= chance * 100 then return false end
    local part
    if carrier == nil then
        part = ZombRand(2) == 0 and BodyPartType.UpperLeg_L or BodyPartType.UpperLeg_R
    else
        local location = string.lower(tostring(carrier:getBodyLocation()))
        part = (location:find("fanny") or location:find("belt") or location:find("waist")) and BodyPartType.Torso_Lower or BodyPartType.Torso_Upper
    end
    local body = player:getBodyDamage():getBodyPart(part)
    local t = math.max(0, math.min(1, (heat - Config.HotAbove) / (3 - Config.HotAbove)))
    local lo = DSTB.value("BurnTimeMin")
    local time = lo + t * (math.max(lo, DSTB.value("BurnTimeMax")) - lo)
    if body:getBurnTime() < time then
        body:setBurnTime(time)
        body:setNeedBurnWash(true)
        body:setLastTimeBurnWash(0)
    end
    syncBodyPart(body, 0xFFFFFFFFFFF)   -- only does anything on a dedicated server
    return true
end

-- Applies `fraction` ({ liquid = ..., food = ... }: the share of capacity lost, drinks count as liquids) to each candidate,
-- appending the spill events to `events`.
local function spillCandidates(player, cands, fraction, events)
    for _, c in ipairs(cands) do
        local item, storing, kind = c.item, c.storing, c.kind
        local md = item:getModData()
        local fc = kind == "liquid" and item:getFluidContainer() or nil
        local edible = false   -- whether a liquid would smell of something (not water, fuel, bleach...)
        if fc then
            local f = fc:getPrimaryFluid()
            edible = f ~= nil and not f:isCategory(FluidCategory.Water) and not f:isCategory(FluidCategory.Hazardous)
                and not f:isCategory(FluidCategory.Medical) and (f:isCategory(FluidCategory.Beverage) or f:isCategory(FluidCategory.Alcoholic))
        end
        local capacity = fc and fc:getCapacity() or 1.0
        local step = fc and Config.SpillStepLitres or Config.SpillStepFood
        local debt = (md.DSTB_debt or 0) + capacity * (kind == "food" and fraction.food or fraction.liquid)
        local steps = math.floor(debt / step)
        if steps > 0 then
            local name = item:getDisplayName()
            local lost, litres, waterOnly
            if fc then
                lost = math.min(steps * step, fc:getAmount())
                litres = lost
                waterOnly = fc:isWaterOnlySource()
                fc:adjustAmount(fc:getAmount() - lost)
                debt = fc:isEmpty() and 0 or (debt - steps * step)
                syncItemFields(player, item)
            else
                local before = foodFraction(item)
                if before then
                    lost = math.min(steps * step, before)
                    litres = kind == "drink" and lost * drinkLitres(item) or 0
                    debt = (before - lost <= 0.02) and 0 or (debt - steps * step)
                    spillFood(player, item, before, lost)
                else
                    -- nothing to measure it by (no hunger/thirst value): it only makes a mess
                    lost, litres, debt = 0, 0, 0
                end
            end

            -- Water only wets; other liquids and drinks wet and stain; solid-ish food only stains.
            local wet = (DSTB.wetEnabled() and litres > 0) and litres * DSTB.value("WetnessPerLitre") or 0
            local stains = not waterOnly and DSTB.dirtyEnabled()
            local dirt = stains and (kind == "liquid" and DSTB.value("DirtPerStep") or DSTB.value("FoodDirtPerStep")) or 0
            if storing then
                -- The bag takes it and keeps it until emptied and washed; clothing only gets it by seepage.
                if wet > 0 then DSTB.Wet.add(player, storing, wet) end
                if dirt > 0 and addDirt(storing, dirt) then
                    storing:getModData().DSTB_stain = true
                    syncItemFields(player, storing)
                end
                if lost > 0 then   -- what is in there, for the sounds it makes (see DSTB_Audio)
                    local key = kind == "liquid" and "DSTB_amtLiquid" or kind == "drink" and "DSTB_amtDrink" or "DSTB_amtFood"
                    local bagData = storing:getModData()
                    bagData[key] = (bagData[key] or 0) + lost
                    if kind == "liquid" and not waterOnly then bagData.DSTB_smelly = true end   -- anything but water goes off in time
                end
                DSTB.Wet.markSoiled(player, storing)
                contaminateContents(player, storing, 100, 1)
            elseif not c.vehicle then
                -- Spilled in the clothing's own pockets: straight onto the worn layers. (Loose in a vehicle container:
                -- just lost, there is no bag or clothing to take the mess.)
                if wet > 0 then addToLayers(player, "wet", wet) end
                if dirt > 0 then addToLayers(player, "dirt", dirt) end
            end

            -- Food and edible drinks leave a smell on what they soaked into (Starving Zombies reads it, see DSTB_Scent).
            if DSTB.scentEnabled() and not (c.vehicle and not storing) then
                local scent = 0
                if kind == "food" or (kind == "drink" and item:getBaseHunger() ~= 0) then scent = lost * DSTB.value("FoodScentPerPortion")   -- soups smell like food
                elseif kind == "drink" then scent = lost * drinkLitres(item) * DSTB.value("LiquidScentPerLitre")
                elseif edible then scent = litres * DSTB.value("LiquidScentPerLitre") end
                if scent > 0 then
                    if storing then addScent(player, storing, scent, true) else addScentToClothing(player, scent) end
                end
            end

            -- Hot contents burn the character: at once from the pockets (straight onto the clothing), but from a worn
            -- bag only once the spill has seeped through (see Spill.seep), so the bag just remembers how hot it was.
            local burn = false
            if lost > 0 and not c.vehicle and DSTB.hotBurnsEnabled() then
                local heat = heatOf(item)
                if heat > Config.HotAbove then
                    if storing == nil then
                        burn = scald(player, nil, heat)
                    else
                        local carrier = bodyCarrier(player, storing)
                        if isDebugEnabled() then
                            print(string.format("[DontSpillTheBeans] hot spill (heat %.2f) of %s in %s: %s", heat, name, tostring(storing:getName()),
                                carrier and "remembered by the bag against the body" or "bag held in a hand, no burn"))
                        end
                        if carrier then
                            local cmd = carrier:getModData()
                            cmd.DSTB_hot = math.max(cmd.DSTB_hot or 0, heat)
                            cmd.DSTB_hotN = (cmd.DSTB_hotN or 0) + 1
                            syncItemModData(player, carrier)
                        end
                    end
                end
            end

            events[#events + 1] = {
                burn = burn or nil,
                item = name,
                storing = containerName(storing),   -- how the player would say it ("backpack"), nil for pockets
                bag = storing and storing:getID() or nil,
                vehicle = c.vehicle or nil,
                kind = kind,
                lost = lost,
            }
        end
        md.DSTB_debt = debt
    end
end


-- A carbonated drink foamed over: `litres` of it sprays over the clothes the character wears, wetting and (unless it is
-- plain water) staining them in the order of Config.FizzOrder. Server / SP only.
function Spill.foamOnClothing(player, litres, waterOnly)
    local layers = foamLayers(player)
    if #layers == 0 then return end
    local wet = litres * DSTB.value("WetnessPerLitre")
    local inherit = handedOn(DSTB.value("FoamInherit"), wet / 100)   -- soaking the first garment through = full severity
    if DSTB.wetEnabled() then
        addToLayers(player, "wet", wet, layers, inherit)
    end
    if not waterOnly and DSTB.dirtyEnabled() then
        addToLayers(player, "dirt", litres / Config.SpillStepLitres * DSTB.value("DirtPerStep"), layers, inherit)
    end
end

-- exposure = { sneak=sec, walk=sec, run=sec, sprint=sec, vaults=n } (already validated; vehicles are handled by vehicleTick). Returns a list of spill events { item = <display name>, storing = <display name or nil>,
-- kind = ..., lost = amount } where lost is litres for liquids and a fraction of a full portion for food and drinks.
function Spill.apply(player, exposure)
    if not DSTB.isEnabled() then return nil end

    local scale = DSTB.rateMultiplier() * DSTB.traitFactor(player)   -- Graceful spill less, Clumsy more
    local fraction = {}
    for _, kind in ipairs({ "liquid", "food" }) do
        local sum = (exposure.vaults or 0) * DSTB.vaultSpill(kind)
        for _, state in ipairs({ "sneak", "walk", "run", "sprint" }) do
            sum = sum + (exposure[state] or 0) * DSTB.footRate(state, kind)
        end
        fraction[kind] = sum * scale
    end
    if fraction.liquid <= 0 and fraction.food <= 0 then return nil end

    local events = {}
    spillCandidates(player, Spill.collectCandidates(player), fraction, events)
    return #events > 0 and events or nil
end

-- Vehicle spill, driven by the server watching the vehicles instead of trusting what clients report.
-- The speed to use: a towed vehicle's own physics may be off, so it follows whatever is towing it.
local function vehicleSpeed(vehicle)
    local root, guard = vehicle, 0
    while root:getVehicleTowedBy() and guard < 8 do root, guard = root:getVehicleTowedBy(), guard + 1 end
    return math.abs(root:getCurrentSpeedKmHour())
end

local BAND_NAMES = { "crawl", "city", "road", "highway" }
local function vehicleBand(kmh)
    local limits = DSTB.vehicleBandLimits()
    if kmh < limits[1] then return nil end
    for i = 2, #limits do
        if kmh < limits[i] then return BAND_NAMES[i - 1] end
    end
    return BAND_NAMES[#BAND_NAMES]
end

local function occupants(vehicle)
    local list = {}
    for seat = 0, vehicle:getMaxPassengers() - 1 do
        local who = vehicle:getCharacter(seat)
        if who and instanceof(who, "IsoPlayer") then list[#list + 1] = who end
    end
    return list
end

-- Someone to attribute an occupant-less vehicle's spill to (item syncing goes through a player): the nearest online
-- player within the sandbox "unattended vehicle range" (0 = none).
local function nearestPlayer(vehicle, players)
    local range = DSTB.unattendedRange()
    if range <= 0 then return nil end
    local best, bestD = nil, range * range
    for _, p in ipairs(players) do
        local dx, dy = p:getX() - vehicle:getX(), p:getY() - vehicle:getY()
        local d = dx * dx + dy * dy
        if d < bestD then best, bestD = p, d end
    end
    return best
end

local function addEvents(report, player, events)
    if #events == 0 then return report end
    report = report or {}
    report[player] = report[player] or {}
    for _, e in ipairs(events) do table.insert(report[player], e) end
    return report
end

-- Called about once a second with the seconds since the previous call. `players` = every online player.
-- Returns { [player] = events } for the feedback to be sent, or nil.
function Spill.vehicleTick(dt, players)
    if not DSTB.isEnabled() or not DSTB.vehicleSpillEnabled() then return nil end
    local cell = getCell()
    local vehicles = cell and cell:getVehicles()
    if not vehicles then return nil end

    local scale = DSTB.rateMultiplier()
    if scale <= 0 then return nil end

    local report
    local towedCounts = DSTB.towedSpillEnabled()
    local it = vehicles:iterator()
    while it:hasNext() do
        local vehicle = it:next()
        local band = (towedCounts or not vehicle:getVehicleTowedBy()) and vehicleBand(vehicleSpeed(vehicle)) or nil
        if band then
            local drive = scale * DSTB.drivingFactor(vehicle:getDriver())   -- Speed Demon spill less, Sunday Driver more
            local fraction = { liquid = DSTB.vehicleRate(band, "liquid") * dt * drive, food = DSTB.vehicleRate(band, "food") * dt * drive }
            local riders = occupants(vehicle)

            -- What the occupants carry.
            for _, p in ipairs(riders) do
                local events = {}
                spillCandidates(p, Spill.collectCandidates(p), fraction, events)
                report = addEvents(report, p, events)
            end

            -- Loose cargo in the vehicle itself. Only someone aboard is told about it: a "Spilled!" message for a car the
            -- player is not in would only confuse them.
            local owner = riders[1] or nearestPlayer(vehicle, players)
            if owner then
                local cargo, events = {}, {}
                scanVehicle(owner, vehicle, cargo)
                if #cargo > 0 then spillCandidates(owner, cargo, fraction, events) end
                if riders[1] then report = addEvents(report, owner, events) end
            end
        end
    end
    return report
end

-- A bag with spilled contents inside that sits in another carried bag seeps into that bag: after the same delay as for
-- clothing the carrying bag gets wet (and dirty, with seepage dirt on), but is not spilled in itself, so it never seeps
-- further. A protective carrier (plastic bag, lunchbox, cooler) shields what it holds and takes nothing.
local function seepIntoCarrier(player, container, carrier, minutes, depth)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local bag = items:get(i)
        if instanceof(bag, "InventoryContainer") then
            if carrier and DSTB.Wet.isSoiled(bag) and not Config.ProtectiveContainers[carrier:getFullType()] then
                local md = bag:getModData()
                md.DSTB_seepMin = (md.DSTB_seepMin or 0) + minutes
                if md.DSTB_seepMin >= DSTB.value("SeepAfterMinutes") then
                    DSTB.Wet.goOff(player, bag)   -- gone off, but shut in the carrier it smells of nothing until it is taken out
                    if DSTB.wetEnabled() and DSTB.Wet.get(bag) >= DSTB.value("SeepMinWet") then
                        DSTB.Wet.add(player, carrier, DSTB.value("SeepWetPerStep") * (0.5 + 0.5 * DSTB.Wet.get(bag) / 100))
                    end
                    if DSTB.dirtyEnabled() and DSTB.seepDirtEnabled() and dirtLevel(bag) >= DSTB.value("SeepMinDirt")
                        and addDirt(carrier, DSTB.value("SeepDirtPerStep")) then
                        syncItemFields(player, carrier)
                    end
                end
                syncItemModData(player, bag)
            end
            if depth < MAX_NEST_DEPTH then seepIntoCarrier(player, bag:getInventory(), bag, minutes, depth + 1) end
        end
    end
end

-- Whether a bag that is carried (not nested) lies against the clothes: worn, on a hotbar slot (it hangs on the body, so it
-- counts as worn), or loose in the pockets (the main inventory). One held in a hand leaks outside them.
local function touchesClothing(player, bag)
    return not bag:isEquipped() or player:isEquippedClothing(bag)
end

-- Worn or on the body in a hotbar slot, as opposed to loose in the pockets.
local function onBody(player, bag)
    return player:isEquippedClothing(bag) or bag:getAttachedSlot() > -1
end

-- Called every ten in-game minutes: a bag the player carries with spilled contents inside seeps, wherever it is carried.
-- Worn or loose in the pockets, it seeps into the clothing under it, and on down the body: each garment in the order gets
-- Config.SeepInherit of what the one before it got, for as long as the bag is not emptied. Held in a hand it seeps just
-- the same (the time is counted, and what spilled in it goes off) but wets and dirties no clothing. Returns the names of
-- bags whose hot spill has just burnt the character, if any.
function Spill.seep(player, minutes)
    local scalded
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local bag = items:get(i)
        if instanceof(bag, "InventoryContainer") and DSTB.Wet.isSoiled(bag) then
            local md = bag:getModData()
            md.DSTB_seepMin = (md.DSTB_seepMin or 0) + minutes
            local onClothes = touchesClothing(player, bag)
            local worn = onBody(player, bag)
            local hot = md.DSTB_hot
            if hot and not DSTB.hotBurnsEnabled() then hot = nil; md.DSTB_hot = nil end
            if onClothes and hot and md.DSTB_seepMin >= DSTB.value("HotSeepAfterMinutes") then
                -- Hot liquid reaches the skin once: the spill cools, so one chance per hot spill (legs for a bag in the pockets).
                local spills = md.DSTB_hotN
                md.DSTB_hot, md.DSTB_hotN = nil, nil
                local burnt = scald(player, worn and bag or nil, hot, spills)
                if isDebugEnabled() then
                    print(string.format("[DontSpillTheBeans] hot spill (heat %.2f) soaked through %s (%d hot spills): %s", hot, tostring(bag:getName()), spills or 1, burnt and "burnt" or "no burn (rolled)"))
                end
                if burnt then
                    scalded = scalded or {}
                    scalded[#scalded + 1] = containerName(bag)
                end
            end
            if md.DSTB_seepMin >= (hot and DSTB.value("HotSeepAfterMinutes") or DSTB.value("SeepAfterMinutes")) then
                DSTB.Wet.goOff(player, bag)   -- seepage has started: food spilled in it has gone off
            end
            if onClothes and md.DSTB_seepMin >= (hot and DSTB.value("HotSeepAfterMinutes") or DSTB.value("SeepAfterMinutes")) then
                if DSTB.wetEnabled() and DSTB.Wet.get(bag) >= DSTB.value("SeepMinWet") then
                    addToLayers(player, "wet", DSTB.value("SeepWetPerStep") * (0.5 + 0.5 * DSTB.Wet.get(bag) / 100), nil, handedOn(DSTB.value("SeepInherit"), DSTB.Wet.get(bag) / 100))
                end
                if DSTB.dirtyEnabled() and DSTB.seepDirtEnabled() and dirtLevel(bag) >= DSTB.value("SeepMinDirt") then
                    addToLayers(player, "dirt", DSTB.value("SeepDirtPerStep"), nil, handedOn(DSTB.value("SeepInherit"), dirtLevel(bag)))
                end
            end
            syncItemModData(player, bag)
        end
    end
    if minutes > 0 then seepIntoCarrier(player, player:getInventory(), nil, minutes, 0) end
    return scalded
end

-- Worn bags get wet from the same things that wet clothing in vanilla. The owning client samples the
-- signals (rain on an unsheltered player, a broken windshield, sweat soaking through the torso layers) and
-- reports them as hour-integrals; the server clamps them and applies them to every worn bag.
--   env = { rain = signal-hours, sweat = signal-hours, wetHours = hours under any rain exposure }
-- While rained on, a bag does not dry (vanilla clothing only dries when it is not being rained on), so the
-- lazy drying over those hours is cancelled out.
function Spill.applyEnvironment(player, env)
    if not DSTB.isEnabled() or not DSTB.wetEnabled() or not DSTB.envWetEnabled() then return end
    local gain = env.rain * DSTB.value("BagRainPerHour") + env.sweat * DSTB.value("BagSweatPerHour")
    if gain <= 0 and env.wetHours <= 0 then return end
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local bag = items:get(i)
        if instanceof(bag, "InventoryContainer") and player:isEquippedClothing(bag) then
            local noDry = DSTB.Wet.isSoiled(bag) and 0 or env.wetHours * DSTB.value("BagDryPerHour") * Config.WornDryFactor
            DSTB.Wet.addBuffered(player, bag, gain + noDry)
        end
    end
end

-- Finds a bag by item id anywhere in the player's carried inventory.
function Spill.findBag(container, id, depth)
    depth = depth or 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if item:getID() == id then return item end
            if depth < MAX_NEST_DEPTH then
                local found = Spill.findBag(item:getInventory(), id, depth + 1)
                if found then return found end
            end
        end
    end
end
