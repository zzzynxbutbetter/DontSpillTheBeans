-- Bag (and washer-soaked item) wetness and "spilled contents" state. The engine only tracks wetness on Clothing, so bags
-- (InventoryContainer) get it here: level 0..100 in item ModData, shown as a tooltip line.
--   DSTB_wet / DSTB_wetHr   wetness level and the world hour it was last settled
--   DSTB_spilled            something spilled inside; the bag stays wet/dirty (no drying) until emptied
--   DSTB_seepMin            worn minutes spent with spilled contents inside
--   DSTB_amtFood/Liquid/Drink  how much of each kind spilled in (portions / litres / portions), for the sounds
--   DSTB_smelly             a liquid other than water spilled in (fuel, milk, juice...): it will go off like food does
--   DSTB_sour               set when seepage starts with anything but water spilled inside: it has gone off and smells
-- Other mods can use DontSpillTheBeans.Wet.get(item) / .add(player, item, amount).

require "DSTB_Config"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local Wet = {}
DSTB.Wet = Wet

-- Items in world containers (a washing machine) have no player to sync through; the caller resends the container.
local function sync(player, item)
    if player then syncItemModData(player, item) end
end

local function worldHours()
    return getGameTime():getWorldAgeHours()
end

function Wet.isSoiled(item)
    return item:getModData().DSTB_spilled == true
end

-- What is spilled in `bag` itself: { food, liquid, drink } (portions of food, litres of liquid, portions of liquid food;
-- the sounds follow these), all zero if the bag is not spilled in. A bag spilled in before the amounts were recorded counts
-- as some dry food.
function Wet.bagAmounts(bag)
    local md = bag:getModData()
    if not md.DSTB_spilled then return { food = 0, liquid = 0, drink = 0 } end
    local a = { food = md.DSTB_amtFood or 0, liquid = md.DSTB_amtLiquid or 0, drink = md.DSTB_amtDrink or 0 }
    if a.food + a.liquid + a.drink <= 0 then a.food = Config.SoundFullFood * 0.5 end
    return a
end

-- Everything spilled in the bags inside `container`: { food, liquid, drink } for the bags carried directly (worn, in a
-- hand, in a hotbar slot or just in the inventory) and the same under `nested` for bags inside another bag, which are
-- heard muffled; `sour` counts the directly carried ones that have gone off (see Wet.goOff):
-- one shut in another bag does not smell.
function Wet.spilledAmounts(container, into, depth)
    into = into or { food = 0, liquid = 0, drink = 0, sour = 0, nested = { food = 0, liquid = 0, drink = 0 } }
    depth = depth or 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if item:getModData().DSTB_spilled then
                local a, to = Wet.bagAmounts(item), depth == 0 and into or into.nested
                to.food, to.liquid, to.drink = to.food + a.food, to.liquid + a.liquid, to.drink + a.drink
                if depth == 0 and item:getModData().DSTB_sour then into.sour = into.sour + 1 end   -- one that smells, carried in the open
            end
            if depth < 4 then Wet.spilledAmounts(item:getInventory(), into, depth + 1) end
        end
    end
    return into
end

-- Current wetness of a bag after drying, 0..100. Dries like vanilla clothing items (40/h carried, half that while worn), but not while soiled.
function Wet.get(item)
    local md = item:getModData()
    local level = md.DSTB_wet
    if not level then return 0 end
    if md.DSTB_spilled then return level end
    local rate = DSTB.value("BagDryPerHour") * (item:isEquipped() and Config.WornDryFactor or 1)
    return math.max(0, level - rate * (worldHours() - (md.DSTB_wetHr or worldHours())))
end

-- Vanilla shows wetness in clothing names ("Shirt (Wet)", Clothing.getName). Bags get the same, using the
-- vanilla strings and thresholds, unless the player has renamed the bag (a rename sets the custom-name flag,
-- and then the name is never touched). The name is always derived from the script name, so it is idempotent
-- and survives reloads, where the engine resets non-custom names. Returns true if the name changed.
function Wet.applyName(item)
    if not instanceof(item, "InventoryContainer") or item:isCustomName() then return false end
    local script = item:getScriptItem()
    if not script then return false end
    local level = Wet.get(item)
    local key = level >= 100 and "IGUI_ClothingName_Soaked" or level > 25 and "IGUI_ClothingName_Wet" or nil
    local want = key and getText("IGUI_ClothingNaming", getText(key), script:getDisplayName()) or script:getDisplayName()
    if item:getName() == want then return false end
    item:setName(want)
    return true
