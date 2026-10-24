-- Washing machines and dryers. The cycles themselves are Java (it only handles loose Clothing and a bag's blood), so:
--  * a machine cannot be started while a bag with spilled contents is inside it (empty it first);
--  * once started, the machine is tracked here and each in-game minute any bag inside is cleaned of dirt and
--    soaked, and what is directly inside the bag gets wet too if it can (clothing, towels); items inside a
--    nested container are shielded. Leave in the bag only what you want washed.
--  * dryers work the same way in reverse: a bag in a running dryer dries like clothing (1 point per minute),
--    unless it still has spilled contents inside, and so does what is directly inside it.

require "DSTB_Config"
require "DSTB_Wet"
require "DSTB_Spill"
require "TimedActions/ISToggleClothingWasher"
require "TimedActions/ISToggleComboWasherDryer"
require "TimedActions/ISToggleClothingDryer"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local Washer = {}
DSTB.Washer = Washer

local MAX_NEST_DEPTH = 4

-- Only the washing half of combination units counts.
local function isWashing(object)
    if instanceof(object, "IsoCombinationWasherDryer") and not object:isModeWasher() then return false end
    return true
end

local function hasSoiledBag(container, depth)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if DSTB.Wet.isSoiled(item) then return true end
            if depth < MAX_NEST_DEPTH and hasSoiledBag(item:getInventory(), depth + 1) then return true end
        end
    end
    return false
end

-- Only the drying half of combination units counts. (Defined before the hooks below, which use it.)
local function isDrying(object)
    if instanceof(object, "IsoClothingDryer") then return true end
    return instanceof(object, "IsoCombinationWasherDryer") and not object:isModeWasher()
end

-- Refuse to switch a machine on while a spilled-in bag is inside it.
local function blockSoiledStart(action)
    local vanillaIsValid = action.isValid
    function action:isValid()
        local object = self.object
        if object and not object:isActivated() and isWashing(object) then
            local container = object:getContainer()
            if container and hasSoiledBag(container, 0) then
                if not isServer() and getTimestampMs() - (DSTB.lastWasherHintMs or 0) > 3000 then
                    DSTB.lastWasherHintMs = getTimestampMs()
                    HaloTextHelper.addText(self.character, getText("IGUI_DontSpillTheBeans_WasherSoiled"), "", HaloTextHelper.getColorRed())
                end
                return false
            end
        end
        return vanillaIsValid(self)
    end
end

-- Remember machines that were switched on, so they can be processed while they run (server / SP only).
local function trackStarted(action)
    local vanillaComplete = action.complete
    function action:complete()
        local result = vanillaComplete(self)
        local object = self.object
        if object and object:isActivated() and (isWashing(object) or isDrying(object)) then Washer.register(object) end
        return result
    end
end

blockSoiledStart(ISToggleClothingWasher)
trackStarted(ISToggleClothingWasher)
blockSoiledStart(ISToggleComboWasherDryer)
trackStarted(ISToggleComboWasherDryer)
trackStarted(ISToggleClothingDryer)

local function registry()
    local data = ModData.getOrCreate(DSTB.MODULE)
    data.washers = data.washers or {}
    return data.washers
end

function Washer.register(object)
    if isClient() then return end
    local sq = object:getSquare()
    if not sq then return end
    registry()[sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()] =
        { x = sq:getX(), y = sq:getY(), z = sq:getZ(), run = tostring(getTimestampMs()) }
end

-- Replaces whatever an open fluid container holds with a random amount of water (20 to 100% of its capacity).
local function fillWithWater(fc)
    fc:Empty()
    if not fc:canAddFluid(Fluid.Water) then return false end
    fc:addFluid(Fluid.Water, fc:getCapacity() * (20 + ZombRand(81)) / 100)
    return true
end

-- An open container (mug, bowl, pot...) directly inside a bag that is being washed is filled with water, once per
-- wash (`run` identifies the wash), and what it held is lost: a food in an open vessel (soup in a bowl, pasta in a
-- pot) turns into the empty vessel holding water. Returns true if something changed.
local function ruinOpenVessel(container, item, run)
    if DSTB.Spill.isFoodInOpenVessel(item) then
        local vessel = instanceItem(item:getReplaceOnUseFullType())
        local fc = vessel and vessel:getFluidContainer()
        if not fc then return false end
        fillWithWater(fc)
        vessel:getModData().DSTB_washRun = run
        vessel:setFavorite(item:isFavorite())
        container:Remove(item)
        container:AddItem(vessel)
        return true
    end
    if not DSTB.Spill.isOpenFluidContainer(item) then return false end
    local md = item:getModData()
    if md.DSTB_washRun == run then return false end
    md.DSTB_washRun = run
    return fillWithWater(item:getFluidContainer())
end

-- Wets what is directly inside a bag, but only things that can get wet in vanilla: clothing (real wetness)
-- and items with a wet counterpart (towels, dish cloths), which are swapped for it. Everything else is
-- unaffected, exactly like loose items in the machine. A nested container can get wet itself (unless it is a
-- protective bag/lunchbox) but whatever is inside it is shielded, so we never recurse. Returns true if
-- anything changed.
local function soakContents(container, run)
    local changed = false
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if instanceof(item, "Clothing") then
            if item:getWetness() < 100 then item:setWetness(100); changed = true end
        elseif instanceof(item, "InventoryContainer") then
            if not Config.ProtectiveContainers[item:getFullType()] and DSTB.Wet.get(item) < 100 then
                DSTB.Wet.setLevel(nil, item, 100)
                changed = true
            end
        elseif run and DSTB.washerFillsEnabled() and ruinOpenVessel(container, item, run) then
            changed = true
        else
            local wetType = Config.WetVariants[item:getFullType()]
            local wet = wetType and instanceItem(wetType)
            if wet then
                wet:setFavorite(item:isFavorite())
                container:Remove(item)
                container:AddItem(wet)
                changed = true
            end
        end
    end
    return changed
end

-- Cleans one loose bag in the machine: dirt comes off gradually, it gets soaked.
local function washBag(bag, minutes, run)
    local changed = false
    local types = bag:getBloodClothingType()
    local parts = types and not types:isEmpty() and BloodClothingType.getCoveredParts(types)
    if parts then
        for i = 0, parts:size() - 1 do
            local part = parts:get(i)
            local dirt = bag:getDirt(part)
            if dirt > 0 then
                bag:setDirt(part, math.max(0, dirt - Config.WasherBagDirtPerMinute * minutes))
                changed = true
            end
        end
    end
    if DSTB.Wet.get(bag) < 100 then DSTB.Wet.setLevel(nil, bag, 100); changed = true end
    if DSTB.Wet.isSoiled(bag) then DSTB.Wet.clearSoiled(nil, bag); changed = true end
    if soakContents(bag:getInventory(), run) then changed = true end
    return changed
end

-- A dryer takes what open vessels hold out of them (only liquids and liquid foods; anything else is left alone):
-- a liquid is emptied completely, a liquid food loses nutrition (DryerNutritionPer5Min per 5 minutes, scaled by how
-- liquid it is: its thirst share of hunger plus thirst, so tea loses it faster than soup) and becomes its empty
-- vessel once none is left. Returns true if something changed.
local function dryOpenVessel(container, item, minutes)
    if not DSTB.dryerEmptiesEnabled() then return false end
    if DSTB.Spill.isLiquidFood(item) then
        local script = item:getScriptItem()
        local hungerBase, thirstBase = script and math.abs(script:getHungerChange()) or 0, script and math.abs(script:getThirstChange()) or 0
        local liquidShare = (hungerBase + thirstBase) > 0 and thirstBase / (hungerBase + thirstBase) or 1
        local points = DSTB.value("DryerNutritionPer5Min") * liquidShare / 5 * minutes / 100   -- script units are 100 times the stored value
        if points <= 0 then return false end
        local hunger = math.min(0, item:getHungChange() + points)
        local thirst = math.min(0, item:getThirstChangeUnmodified() + points)
        if hunger > -0.005 and thirst > -0.005 then
            local vesselType = item:getReplaceOnUse() and item:getReplaceOnUseFullType()
            local vessel = vesselType and instanceItem(vesselType)
            if vessel then
                vessel:setFavorite(item:isFavorite())
                container:AddItem(vessel)
            end
            container:Remove(item)
        else
            item:setHungChange(hunger)
            item:setThirstChange(thirst)
        end
        return true
    end
    if DSTB.Spill.isOpenFluidContainer(item) then
        local fc = item:getFluidContainer()
        if not fc:isEmpty() then
            fc:Empty()
            return true
        end
    end
    return false
end

-- Dries what is directly inside a bag at the vanilla dryer's rate: clothing loses 1 wetness per minute, wet
-- towels dry out into their dry version, nested containers dry themselves but their contents are shielded.
-- Returns true if anything changed.
local function dryContents(container, minutes)
    local changed = false
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if instanceof(item, "Clothing") then
            if item:getWetness() > 0 then item:setWetness(math.max(0, item:getWetness() - minutes)); changed = true end
        elseif instanceof(item, "InventoryContainer") then
            local level = DSTB.Wet.get(item)
            if level > 0 and not DSTB.Wet.isSoiled(item) then
                DSTB.Wet.setLevel(nil, item, level - minutes)
                changed = true
            end
        elseif dryOpenVessel(container, item, minutes) then
            changed = true
        elseif item:isWet() and item:getItemWhenDry() then
            item:setWetCooldown(item:getWetCooldown() - minutes * 250)
            if item:getWetCooldown() <= 0 then
                local dry = instanceItem(item:getItemWhenDry())
                if dry then
                    dry:setFavorite(item:isFavorite())
                    container:Remove(item)
                    container:AddItem(dry)
                end
            end
            changed = true
        end
    end
    return changed
end

-- Dries one loose bag in a dryer. A bag that still holds spilled contents stays wet.
local function dryBag(bag, minutes)
    local changed = false
    local level = DSTB.Wet.get(bag)
    if level > 0 and not DSTB.Wet.isSoiled(bag) then
        DSTB.Wet.setLevel(nil, bag, level - minutes)
        changed = true
    end
    if dryContents(bag:getInventory(), minutes) then changed = true end
    return changed
end

local function findMachine(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        if instanceof(o, "IsoClothingWasher") or instanceof(o, "IsoClothingDryer")
            or instanceof(o, "IsoCombinationWasherDryer") then
            return o
        end
    end
end

-- Server / SP, once per in-game minute.
function Washer.update(minutes)
    local list = registry()
    for key, w in pairs(list) do
        local square = getCell():getGridSquare(w.x, w.y, w.z)
        if square then   -- unloaded chunks keep their entry until they load again
            local object = findMachine(square)
            local washing = object and isWashing(object) and not isDrying(object)
            local drying = object and isDrying(object)
            if not object or not object:isActivated() or not (washing or drying) then
                list[key] = nil
            else
                local treat = washing and washBag or dryBag
                local container = object:getContainer()
                local changed = false
                if container then
                    local items = container:getItems()
                    for i = 0, items:size() - 1 do
                        local item = items:get(i)
                        if instanceof(item, "InventoryContainer") and treat(item, minutes, w.run or key) then changed = true end
                    end
                end
                if changed and isServer() then sendItemsInContainer(object, container) end
            end
        end
    end
end
