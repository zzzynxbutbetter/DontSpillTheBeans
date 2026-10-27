-- Timed action behind the "Empty Spilled Contents" menu option. Client-driven (no complete()), like
-- other legacy-style actions: on finishing, it asks the server to do the actual emptying.
--
-- Animation: the bag is shown in the hands (its own skinned hand model) and turned upside down and shaken. Each bag has
-- one clip (DSTB_BagClips: small, medium, large or pack) holding a lift that turns the bag over, one shake and a lowering,
-- end to end. The action time is a sandbox option (0.5 to 60 s), so the clip is not played at a fixed speed: the AnimSet
-- node (media/AnimSets/player/actions/DSTBEmpty*.xml) takes its playback position from the float variable DSTBTime (0..1
-- of the clip), which this action sets every frame. The lift and the lowering always play whole, the shake repeats in
-- whole cycles to fill what is left of the time, and a time too short for all three plays them faster. Because the position
-- is set directly, the pieces join with no seam and the game speed does not matter. A bag with no clip (see
-- DSTB_BagClips) keeps the stock Loot animation.
-- The node is picked by PerformingAction = DSTBEmptyBag and DSTBClip (small/medium/large/pack).

require "TimedActions/ISBaseTimedAction"
require "DSTB_Config"
require "DSTB_Audio"
require "DSTB_BagClips"

local DSTB = DontSpillTheBeans

DSTB_EmptyAction = ISBaseTimedAction:derive("DSTB_EmptyAction")

local ANIM = "DSTBEmptyBag"
local UNITS_PER_SECOND = 48   -- action time runs at 0.8 * 60 = 48 per second at normal game speed
-- Lengths of the three pieces of the clip in seconds (30 frames per second): lift 26 frames, one shake of 11, lowering 21.
local LIFT, LOOP, LOWER = 26 / 30, 11 / 30, 21 / 30
local WHOLE = LIFT + LOOP + LOWER   -- the clip's length

-- Where in the clip (0..1) the animation is `elapsed` seconds into an action of `total` seconds.
local function clipFraction(total, elapsed)
    local c
    if total <= WHOLE then
        c = elapsed * WHOLE / total          -- too short for all three: the lift, one shake and the lowering, faster
    else
        local span = total - LIFT - LOWER    -- the time for shaking
        if elapsed < LIFT then
            c = elapsed
        elseif elapsed < LIFT + span then
            -- whole shake cycles, slightly faster or slower so that they fit the span exactly and end on the lift's pose
            local cycles = math.max(1, math.floor(span / LOOP + 0.5))
            c = LIFT + ((elapsed - LIFT) * cycles * LOOP / span) % LOOP
        else
            c = LIFT + LOOP + (elapsed - LIFT - span)
        end
    end
    return math.min(1, math.max(0, c / WHOLE))
end
DSTB_EmptyAction.clipFraction = clipFraction

function DSTB_EmptyAction:isValid()
    return self.character:getInventory():containsRecursive(self.bag) and not self.character:getVehicle()
end

function DSTB_EmptyAction:start()
    -- The instant mode (time 1) skips the animation either way.
    self.clip = self.maxTime > 1 and DSTB.BagClips.clipFor(self.bag) or nil
    if isDebugEnabled() then
        print(string.format("[DontSpillTheBeans] emptying %s (%s): %s, %.1f s", tostring(self.bag:getDisplayName()), self.bag:getFullType(),
            self.clip and ("clip " .. self.clip) or ("Loot: " .. DSTB.BagClips.explain(self.bag)), self.maxTime / UNITS_PER_SECOND))
    end
    if self.clip then
        self:setActionAnim(ANIM)
        self:setAnimVariable("DSTBClip", self.clip)
        self.character:setVariable("DSTBTime", 0.0)
        self:setOverrideHandModels(self.bag, nil)   -- the bag's own hand model, which the clip turns over
    else
        self:setActionAnim("Loot")
        self.character:reportEvent("EventLootItem")
    end
    -- The base sound always, layered with one per kind of spilled content in the bag, all through the action.
    self.sounds = DSTB.Audio.emptying(self.character, self.bag, self.maxTime / UNITS_PER_SECOND)
end

function DSTB_EmptyAction:update()
    if not self.clip then return end
    local total = self.maxTime / UNITS_PER_SECOND
    self.character:setVariable("DSTBTime", clipFraction(total, self:getJobDelta() * total))
end

local FADE_DONE, FADE_STOPPED = 0.6, 0.15   -- seconds: the sounds fade out as the action ends, quicker if it was interrupted

local function fadeSounds(self, seconds)
    if self.sounds then DSTB.Audio.fade(self.sounds, seconds, "out") end
    self.sounds = nil
end

local function clearTime(self)
    if self.clip then self.character:clearVariable("DSTBTime") end   -- the string variables are cleared with the action; this one is a float
end

function DSTB_EmptyAction:stop()
    fadeSounds(self, FADE_STOPPED)   -- interrupted: nothing came out
    clearTime(self)
    ISBaseTimedAction.stop(self)
end

function DSTB_EmptyAction:perform()
    fadeSounds(self, self.maxTime <= 1 and FADE_STOPPED or FADE_DONE)
    clearTime(self)
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
    o.maxTime = character:isTimedActionInstant() and 1 or math.floor(DSTB.emptySeconds() * UNITS_PER_SECOND)
    return o
end
