-- Eating or drinking part of an "At 100%" item (a full bottle, an unopened packet: safe in a bag only while whole) takes
-- it into the hands first, so what is left never goes back into the bag, where it would spill. Held items do not spill.
-- It goes into a free hand, else replaces what is in the primary hand (a two-handed item empties both). Vanilla's
-- "return the item to where it was" step is skipped for it. Off with the AutoEquipAtFull option: vanilla behaviour.

require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISCraftingUI"
require "DSTB_Config"
require "DSTB_Spill"

local DSTB = DontSpillTheBeans

local handling   -- the item whose transfer to the main inventory and return to its container vanilla must not queue again

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
