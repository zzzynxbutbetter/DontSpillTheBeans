-- Putting an item into the character's hands without an equip action: for things that are in the hands already as far as the
-- animation goes (a jar or tin just opened, a can or bottle being drunk from, a packet being eaten from). A held item does not
-- spill, and the hands are what the opening and eating animations show. Server / single player only: the game sends the
-- hand items of a character the server sets on to the clients.

require "DSTB_Config"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local Hands = {}
DSTB.Hands = Hands

-- Whether `item` is the kind that is held while it is eaten or drunk from (decided by what it is, not by how much is left of it):
-- opened jars and tins, factory-sealed drinks (cans, bottles, cartons) and foods that spill only once bitten.
function Hands.eligible(item)
    local id = item:getFullType()
    return Config.Reseal[id] ~= nil or Config.OpenedTins[id] ~= nil or Config.SealedWhenFull[id] == true or Config.FoodExemptWhenUneaten[id] == true
        or (item:getOpeningRecipe() ~= nil and item:getFluidContainer() ~= nil)
end

function Hands.isHeld(player, item)
    return player:isPrimaryHandItem(item) or player:isSecondaryHandItem(item)
end

-- Same choice of hand as taking an item into the hands by hand: the primary one if it is free (or both are taken), else the
-- secondary; a two-handed item has to go.
function Hands.hold(player, item)
    if Hands.isHeld(player, item) then return end
    local primary, secondary = player:getPrimaryHandItem(), player:getSecondaryHandItem()
    if (primary and primary:isRequiresEquippedBothHands()) or (secondary and secondary:isRequiresEquippedBothHands()) then
        player:setPrimaryHandItem(nil)
        player:setSecondaryHandItem(nil)
        primary, secondary = nil, nil
    end
    if primary == nil or secondary ~= nil then player:setPrimaryHandItem(item) else player:setSecondaryHandItem(item) end
end

-- Called as an eat or drink action starts (see DSTB_Consuming): holds `item` if it is the kind that is held and is carried in the
-- main inventory (vanilla has moved it there from a bag by now). The player can switch it off in Options > Mods (DSTB.holdEnabled).
function Hands.holdForConsuming(player, item)
    if not item or not DSTB.holdEnabled(player) or not Hands.eligible(item) or item:getContainer() ~= player:getInventory() then return end
    Hands.hold(player, item)
end
