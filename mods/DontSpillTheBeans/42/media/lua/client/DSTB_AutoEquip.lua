-- Eating or drinking part of an "At 100%" item (a full bottle, an unopened packet: safe in a bag only while whole) takes
-- it into the hands first, so what is left never goes back into the bag, where it would spill. Held items do not spill.
-- It goes into a free hand, else replaces what is in the primary hand (a two-handed item empties both). Vanilla's
-- "return the item to where it was" step is skipped for it. Off with the AutoEquipAtFull option: vanilla behaviour.

require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISCraftingUI"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISUnequipAction"
require "DSTB_Config"
require "DSTB_Spill"

local DSTB = DontSpillTheBeans

local handling   -- the item whose transfer to the main inventory and return to its container vanilla must not queue again

local equipped = setmetatable({}, { __mode = "k" })   -- item -> the full type it leaves behind when used up, for items taken into the hands here
local finished = {}   -- consumed items waiting a moment to see what is left of them: { player, item, left, ms }

local function wants(player, item, fraction, openingRecipe)
    if openingRecipe or not fraction or fraction >= 1 then return false end   -- all of it: nothing is left to spill
    if not DSTB.autoEquipEnabled() or not instanceof(item, "InventoryItem") then return false end
    if player:isPrimaryHandItem(item) or player:isSecondaryHandItem(item) then return false end
    return DSTB.Spill.isAtFull(item)
end

-- Queues the equip (with the transfer out of its bag it needs first).
local function equipFirst(player, item)
    local primary = player:getPrimaryHandItem() == nil or player:getSecondaryHandItem() ~= nil
    ISInventoryPaneContextMenu.equipWeapon(item, primary, item:isRequiresEquippedBothHands(), player:getPlayerNum())
    handling = item
    equipped[item] = { left = instanceof(item, "Food") and item:getReplaceOnUseFullType() or nil, origin = item:getContainer() }
end

-- Once an item taken into the hands here has been consumed down to nothing, what is left (the empty bottle, the bowl)
-- goes back into the inventory so the hands are free; a part-eaten item stays in the hands.
-- It is then put back where the item came from (as vanilla does after eating), if that is still part of the inventory.
local function emptyHands(player, item, was)
    for _, held in ipairs({ player:getPrimaryHandItem(), player:getSecondaryHandItem() }) do
        if held and (held == item or (was.left and held:getFullType() == was.left)) then
            local fc = held:getFluidContainer()
            local spent = fc and fc:isEmpty() or (held ~= item) or item:getContainer() == nil
            if spent then
                ISTimedActionQueue.add(ISUnequipAction:new(player, held, 50))
                local origin = was.origin
                local bag = origin and origin:getContainingItem()   -- nil for the ground, a vehicle...: nothing to put back into
                if bag and player:getInventory():containsRecursive(bag) then
                    ISCraftingUI.ReturnItemToContainer(player, held, origin)
                end
            end
            return
        end
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
        local result = perform(self)
        if item and equipped[item] ~= nil and self.character:isLocalPlayer() then
            finished[#finished + 1] = { player = self.character, item = item, was = equipped[item], ms = getTimestampMs() }
            equipped[item] = nil
        end
        return result
    end
end

local transferIfNeeded = ISInventoryPaneContextMenu.transferIfNeeded
function ISInventoryPaneContextMenu.transferIfNeeded(player, item, ...)
    if handling ~= nil and item == handling then return end
    return transferIfNeeded(player, item, ...)
end

local returnToContainer = ISCraftingUI.ReturnItemToOriginalContainer
function ISCraftingUI.ReturnItemToOriginalContainer(player, item)
    if handling ~= nil and item == handling then return end
    return returnToContainer(player, item)
end

local function run(original, player, item, fraction, openingRecipe, ...)
    if wants(player, item, fraction, openingRecipe) then equipFirst(player, item) end
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
