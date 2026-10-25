-- Inventory context menu: "Empty Spilled Contents" on a bag that something spilled in.

require "DSTB_Config"
require "DSTB_Wet"
require "DSTB_EmptyAction"

-- A worn, held or hotbar-attached bag is taken off first and put back afterwards, so the emptying happens "in the hands".
local function emptySpilled(player, bag)
    -- A bag inside another bag is taken out into the main inventory first and put back in that bag afterwards.
    local origin = luautils.haveToBeTransfered(player, bag) and bag:getContainer() or nil
    ISInventoryPaneContextMenu.transferIfNeeded(player, bag)
    local worn = player:isEquippedClothing(bag)
    local hand = nil
    if player:getPrimaryHandItem() == bag then hand = "primary"
    elseif player:getSecondaryHandItem() == bag then hand = "secondary" end

    -- A bag hanging off the hotbar (on the belt or back) is detached first and put back in the same slot afterwards.
    local hotbar, slotIndex, model, slotDef
    if not worn and not hand and bag:getAttachedSlot() > -1 then
        hotbar = getPlayerHotbar(player:getPlayerNum())
        slotIndex, model = bag:getAttachedSlot(), bag:getAttachedToModel()
        local slot = hotbar and hotbar.availableSlot[slotIndex]
        slotDef = slot and slot.def
        if not (slotDef and model) then hotbar = nil end
    end

    if hotbar then
        hotbar:setAttachAnim(bag, slotDef)
        ISTimedActionQueue.add(ISDetachItemHotbar:new(player, bag))
    elseif worn or hand then
        ISTimedActionQueue.add(ISUnequipAction:new(player, bag, 50))
    end
    ISTimedActionQueue.add(DSTB_EmptyAction:new(player, bag))
    if hotbar then
        ISTimedActionQueue.add(ISAttachItemHotbar:new(player, bag, model, slotIndex, slotDef))
    elseif worn then
        ISTimedActionQueue.add(ISWearClothing:new(player, bag, 50))
    elseif hand then
        ISTimedActionQueue.add(ISEquipWeaponAction:new(player, bag, 50, hand == "primary", bag:isRequiresEquippedBothHands()))
    elseif origin and origin ~= player:getInventory() then
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, bag, player:getInventory(), origin))
    end
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    for _, entry in ipairs(items) do
        local item = instanceof(entry, "InventoryItem") and entry or entry.items[1]
        if item and instanceof(item, "InventoryContainer") and DontSpillTheBeans.Wet.isSoiled(item)
            and player:getInventory():containsRecursive(item) then
            local text, drop = getText("ContextMenu_DontSpillTheBeans_EmptySpilled"), getText("ContextMenu_Drop")
            if context:getOptionFromName(drop) then
                context:insertOptionBefore(drop, text, player, emptySpilled, item)   -- with the actions on the bag, above Drop and Move
            else
                context:addOption(text, player, emptySpilled, item)
            end
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
