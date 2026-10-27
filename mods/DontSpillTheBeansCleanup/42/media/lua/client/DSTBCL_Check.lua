-- Debug only (the game started with -debug): right-click the ground > "Cleanup check" lists, in the console and as a note over
-- the character, what in the inventory and in the containers and floor items within a few tiles still carries data from
-- Don't Spill the Beans, a "(Wet)" or "(Soaked)" name, a stored tooltip key, or is a drink sealed with no way to open it.
-- Run it before (with the other mods loaded: shows what the kit made) and after (Cleanup alone) to see the cleaning work.
-- Needs a single-player save, or an admin on a server for the items the client can see.

local PREFIX = "DSTB_"
local RADIUS = 3

local function findings(item)
    local out = {}
    if item:hasModData() then
        local keys = {}
        for k, _ in pairs(item:getModData()) do
            if type(k) == "string" and k:sub(1, #PREFIX) == PREFIX then keys[#keys + 1] = k end
        end
        table.sort(keys)
        if #keys > 0 then out[#out + 1] = "data: " .. table.concat(keys, ",") end
    end
    local tip = item:getTooltip()
    if tip and tip:find("DontSpillTheBeans", 1, true) then out[#out + 1] = "tooltip: " .. tip end
    if instanceof(item, "InventoryContainer") and (item:getName():find("%(Wet%)") or item:getName():find("%(Soaked%)")) then
        out[#out + 1] = "wet name"
    end
    local fc = item:getFluidContainer()
    if fc and not fc:canPlayerEmpty() and not item:getOpeningRecipe() then out[#out + 1] = "sealed with no opening recipe" end
    return out
end

local totals
local function scanItem(item, where, depth)
    totals.items = totals.items + 1
    local f = findings(item)
    if #f > 0 then
        totals.dirty = totals.dirty + 1
        print(string.format("[DSTB Cleanup check] %s: %s | %s", where, item:getName(), table.concat(f, "; ")))
    end
    if depth < 8 and instanceof(item, "InventoryContainer") then
        local items = item:getInventory():getItems()
        for i = 0, items:size() - 1 do scanItem(items:get(i), where .. " > " .. item:getName(), depth + 1) end
    end
end

local function scanContainer(container, where)
    local items = container:getItems()
    for i = 0, items:size() - 1 do scanItem(items:get(i), where, 0) end
end

local function check(player)
    totals = { items = 0, dirty = 0 }
    print("[DSTB Cleanup check] ---- start")
    scanContainer(player:getInventory(), "inventory")
    local cx, cy, cz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    for dx = -RADIUS, RADIUS do
        for dy = -RADIUS, RADIUS do
            local sq = getCell():getGridSquare(cx + dx, cy + dy, cz)
            if sq then
                local objects = sq:getObjects()
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    for c = 0, o:getContainerCount() - 1 do scanContainer(o:getContainerByIndex(c), "container") end
                end
                local floor = sq:getWorldObjects()
                for i = 0, floor:size() - 1 do
                    local item = floor:get(i):getItem()
                    if item then scanItem(item, "floor", 0) end
                end
            end
        end
    end
    local text = string.format("Cleanup check: %d of %d items still have something to clean (see console)", totals.dirty, totals.items)
    print("[DSTB Cleanup check] " .. text)
    HaloTextHelper.addText(player, text, "", totals.dirty == 0 and HaloTextHelper.getColorWhite() or HaloTextHelper.getColorRed())
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test)
    if test or not isDebugEnabled() then return end
    context:addOption("Cleanup check (debug)", getSpecificPlayer(playerNum), check)
end)
