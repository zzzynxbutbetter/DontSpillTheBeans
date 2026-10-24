-- A bag whose spilled contents have gone off (see Wet.goOff, when its seepage starts) gives whoever carries it in the open, or
-- is near it where it lies on the ground (sandbox: SmellRadius), the "Bad Smell" level of the NoxiousSmell
-- moodle, and never more than that. The moodle is worked out from the character's corpse sickness rate, which the game
-- recomputes (to zero, away from rotting corpses) every update, so the rate is put back each time; it is only a display
-- value for the moodle: the sickness itself is added separately, so this makes nobody ill. Where there are corpses
-- already, their rate is left alone. (The moodle does not show if the "decaying corpse health impact" sandbox option is None.)

require "DSTB_Config"
require "DSTB_Carried"

local DSTB = DontSpillTheBeans

local MAX_AGE_MS = 1000
local near = {}   -- player number -> { at, sour }: whether a bag that has gone off lies within reach

-- Is there a gone-off bag on the ground within the radius (same floor)? Only bags lying directly on a tile count,
-- not ones shut inside a container there. Looked up at most once a second: up to 25 x 25 tiles.
local function groundSour(player)
    local radius = math.floor(DSTB.value("SmellRadius") or 0)
    if radius <= 0 then return false end
    local num, now = player:getPlayerNum(), getTimestampMs()
    local entry = near[num]
    if entry and now - entry.at < MAX_AGE_MS then return entry.sour end
    local sour = false
    local cell, px, py, pz = getCell(), math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            local square = (x - player:getX()) ^ 2 + (y - player:getY()) ^ 2 <= (radius + 0.5) ^ 2 and cell:getGridSquare(x, y, pz) or nil
            local objects = square and square:getWorldObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local item = objects:get(i):getItem()
                if item and instanceof(item, "InventoryContainer") and item:getModData().DSTB_sour then sour = true break end
            end
            if sour then break end
        end
        if sour then break end
    end
    near[num] = { at = now, sour = sour }
    return sour
end

local function smell(player)
    if not player or player:isDead() or not player:isLocalPlayer() then return end
    if not (DSTB.isEnabled() and DSTB.sourEnabled()) then return end
    if player:getCorpseSicknessRate() > 0 then return end
    if DSTB.Carried.get(player).sour > 0 or groundSour(player) then player:setCorpseSicknessRate(DSTB.Config.SourSmellRate) end
end

-- Both before and after the character's update: whichever side of the moodle's own update the game resets the rate on.
Events.OnPlayerUpdate.Add(smell)
Events.OnTick.Add(function()
    for i = 0, getNumActivePlayers() - 1 do smell(getSpecificPlayer(i)) end
end)
