-- Washing a bag (sink): vanilla cleans its dirt and blood; here it also becomes wet, like washed clothing,
-- and no longer counts as having spilled contents inside (machines are assumed to do the same job).

require "DSTB_Config"
require "DSTB_Wet"
require "TimedActions/ISWashClothing"

local DSTB = DontSpillTheBeans

local vanillaComplete = ISWashClothing.complete
function ISWashClothing:complete()
    local result = vanillaComplete(self)
    if instanceof(self.item, "InventoryContainer") then
        DSTB.Wet.clearSoiled(self.character, self.item)
        DSTB.Wet.setLevel(self.character, self.item, 100)
    end
    return result
end
