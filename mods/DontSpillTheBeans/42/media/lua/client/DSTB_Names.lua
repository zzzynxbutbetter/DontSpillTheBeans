-- Keeps wet bags' names ("Backpack (Wet)") in step on this client: after the server syncs a bag's wetness
-- (ModData), after a reload (the engine resets non-custom names), and as bags dry.

require "DSTB_Config"
require "DSTB_Wet"

local Wet = DontSpillTheBeans.Wet

local function refreshIn(container, depth)
    local changed = false
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            if Wet.applyName(item) then changed = true end
            if depth < 4 and refreshIn(item:getInventory(), depth + 1) then changed = true end
        end
    end
    return changed
end

local function refreshPlayer(playerNum, redraw)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    if refreshIn(player:getInventory(), 0) and redraw then
        local pdata = getPlayerData(playerNum)
        if pdata and pdata.playerInventory then pdata.playerInventory:refreshBackpacks() end
    end
end

-- Before the inventory window rebuilds its container buttons, so they pick up the right names.
Events.OnRefreshInventoryWindowContainers.Add(function(page, state)
    if state == "begin" then refreshPlayer(page.player, false) end
end)

Events.EveryOneMinute.Add(function()
    for n = 0, getNumActivePlayers() - 1 do refreshPlayer(n, true) end
end)
