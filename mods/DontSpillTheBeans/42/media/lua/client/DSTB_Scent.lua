-- Starving Zombies integration (optional; Workshop 3396867685, ids StarvingZombies / StarvingZombiesWIP).
-- That mod keeps how far zombies smell the local player, in tiles, in player:getModData().szSmell and recomputes it about
-- once a second from blood (stamping modData.szUpdate each time). Right after each recomputation we add the smell of
-- what has spilled on what the player carries and wears. Its zombie logic only ever looks at the local player, on the
-- client that controls the zombie, and the scent is read from synced item data, so this works in multiplayer too.
-- Vehicle cargo is deliberately left out: only scent on the player counts.

require "DSTB_Config"
require "DSTB_Spill"

local DSTB = DontSpillTheBeans

local lastStamp

Events.OnPlayerUpdate.Add(function(player)
    if not player:isLocalPlayer() then return end
    local md = player:getModData()
    local stamp = md.szUpdate
    if stamp == nil or stamp == lastStamp then return end
    lastStamp = stamp
    if md.szSmell == nil or not DSTB.scentEnabled() then return end
    local scent = DSTB.Spill.playerScent(player)
    if scent > 0 then md.szSmell = md.szSmell + scent end
end)
