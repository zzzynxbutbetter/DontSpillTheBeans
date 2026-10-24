-- Timed action behind the "Empty Spilled Contents" menu option. Client-driven (no complete()), like
-- other legacy-style actions: on finishing, it asks the server to do the actual emptying.

require "TimedActions/ISBaseTimedAction"
require "DSTB_Config"
require "DSTB_Audio"

local DSTB = DontSpillTheBeans

DSTB_EmptyAction = ISBaseTimedAction:derive("DSTB_EmptyAction")

function DSTB_EmptyAction:isValid()
    return self.character:getInventory():containsRecursive(self.bag) and not self.character:getVehicle()
end

function DSTB_EmptyAction:start()
    self:setActionAnim("Loot")
    self.character:reportEvent("EventLootItem")
    -- The base sound always, layered with one per kind of spilled content in the bag, all through the action.
    self.sounds = DSTB.Audio.emptying(self.character, self.bag, self.maxTime / 48)
end

local FADE_DONE, FADE_STOPPED = 0.6, 0.15   -- seconds: the sounds fade out as the action ends, quicker if it was interrupted

local function fadeSounds(self, seconds)
    if self.sounds then DSTB.Audio.fade(self.sounds, seconds, "out") end
    self.sounds = nil
end

function DSTB_EmptyAction:stop()
    fadeSounds(self, FADE_STOPPED)   -- interrupted: nothing came out
    ISBaseTimedAction.stop(self)
end

function DSTB_EmptyAction:perform()
    fadeSounds(self, self.maxTime <= 1 and FADE_STOPPED or FADE_DONE)
    sendClientCommand(self.character, DSTB.MODULE, "emptySpilled", { id = self.bag:getID() })
    DSTB.Carried.invalidate(self.character)
    ISBaseTimedAction.perform(self)
end

function DSTB_EmptyAction:new(character, bag)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.bag = bag
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or math.floor(DSTB.emptySeconds() * 48)   -- action time runs at 0.8 * 60 = 48 per second at normal game speed
    return o
end
