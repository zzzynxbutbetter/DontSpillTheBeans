-- Client side: samples the local player's locomotion and reports compact summaries to the server.
-- No spill decisions are made here.

require "DSTB_Config"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local MAX_TICK_SEC = 0.5   -- ignore long hitches (loading, pause) rather than counting them as movement

local perPlayer = {}       -- playerNum -> { sneak, walk, run, sprint, vaults, wasVaulting, lastMs, sentMs }

local MAX_TICK_HOURS = 0.02  -- same hitch guard, in game time
local ENV_SAMPLE_MS = 1000

-- Animation states of a trip, a bump, a knock-down and a fall: entering one counts as a single event, reported (and
-- spilled for) like a vault. Another within the cooldown, the same tumble going on, does not count again.
local STUMBLE = { bumped = true, falldown = true, falling = true, knockeddown = true }
local STUMBLE_COOLDOWN_MS = 3000

local function newState(nowMs)
    return {
        sneak = 0, walk = 0, run = 0, sprint = 0, vaults = 0, wasVaulting = false, lastMs = nowMs, sentMs = nowMs,
        wasStumbling = false, stumbleMs = nowMs - STUMBLE_COOLDOWN_MS,
        rain = 0, sweat = 0, wetHours = 0, rainSig = 0, sweatSig = 0, envMs = 0,
        lastHr = getGameTime():getWorldAgeHours(),
    }
end

local function coversUpperTorso(item)
    local types = item:getBloodClothingType()
    if not types or types:isEmpty() then return false end
    local parts = BloodClothingType.getCoveredParts(types)
    for i = 0, parts:size() - 1 do
        if parts:get(i) == BloodBodyPartType.Torso_Upper then return true end
    end
    return false
end

-- True when every worn garment over the upper torso is already soaked, i.e. sweat soaks through to the bag.
local function torsoSoaked(player)
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and instanceof(item, "Clothing") and coversUpperTorso(item) and item:getWetness() < 100 then
            return false
        end
    end
    return true
end

-- Vanilla's wetting signals (BodyDamage.UpdateWetness / ClothingWetness), each 0..1:
-- rain on an unsheltered player (or through a broken windshield) and torso perspiration.
local function sampleEnvironment(player)
    local cm = getClimateManager()
    local vehicle = player:getVehicle()
    local square = player:getCurrentSquare()
    local rain = 0

    local outside = square ~= nil and square:isOutside() and not square:isInARoom()
    if vehicle and vehicle:hasRoof(vehicle:getSeat(player)) then outside = false end
    if outside and cm:isRaining() then
        local v = cm:getRainIntensity()
        if v >= 0.1 then rain = v end
        for _, hand in ipairs({ player:getPrimaryHandItem(), player:getSecondaryHandItem() }) do
            if hand and hand:isProtectFromRainWhileEquipped() then rain = 0 end
        end
    end
    if vehicle and cm:isRaining() then
        local windshield = vehicle:getPartById("Windshield")
        local window = windshield and windshield:getWindow()
        if window and window:isDestroyed() then
            local v = cm:getRainIntensity()
            v = math.min(1, v * v * vehicle:getCurrentSpeedKmHour() / 50)
            if v >= 0.1 then rain = math.max(rain, v) end
        end
    end

    local sweat = 0
    local thermo = player:getBodyDamage():getThermoregulator()
    local node = thermo and thermo:getNodeForBloodType(BloodBodyPartType.Torso_Upper)
    if node then
        local p = math.max(0, math.min(1, node:getSecondaryDelta()))
        p = p * p * (0.2 + 0.8 * (1 - node:getDistToCore()))
        if p > 0.1 and torsoSoaked(player) then
            local ext = math.max(0, math.min(20, thermo:getExternalAirTemperature() + 10)) / 20
            sweat = p * (0.4 + 0.6 * ext)
        end
    end
    return rain, sweat
end

local function isVaulting(player)
    local state = player:getCurrentState()
    return state == ClimbOverFenceState.instance()
        or state == ClimbThroughWindowState.instance()
        or state == ClimbOverWallState.instance()
end

local function locomotion(player)
    if player:isSprinting() then return "sprint" end
    if player:isRunning() then return "run" end
    if player:isSneaking() then return "sneak" end
    return "walk"
end

local function flush(player, st, nowMs)
    st.sentMs = nowMs
    if st.sneak + st.walk + st.run + st.sprint + st.vaults + st.rain + st.sweat + st.wetHours <= 0 then return end
    sendClientCommand(player, DSTB.MODULE, "motion", {
        sneak = st.sneak, walk = st.walk, run = st.run, sprint = st.sprint, vaults = st.vaults,
        rain = st.rain, sweat = st.sweat, wetHours = st.wetHours,
    })
    st.sneak, st.walk, st.run, st.sprint, st.vaults = 0, 0, 0, 0, 0

    st.rain, st.sweat, st.wetHours = 0, 0, 0
end

local function onPlayerUpdate(player)
    if not player:isLocalPlayer() or player:isDead() then return end
    local num = player:getPlayerNum()
    local nowMs = getTimestampMs()
    local st = perPlayer[num]
    if not st then
        st = newState(nowMs)
        perPlayer[num] = st
    end

    local dt = math.min((nowMs - st.lastMs) / 1000, MAX_TICK_SEC)
    st.lastMs = nowMs

    local hr = getGameTime():getWorldAgeHours()
    local dh = math.max(0, math.min(hr - st.lastHr, MAX_TICK_HOURS))
    st.lastHr = hr
    if nowMs - st.envMs >= ENV_SAMPLE_MS then
        st.envMs = nowMs
        st.rainSig, st.sweatSig = sampleEnvironment(player)
    end
    st.rain = st.rain + st.rainSig * dh
    st.sweat = st.sweat + st.sweatSig * dh
    if st.rainSig > 0 then st.wetHours = st.wetHours + dh end

    -- Vehicles are watched by the server (Spill.vehicleTick); on foot only here.
    if player:getVehicle() then
        st.wasVaulting, st.wasStumbling = false, false
    else
        local stumbling = STUMBLE[player:getAnimationStateName()] == true
        if stumbling and not st.wasStumbling and nowMs - st.stumbleMs >= STUMBLE_COOLDOWN_MS then
            st.vaults = st.vaults + 1   -- the server counts it with the vaults, with the same validation
            st.stumbleMs = nowMs
        end
        st.wasStumbling = stumbling

        local vaulting = isVaulting(player)
        if vaulting and not st.wasVaulting then st.vaults = st.vaults + 1 end
        st.wasVaulting = vaulting

        if not vaulting and player:isPlayerMoving() then
            local s = locomotion(player)
            st[s] = st[s] + dt
        end
    end

    if (nowMs - st.sentMs) / 1000 >= Config.ReportIntervalSec then flush(player, st, nowMs) end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
