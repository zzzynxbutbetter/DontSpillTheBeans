-- Don't Spill the Beans: Cleanup. Load it in place of Don't Spill the Beans and its add-ons (only an admin can change the load
-- order, so nothing here needs a permission check). It cleans what those mods left in a save:
--   * every DSTB_* key in item ModData, the "(Wet)" / "(Soaked)" bag names, a tooltip key the mod stored, and the washer registry;
--   * drinks that were sealed by the Vessel Fixes add-ons and now have no opening recipe: a fluid container that cannot be
--     emptied and has no way to be opened is opened.
-- Safeguard: if the main mod or any Vessel Fixes add-on is loaded too, it does nothing at all, so the others work as if it
-- were not there.
-- It works on every square as it loads (containers, floor items, corpses, vehicles) and on each player as they join and every ten
-- minutes, so it reaches everything over time; leave it loaded as long as you like. Server and single player only.
if isClient() then return end

local MAIN = "DontSpillTheBeans"
local OTHERS = {   -- the mods this one cleans up after: while any is loaded, it stands aside
    "DontSpillTheBeans", "DontSpillTheBeansVesselFixes", "DontSpillTheBeansVesselFixesPomps",
    "DontSpillTheBeansVesselFixesVFE", "DontSpillTheBeansVesselFixesSapph",
}
local PREFIX = "DSTB_"
local STORED_TOOLTIPS = { Tooltip_DontSpillTheBeans_BagSour = true, Tooltip_DontSpillTheBeans_BagSpilled = true }

local standAside   -- true when one of the others is loaded (the mod list cannot change while the game runs)
local function isStandingAside()
    if standAside == nil then
        local mods = getActivatedMods()
        standAside = false
        for _, id in ipairs(OTHERS) do
            if mods ~= nil and mods:contains(id) then standAside = true end
        end
        if standAside then print("[DontSpillTheBeansCleanup] Don't Spill the Beans or an add-on is loaded: doing nothing") end
    end
    return standAside
end

local cleaned, opened = 0, 0   -- since the game started, for the log

-- Returns true if the item changed.
local function cleanItem(item, player)
    local changed = false

    do
        if item:hasModData() then
            local md, keys = item:getModData(), {}
            for k, _ in pairs(md) do
                if type(k) == "string" and k:sub(1, #PREFIX) == PREFIX then keys[#keys + 1] = k end
            end
            if #keys > 0 then
                local wet = md.DSTB_wet ~= nil
                for _, k in ipairs(keys) do md[k] = nil end
                changed = true
                if wet and instanceof(item, "InventoryContainer") and not item:isCustomName() then
                    local script = item:getScriptItem()
                    if script and item:getName() ~= script:getDisplayName() then item:setName(script:getDisplayName()) end
                end
                if player and isServer() then syncItemModData(player, item) end
            end
        end
        if STORED_TOOLTIPS[item:getTooltip() or ""] then
            item:setTooltip(nil)
            changed = true
        end
    end

    local fc = item:getFluidContainer()
    if fc and not fc:canPlayerEmpty() and not item:getOpeningRecipe() then
        fc:setCanPlayerEmpty(true)
        fc:adjustAmount(fc:getAmount())   -- sets the same amount again, which rebuilds the "(Sealed)" name
        if player and isServer() then sendItemStats(item) end
        opened = opened + 1
        changed = true
    end

    if changed then cleaned = cleaned + 1 end
    return changed
end

local function cleanContainer(container, player, depth)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        cleanItem(item, player)
        if depth < 8 and instanceof(item, "InventoryContainer") then cleanContainer(item:getInventory(), player, depth + 1) end
    end
end

local function cleanSquare(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        for c = 0, o:getContainerCount() - 1 do cleanContainer(o:getContainerByIndex(c), nil, 0) end
    end
    local floor = square:getWorldObjects()
    for i = 0, floor:size() - 1 do
        local item = floor:get(i):getItem()
        if item then
            cleanItem(item)
            if instanceof(item, "InventoryContainer") then cleanContainer(item:getInventory(), nil, 0) end
        end
    end
    local bodies = square:getStaticMovingObjects()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if instanceof(body, "IsoDeadBody") and body:getContainer() then cleanContainer(body:getContainer(), nil, 0) end
    end
    local vehicle = square:getVehicleContainer()
    if vehicle then
        for i = 0, vehicle:getPartCount() - 1 do
            local container = vehicle:getPartByIndex(i):getItemContainer()
            if container then cleanContainer(container, nil, 0) end
        end
    end
end

Events.LoadGridsquare.Add(function(square)
    if not isStandingAside() then cleanSquare(square) end
end)

-- The washer registry the main mod kept in global ModData (nothing reads it without the mod).
Events.OnInitGlobalModData.Add(function()
    if not isStandingAside() and ModData.exists(MAIN) then ModData.remove(MAIN) end
end)

local function onlinePlayers()
    local list = {}
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do list[#list + 1] = online:get(i) end
    else
        local p = getPlayer()
        if p then list[1] = p end
    end
    return list
end

-- A player is cleaned the first minute they are seen online, then every ten minutes.
local seen = {}
Events.EveryOneMinute.Add(function()
    if isStandingAside() then return end
    for _, p in ipairs(onlinePlayers()) do
        local key = tostring(p:getUsername())
        if not seen[key] then
            seen[key] = true
            cleanContainer(p:getInventory(), p, 0)
        end
    end
end)

local lastLogged = 0
Events.EveryTenMinutes.Add(function()
    if isStandingAside() then return end
    for _, p in ipairs(onlinePlayers()) do cleanContainer(p:getInventory(), p, 0) end
    if cleaned ~= lastLogged then
        lastLogged = cleaned
        print(string.format("[DontSpillTheBeansCleanup] cleaned %d items so far (%d drinks opened)", cleaned, opened))
    end
end)
