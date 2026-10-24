-- What the local player's bags hold, for the things that need it often (the shuffling sounds, the bad smell). Scanning the
-- inventory, nested bags included, is not free, so the result is kept for a second and only looked up again after that or
-- as soon as something changes it: Carried.invalidate() is called when the server reports a spill, and when a bag is emptied.

require "DSTB_Config"
require "DSTB_Wet"

local DSTB = DontSpillTheBeans

local Carried = {}
DSTB.Carried = Carried

local MAX_AGE_MS = 1000

local cache = {}   -- player number -> { at = when it was looked up, amounts = Wet.spilledAmounts }

-- Forgets what is known about the bags, so the next Carried.get looks again. `player` = nil: every local player.
function Carried.invalidate(player)
    if player then cache[player:getPlayerNum()] = nil else cache = {} end
end

-- Wet.spilledAmounts(player's inventory): { food, liquid, drink, sour, nested = { food, liquid, drink } }. Do not change it.
function Carried.get(player)
    local num, now = player:getPlayerNum(), getTimestampMs()
    local entry = cache[num]
    if entry and now - entry.at < MAX_AGE_MS then return entry.amounts end
    local amounts = DSTB.Wet.spilledAmounts(player:getInventory())
    cache[num] = { at = now, amounts = amounts }
    return amounts
end
