-- Eating or drinking part of a vessel or a packet that does not close again (an opened jar or tin, a can or bottle opened to drink,
-- an unopened packet: see Hands.eligible) holds it in the hands as the eating or drinking starts, so what is left never goes back
-- into the bag, where it would spill. Held items do not spill. There is no equip action: the eat and drink animations show the
-- item in the hands anyway, so it counts as held from the moment they begin. It goes into a free hand, else replaces what is in
-- the primary hand (a two-handed item empties both). Vanilla's "return the item to where it was" step is skipped for it, and
-- what is left of it when it is used up is returned instead. Off with the "Hold opened food and drinks" option in Options > Mods
-- (a player preference, reported to the server): vanilla behaviour.

require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISCraftingUI"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISUnequipAction"
require "DSTB_Config"
require "DSTB_Options"
require "DSTB_Hands"
require "DSTB_Consuming"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

-- The player's preference, in Options > Mods (a tick box per player, not a server setting). Keep the label short: the Mod Manager mod's options screen centres label plus control as one block, and a wider one than the panel runs off its left edge. The server learns it from the "prefs" command.
local holdTick = DSTB.Options.page and DSTB.Options.page:addTickBox("HoldOpened", "Hold opened food and drinks in hand", true,
    "Eating or drinking only some of an opened jar, tin, can or bottle, or of a packet, keeps it in your hands, so what is left does not go back into the bag, where it would spill. When it is used up the empty one goes back to where it came from. Off: it goes back into the bag as in the base game.") or nil
DSTB.Prefs.local_ = function() return holdTick == nil or holdTick:getValue() end

local function reportPrefs()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then
            if isClient() then
                sendClientCommand(player, DSTB.MODULE, "prefs", { hold = DSTB.Prefs.local_() })
            else
                DSTB.Prefs.hold[tostring(player:getUsername())] = DSTB.Prefs.local_()
            end
        end
    end
end
Events.OnGameStart.Add(reportPrefs)
if DSTB.Options.page then
    local applyPage = DSTB.Options.page.apply
    DSTB.Options.page.apply = function(page, ...)
        if applyPage then applyPage(page, ...) end
        reportPrefs()
    end
end

local handling   -- the item whose return to its container vanilla must not queue again (it is held)

local equipped = setmetatable({}, { __mode = "k" })   -- item -> the full type it leaves behind when used up and the container it came from, for items held as they are consumed
local origins = setmetatable({}, { __mode = "k" })   -- item -> the container it was in when the action was chosen
local finished = {}   -- consumed items waiting a moment to see what is left of them: { player, item, left, ms }

local function wants(player, item, fraction)
    if not fraction or fraction >= 1 then return false end   -- all of it: nothing is left to spill
    if not DSTB.holdEnabled(player) or not instanceof(item, "InventoryItem") then return false end
    return DSTB.Hands.eligible(item) and not DSTB.Hands.isHeld(player, item)
end

-- Notes what to do for `item` as it is eaten or drunk from: hold it when the action starts, and put what is left of it away at the end.
local function plan(player, item)
    DSTB.HoldOnConsume[item] = true
    handling = item
    equipped[item] = { left = instanceof(item, "Food") and item:getReplaceOnUseFullType() or nil, origin = item:getContainer() }
end

-- The newest item of that type directly in the inventory (what an item turned into when it was used up).
local function newestOfType(container, fullType)
    local best
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == fullType and (not best or item:getID() > best:getID()) then best = item end
    end
    return best
end

-- Once a vessel eaten or drunk from has been used up, what is left (the empty bottle, can or tin) is taken out of the hands if it was
-- held, and put back where the item came from (as vanilla does after eating), if that is still part of the inventory. A part-eaten item
-- stays as it is, held if it was.
local function emptyHands(player, item, was)
    local vessel
    local fc = item:getFluidContainer()
    if item:getContainer() == nil then   -- used up: the empty vessel it turns into
        vessel = was.left and newestOfType(player:getInventory(), was.left)
    elseif fc and fc:isEmpty() then
        vessel = item
    end
    if not vessel then return end
    if DSTB.Hands.isHeld(player, vessel) then ISTimedActionQueue.add(ISUnequipAction:new(player, vessel, 50)) end
    local bag = was.origin and was.origin:getContainingItem()   -- nil for the ground, a vehicle...: nothing to put back into
    if bag and player:getInventory():containsRecursive(bag) then
        ISCraftingUI.ReturnItemToContainer(player, vessel, was.origin)
    end
end

local function onPlayerUpdate(player)
    for i = #finished, 1, -1 do
        local f = finished[i]
        if f.player == player and getTimestampMs() - f.ms > 400 then
            table.remove(finished, i)
            if not player:isDead() then emptyHands(player, f.item, f.was) end
        end
    end
end
Events.OnPlayerUpdate.Add(onPlayerUpdate)

for _, class in ipairs({ ISEatFoodAction, ISDrinkFluidAction }) do
    local perform = class.perform
    function class:perform()
        local item = self.item
        local was = item and equipped[item]
        -- A vessel that was not held by the plan can be in the hands all the same (a can or bottle opened first is held when the
        -- opening ends): the end of it is dealt with alike.
        if item and was == nil and DSTB.holdEnabled(self.character) and DSTB.Hands.eligible(item) then
            was = { left = instanceof(item, "Food") and item:getReplaceOnUseFullType() or nil, origin = origins[item] }
        end
        local result = perform(self)
        if was ~= nil and self.character:isLocalPlayer() then
            finished[#finished + 1] = { player = self.character, item = item, was = was, ms = getTimestampMs() }
            equipped[item] = nil
        end
        return result
    end
end

local returnToContainer = ISCraftingUI.ReturnItemToOriginalContainer
function ISCraftingUI.ReturnItemToOriginalContainer(player, item)
    if handling ~= nil and item == handling then return end
    return returnToContainer(player, item)
end

local function run(original, player, item, fraction, openingRecipe, ...)
    if instanceof(item, "InventoryItem") and DSTB.holdEnabled(player) and DSTB.Hands.eligible(item) then origins[item] = item:getContainer() end
    if wants(player, item, fraction) then plan(player, item) end
    local ok, err = pcall(original, ...)
    handling = nil
    if not ok then error(err, 0) end
end

local onDrinkFluid = ISInventoryPaneContextMenu.onDrinkFluid
ISInventoryPaneContextMenu.onDrinkFluid = function(item, percent, playerObj, openingRecipe, realItem)
    run(onDrinkFluid, playerObj, item, percent, openingRecipe, item, percent, playerObj, openingRecipe, realItem)
end

local eatItem = ISInventoryPaneContextMenu.eatItem
ISInventoryPaneContextMenu.eatItem = function(item, percentage, playerNum, openingRecipe, eatPercentage)
    run(eatItem, getSpecificPlayer(playerNum), item, percentage, openingRecipe, item, percentage, playerNum, openingRecipe, eatPercentage)
end
