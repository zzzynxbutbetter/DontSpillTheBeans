-- Client side: player feedback for spills decided by the server.
-- Its sounds are in DSTB_Audio.lua (local emitter only; zombies must never hear them).

require "DSTB_Config"
require "DSTB_Audio"
require "DSTB_Carried"
require "DSTB_Smell"
require "DSTB_Tint"

local DSTB = DontSpillTheBeans

local Handlers = {}

Handlers.spilled = function(args)
    local player = getPlayer()
    if not player or not args.events then return end
    DSTB.Carried.invalidate()   -- what the bags hold has changed: the shuffling sounds follow it from the next step
    -- Written like a thought, at most two lines: one for what the character carries, one for the vehicle.
    local carried, inVehicle = false, false
    local places = {}   -- key -> { name = ..., hot = true if a hot spill burnt you there }
    local order = {}
    local burnt = false
    for _, e in ipairs(args.events) do
        if e.vehicle then
            inVehicle = true
        else
            carried = true
            local key = e.bag and tostring(e.bag) or "pockets"
            local place = places[key]
            if not place then
                place = { name = e.storing or getText("IGUI_DontSpillTheBeans_Pockets") }
                places[key] = place
                order[#order + 1] = place
            end
            if e.burn then place.hot = true; burnt = true end
        end
        if isDebugEnabled() then
            print(string.format("[DontSpillTheBeans] spilled %.3f (%s) of %s (storing: %s%s)", e.lost or 0, tostring(e.kind), e.item,
                tostring(e.storing), e.vehicle and ", in the vehicle" or ""))
        end
    end

    if burnt then DSTB.Audio.event(player, "Burn") end

    -- The game joins texts queued in the same tick into one halo note with the separator: a line break stacks them.
    -- The hot line only names the places where something hot spilled; everywhere else gets the plain spill line.
    if carried then
        local hot, plain = {}, {}
        for _, place in ipairs(order) do table.insert(place.hot and hot or plain, place) end
        if #hot > 0 then
            local text = #hot > 1 and getText("IGUI_DontSpillTheBeans_ScaldedSeveral") or getText("IGUI_DontSpillTheBeans_ScaldedIn", hot[1].name)
            HaloTextHelper.addText(player, text, "[br/]", HaloTextHelper.getColorRed())
        end
        if #plain > 0 then
            local text = #plain > 1 and getText("IGUI_DontSpillTheBeans_SpilledSeveral") or getText("IGUI_DontSpillTheBeans_SpilledIn", plain[1].name)
            HaloTextHelper.addText(player, text, "[br/]", HaloTextHelper.getColorRed())
        end
    end
    if inVehicle then
        HaloTextHelper.addText(player, getText("IGUI_DontSpillTheBeans_SpilledVehicle"), "[br/]", HaloTextHelper.getColorRed())
    end
end

-- A hot spill has soaked through a worn bag onto the skin.
Handlers.scalded = function(args)
    local player = getPlayer()
    if not player or type(args) ~= "table" or type(args.bags) ~= "table" then return end
    DSTB.Audio.event(player, "Burn")
    local text = #args.bags > 1 and getText("IGUI_DontSpillTheBeans_SoakedSeveral") or getText("IGUI_DontSpillTheBeans_SoakedIn", args.bags[1])
    HaloTextHelper.addText(player, text, "[br/]", HaloTextHelper.getColorRed())
end

-- A carbonated drink foamed over as it was opened.
Handlers.fizzed = function(args)
    local player = getPlayer()
    if player then
        DSTB.Audio.event(player, "FoamOver")
        HaloTextHelper.addText(player, getText("IGUI_DontSpillTheBeans_Fizzed"), "[br/]", HaloTextHelper.getColorRed())
    end
end

-- What another player's bags hold (relayed by the server), for the sounds they make when they move.
Handlers.soundState = function(args)
    DSTB.Audio.setRemote(args)
end

Handlers.debugShake = function(args)
    local player = getPlayer()
    if player then HaloTextHelper.addText(player, "DSTB shake " .. tostring(args.value), "", HaloTextHelper.getColorWhite()) end
end

Handlers.debugCargo = function(args)
    local player = getPlayer()
    if player then
        HaloTextHelper.addText(player, args.ok and "DSTB test cargo added to the nearest vehicle" or "DSTB: no vehicle within 8 tiles", "", HaloTextHelper.getColorWhite())
    end
end

Handlers.debugStress = function(args)
    local player = getPlayer()
    if player and args.lines then
        HaloTextHelper.addText(player, "DSTB stress test: " .. args.lines[1] .. " (timings in the console)", "", HaloTextHelper.getColorWhite())
    end
end

Handlers.debugProbe = function(args)
    if HaloTextHelper and getPlayer() then
        HaloTextHelper.addText(getPlayer(), "DSTB vehicle probe " .. (args.on and "ON" or "OFF") .. " (see console)", "", HaloTextHelper.getColorWhite())
    end
end

Handlers.debugMultiplier = function(args)
    print("[DontSpillTheBeans] debug rate multiplier = " .. tostring(args.value))
    DSTB.debugMultiplier = args.value
    local player = getPlayer()
    if player then HaloTextHelper.addText(player, "DSTB spill x" .. tostring(args.value), "", HaloTextHelper.getColorWhite()) end
end

local function onServerCommand(module, command, args)
    if module ~= DSTB.MODULE then return end
    local handler = Handlers[command]
    if handler then handler(args or {}) end
end

Events.OnServerCommand.Add(onServerCommand)
