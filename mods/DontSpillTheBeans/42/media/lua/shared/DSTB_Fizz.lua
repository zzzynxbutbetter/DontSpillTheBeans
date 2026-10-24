-- Fizzy drinks. A carbonated drink (Config.CarbonatedItems) that is drunk from while still full, i.e. opened, foams over
-- if the character has been exercising: part of the contents is lost, on top of what they drink. The "shake" that
-- decides how much is kept per player on the server, from the motion they report (on foot only: driving adds none and
-- only lets it fade). Sealed cans and bottles have no separate "open" step in the game, so the first drink is the opening.

require "DSTB_Config"
require "DSTB_Spill"
require "TimedActions/ISDrinkFluidAction"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local Fizz = {}
DSTB.Fizz = Fizz

local meters = {}   -- username -> { v = shake in sprint-seconds, ms = when it was last updated }

local function key(player) return tostring(player:getUsername()) end

local function faded(m, now)
    local half = math.max(1, DSTB.value("FizzFadeSeconds"))
    return m.v * 0.5 ^ ((now - m.ms) / 1000 / half)
end

-- Server / SP: adds a motion report ({ run = sec, sprint = sec, vaults = n }) to the player's shake.
function Fizz.add(player, exposure)
    local gain = (exposure.sprint or 0) + (exposure.run or 0) * 0.5 + (exposure.vaults or 0)
    local now = getTimestampMs()
    local m = meters[key(player)]
    local v = m and faded(m, now) or 0
    meters[key(player)] = { v = math.min(v + gain, 2 * math.max(1, DSTB.value("FizzFullShakeSeconds"))), ms = now }
end

-- 0 (calm) to 1 (a full shake).
function Fizz.shake(player)
    local m = meters[key(player)]
    if not m then return 0 end
    return math.min(1, faded(m, getTimestampMs()) / math.max(1, DSTB.value("FizzFullShakeSeconds")))
end

-- Debug: sets the shake to a fraction of full.
function Fizz.set(player, fraction)
    meters[key(player)] = { v = fraction * math.max(1, DSTB.value("FizzFullShakeSeconds")), ms = getTimestampMs() }
end

local function notify(player, args)
    if isServer() then
        sendServerCommand(player, DSTB.MODULE, "fizzed", args)
    else
        triggerEvent("OnServerCommand", DSTB.MODULE, "fizzed", args)
    end
end

-- Called as a drink action starts. The server (or single player) owns the fluid; a multiplayer client does nothing.
local function foam(action)
    if isClient() or action.dstbFoamed then return end
    action.dstbFoamed = true
    if not DSTB.fizzEnabled() then return end
    local item, fc, player = action.item, action.fluidContainer, action.character
    if not (item and fc and player) or fc:isEmpty() then return end
    if not Config.CarbonatedItems[item:getFullType()] then return end
    if fc:getFilledRatio() < 0.999 then return end   -- already opened: only the first drink from a full container foams

    local shake = Fizz.shake(player)
    if shake < Config.FizzMinShake then return end
    local amount, capacity = fc:getAmount(), fc:getCapacity()
    local lost = math.min(amount, amount * DSTB.value("FizzMaxLoss") * shake * DSTB.traitFactor(player))   -- Graceful lose less, Clumsy more
    if lost <= 0 then return end
    local waterOnly = fc:isWaterOnlySource()
    fc:adjustAmount(amount - lost)
    -- The drink action works out how much was drunk from the fill level, so move its starting point down by what foamed
    -- away: the player still drinks what they meant to, and the foam is lost on top.
    action.startRatio = action.startRatio - lost / capacity
    syncItemFields(player, item)
    DSTB.Spill.foamOnClothing(player, lost, waterOnly)   -- and it sprays over the player's clothes
    notify(player, { lost = lost })
end

local vanillaStart, vanillaServerStart = ISDrinkFluidAction.start, ISDrinkFluidAction.serverStart

function ISDrinkFluidAction:start()
    foam(self)
    return vanillaStart(self)
end

function ISDrinkFluidAction:serverStart()
    foam(self)
    return vanillaServerStart(self)
end
