-- The food or drink the character is eating or drinking does not spill while they do it: walking or running with it in
-- hand would otherwise cost them the very thing they are consuming. The client tells the server (or, in single player,
-- the spill code directly) when such an action starts and ends; afterwards the item is carried and spills like any other.

require "DSTB_Config"
require "DSTB_Spill"
require "DSTB_Hands"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"

local DSTB = DontSpillTheBeans

-- Items DSTB_AutoEquip has decided to hold while they are consumed (item -> true), cleared as the action starts.
DSTB.HoldOnConsume = setmetatable({}, { __mode = "k" })

local function report(action, id)
    local player = action.character
    if not player or not player:isLocalPlayer() then return end
    local hold = id ~= nil and action.item ~= nil and DSTB.HoldOnConsume[action.item] == true
    if hold then DSTB.HoldOnConsume[action.item] = nil end
    if isClient() then
        sendClientCommand(player, DSTB.MODULE, "consuming", { id = id, hold = hold or nil })
    else
        DSTB.Spill.setConsuming(player, id)
        if hold then DSTB.Hands.holdForConsuming(player, action.item) end
    end
end

local function track(class)
    local start, stop, perform = class.start, class.stop, class.perform

    function class:start()
        local result = start(self)
        if self.item then report(self, self.item:getID()) end
        return result
    end

    function class:stop()
        report(self, nil)
        return stop(self)
    end

    function class:perform()
        report(self, nil)
        return perform(self)
    end
end

track(ISEatFoodAction)
track(ISDrinkFluidAction)