end

local function tooltipFor(item, level)
    if Wet.isSoiled(item) then
        return item:getModData().DSTB_sour and "Tooltip_DontSpillTheBeans_BagSour" or "Tooltip_DontSpillTheBeans_BagSpilled"
    end
    -- The "(Wet)" / "(Soaked)" name suffix (applyName) already says it; the percentage is added when the card is drawn.
    return nil
end

local function store(item, level)
    local md = item:getModData()
    if level < 5 and not md.DSTB_spilled then
        md.DSTB_wet, md.DSTB_wetHr = nil, nil
    else
        md.DSTB_wet, md.DSTB_wetHr = level, worldHours()
    end
    item:setTooltip(tooltipFor(item, level))
    Wet.applyName(item)
end

function Wet.setLevel(player, item, level)
    if instanceof(item, "Clothing") then return end   -- clothing has real engine wetness
    store(item, math.max(0, math.min(100, level)))
    sync(player, item)
end

function Wet.add(player, item, amount)
    if instanceof(item, "Clothing") then return end
    Wet.setLevel(player, item, Wet.get(item) + amount)
end

-- Small environmental increments are buffered so the item is not re-synced every report.
function Wet.addBuffered(player, item, amount)
    local md = item:getModData()
    md.DSTB_wetBuf = (md.DSTB_wetBuf or 0) + amount
    if md.DSTB_wetBuf >= 2 or md.DSTB_wetBuf <= -2 then
        local add = md.DSTB_wetBuf
        md.DSTB_wetBuf = nil
        Wet.add(player, item, add)
    end
end

function Wet.markSoiled(player, item)
    local md = item:getModData()
    local level = Wet.get(item)
    md.DSTB_spilled = true
    md.DSTB_seepMin = md.DSTB_seepMin or 0
    store(item, level)
    sync(player, item)
end

-- The spilled contents were emptied out: the bag stays wet/dirty but may dry from now on.
function Wet.clearSoiled(player, item)
    local md = item:getModData()
    local level = md.DSTB_wet or 0
    md.DSTB_spilled, md.DSTB_seepMin, md.DSTB_stain, md.DSTB_hot, md.DSTB_hotN = nil, nil, nil, nil, nil
    md.DSTB_amtFood, md.DSTB_amtLiquid, md.DSTB_amtDrink = nil, nil, nil
    md.DSTB_sour, md.DSTB_smelly = nil, nil
    store(item, level)
    sync(player, item)
end

-- The spilled contents of `bag` have gone off: it smells from now on, until emptied or washed. Server / SP only.
function Wet.makeSour(player, bag)
    local md = bag:getModData()
    md.DSTB_sour = true
    store(bag, Wet.get(bag))
    sync(player, bag)
end

-- Seepage from `bag` has started: if anything but water is spilled in it (food, liquid food, fuel, milk...) it goes off,
-- and stays that way until the bag is emptied or washed. Server / SP only.
function Wet.goOff(player, bag)
    if not DSTB.sourEnabled() then return end
    local md = bag:getModData()
    if md.DSTB_sour then return end
    local a = Wet.bagAmounts(bag)
    if a.food + a.drink > 0 or md.DSTB_smelly then Wet.makeSour(player, bag) end
end

-- Re-settle every wet bag the player carries (drying) and refresh its tooltip. Server / SP only.
local function refreshIn(player, container, depth)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getModData().DSTB_wet then
            store(item, Wet.get(item))
            sync(player, item)
        end
        if instanceof(item, "InventoryContainer") and depth < 4 then
            refreshIn(player, item:getInventory(), depth + 1)
        end
    end
end

function Wet.refresh(player)
    refreshIn(player, player:getInventory(), 0)
end
