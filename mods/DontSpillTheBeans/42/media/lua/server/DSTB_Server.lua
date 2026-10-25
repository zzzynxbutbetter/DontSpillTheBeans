-- Server (and single-player) side: validates client motion reports and applies spills.
if isClient() then return end

require "DSTB_Config"
require "DSTB_Spill"
require "DSTB_Wet"
require "DSTB_Washer"
require "DSTB_Fizz"
require "DSTB_Hands"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local Commands = {}
local lastReportMs = {}   -- username -> timestamp of last accepted report

local STATES = { "sneak", "walk", "run", "sprint" }

-- Server -> owning client. Single player has no real server, so raise the client event directly.
local function notify(player, command, args)
    if isServer() then
        sendServerCommand(player, DSTB.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", DSTB.MODULE, command, args)
    end
end

local function clampNumber(v, lo, hi)
    if type(v) ~= "number" or v ~= v then return 0 end
    return math.max(lo, math.min(hi, v))
end

-- Never trust the client: the total time claimed cannot exceed the time actually elapsed.
local function sanitise(player, args)
    local now = getTimestampMs()
    local key = tostring(player:getUsername())
    local last = lastReportMs[key]
    lastReportMs[key] = now
    local elapsed = last and math.min((now - last) / 1000, Config.MaxReportSec) or Config.ReportIntervalSec
    local budget = elapsed + 0.5

    local clean, total = {}, 0
    for _, s in ipairs(STATES) do
        clean[s] = clampNumber(args[s], 0, Config.MaxReportSec)
        total = total + clean[s]
    end
    if total > budget then
        local scale = budget / total
        for _, s in ipairs(STATES) do clean[s] = clean[s] * scale end
    end
    clean.vaults = math.floor(clampNumber(args.vaults, 0, Config.MaxVaultsPerReport))
    return clean
end

local lastHours = {}   -- username -> world age (hours) of the last motion report

-- Environmental wetting is also client-reported: it cannot exceed the in-game time that actually passed.
local function sanitiseEnv(player, args)
    local now = getGameTime():getWorldAgeHours()
    local key = tostring(player:getUsername())
    local last = lastHours[key]
    lastHours[key] = now
    local budget = last and (math.max(0, math.min(now - last, 1)) + 0.02) or 0
    return {
        rain = clampNumber(args.rain, 0, budget),
        sweat = clampNumber(args.sweat, 0, budget),
        wetHours = clampNumber(args.wetHours, 0, budget),
    }
end

-- What the player's bags hold, for the sounds other players hear them make (see DSTB_Audio): sent to everybody when it
-- changes, and to a single player (`to`) who asks. Dedicated server / host only; in single player nobody else is there.
local sharedSound = {}   -- username -> the last amounts sent, as a string

local function soundArgs(player)
    local a = DSTB.Wet.spilledAmounts(player:getInventory())
    return {
        id = player:getOnlineID(), food = a.food, liquid = a.liquid, drink = a.drink,
        nfood = a.nested.food, nliquid = a.nested.liquid, ndrink = a.nested.drink,
    }
end

local function shareSound(player, to)
    if not isServer() then return end
    local args = soundArgs(player)
    if to then
        sendServerCommand(to, DSTB.MODULE, "soundState", args)
        return
    end
    local sig = string.format("%.2f|%.2f|%.2f|%.2f|%.2f|%.2f", args.food, args.liquid, args.drink, args.nfood, args.nliquid, args.ndrink)
    local key = player:getUsername()
    if sharedSound[key] == sig then return end
    sharedSound[key] = sig
    sendServerCommand(DSTB.MODULE, "soundState", args)
end

Commands.soundRequest = function(player)
    local online = getOnlinePlayers()
    for i = 0, online:size() - 1 do shareSound(online:get(i), player) end
end

Commands.motion = function(player, args)
    if type(args) ~= "table" then return end
    DSTB.Spill.applyEnvironment(player, sanitiseEnv(player, args))
    local exposure = sanitise(player, args)
    DSTB.Fizz.add(player, exposure)
    local events = DSTB.Spill.apply(player, exposure)
    if events then notify(player, "spilled", { events = events }) end
    shareSound(player)
end

-- The item an eat or drink action is working on is exempt from spilling until the action ends (see DSTB_Consuming).
Commands.consuming = function(player, args)
    if type(args) ~= "table" then return end
    local id = type(args.id) == "number" and args.id or nil
    DSTB.Spill.setConsuming(player, id)
    if id and args.hold == true then DSTB.Hands.holdForConsuming(player, player:getInventory():getItemWithIDRecursiv(id)) end
end

-- "Empty Spilled Contents": everything in the bag comes out onto the tile under the player and the
-- bag stops being soiled (it stays wet/dirty until it dries / is washed).
Commands.emptySpilled = function(player, args)
    if type(args) ~= "table" or type(args.id) ~= "number" then return end
    if player:getVehicle() then return end
    local inv = player:getInventory()
    local bag = DSTB.Spill.findBag(inv, args.id)
    if not bag or not DSTB.Wet.isSoiled(bag) then return end
    local square = player:getCurrentSquare()
    if not square then return end

    local bagInv = bag:getInventory()
    local ox = player:getX() - math.floor(player:getX())
    local oy = player:getY() - math.floor(player:getY())
    local oz = player:getZ() - math.floor(player:getZ())
    for i = bagInv:getItems():size() - 1, 0, -1 do
        local item = bagInv:getItems():get(i)
        bagInv:Remove(item)
        sendRemoveItemFromContainer(bagInv, item)
        local dropped = square:AddWorldInventoryItem(item, ox, oy, oz)
        if dropped and dropped:getWorldItem() then dropped:getWorldItem():transmitCompleteItemToClients() end
    end
    DSTB.Spill.scentEmptied(bag)
    DSTB.Wet.clearSoiled(player, bag)
    shareSound(player)
end

-- "Reseal Jar": the opened jar (Config.Reseal) becomes the closed jar again, with what is left in it, and takes a jar lid.
Commands.resealJar = function(player, args)
    if type(args) ~= "table" or type(args.id) ~= "number" or not DSTB.resealEnabled() then return end
    if player:getVehicle() then return end
    local inv = player:getInventory()
    local open = inv:getItemWithIDRecursiv(args.id)
    local closedType = open and Config.Reseal[open:getFullType()]
    if not closedType then return end
    local openFluid = open:getFluidContainer()   -- jars of juice are fluid containers, jars of food are Food
    if not (instanceof(open, "Food") or (openFluid and not openFluid:isEmpty())) then return end
    local lid = inv:getFirstTypeRecurse(Config.ResealLid)
    if not lid then return end

    local cont = open:getContainer()
    local closed = cont and cont:AddItem(closedType)
    if not closed then return end
    local md = closed:getModData()
    md.DSTB_resealed = true
    local closedFluid = closed:getFluidContainer()
    if openFluid and closedFluid then
        closedFluid:copyFluidsFrom(openFluid)   -- what is left in the jar, whatever it is by now; opening it again hands it back (see DSTB_ResealCraft)
    elseif instanceof(open, "Food") then
        -- What is left, kept on the closed jar and put back into the jar that opening it makes (the recipes that open jars do
        -- not all carry it over). The closed jar's own hunger is left alone: it decides how many uses the jar counts as.
        md.DSTB_left = {
            hung = open:getHungChange(), thirst = open:getThirstChangeUnmodified(), cal = open:getCalories(),
            carb = open:getCarbohydrates(), lip = open:getLipids(), prot = open:getProteins(),
        }
        -- The closed jar's card shows what is left too (hunger only where the jar has any of its own, see above).
        if instanceof(closed, "Food") then
            if closed:getBaseHunger() ~= 0 then closed:setHungChange(md.DSTB_left.hung) end
            if closed:getThirstChangeUnmodified() ~= 0 then closed:setThirstChange(md.DSTB_left.thirst) end
            closed:setCalories(md.DSTB_left.cal)
            closed:setCarbohydrates(md.DSTB_left.carb)
            closed:setLipids(md.DSTB_left.lip)
            closed:setProteins(md.DSTB_left.prot)
        end
    end
    if instanceof(closed, "Food") and instanceof(open, "Food") then
        closed:setAge(open:getAge() / math.max(1, open:getOffAgeMax()) * closed:getOffAgeMax())   -- it has spoiled as far along as the open one had
    end
    md.LidCondition = lid:getCondition()   -- opening it again hands the lid back in this condition (RecipeCodeOnCreate.applyLidCondition)
    cont:Remove(open)
    sendRemoveItemFromContainer(cont, open)
    local lidCont = lid:getContainer()
    lidCont:Remove(lid)
    sendRemoveItemFromContainer(lidCont, lid)
    sendAddItemToContainer(cont, closed)
    syncItemFields(player, closed)
    syncItemModData(player, closed)
    shareSound(player)
end

-- Debug helpers: admins in MP, anyone in single player.
local function debugAllowed(player)
    if isServer() then
        local role = player:getRole()   -- B42 roles: the name is lowercase ("admin"), so test the capability instead
        return role ~= nil and role:hasCapability(Capability.AddItem)
    end
    return true
end

-- Debug: marks a bag the player wears (else any bag they carry) as spilled in, with these amounts (food, liquid, drink).
Commands.debugSoil = function(player, args)
    if not debugAllowed(player) or type(args) ~= "table" then return end
    local bag = player:getClothingItem_Back()
    if not bag then
        local items = player:getInventory():getItems()
        for i = 0, items:size() - 1 do
            if instanceof(items:get(i), "InventoryContainer") then bag = items:get(i); break end
        end
    end
    if not bag then return end
    local md = bag:getModData()
    md.DSTB_amtFood, md.DSTB_amtLiquid, md.DSTB_amtDrink = clampNumber(args.food, 0, 50), clampNumber(args.liquid, 0, 50), clampNumber(args.drink, 0, 50)
    md.DSTB_smelly = md.DSTB_amtLiquid > 0 or nil   -- the debug liquid is not water
    DSTB.Wet.markSoiled(player, bag)
    shareSound(player)
end

-- Debug: the spilled contents of the worn bag (else any soiled bag carried) go off at once.
Commands.debugSour = function(player)
    if not debugAllowed(player) then return end
    local bag = player:getClothingItem_Back()
    if not (bag and DSTB.Wet.isSoiled(bag)) then
        bag = nil
        local items = player:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if instanceof(item, "InventoryContainer") and DSTB.Wet.isSoiled(item) then bag = item; break end
        end
    end
    if bag then DSTB.Wet.makeSour(player, bag) end
end

-- Gives one item. args: type (full type), litres + fluid (Water/Petrol/Bleach) to fill a fluid container,
-- freeze = true to freeze it, hot = true to make it piping hot, remaining = fraction (0-1) of a food's nutrition still left (a bitten food).
local DEBUG_FLUIDS = { Water = Fluid.Water, Petrol = Fluid.Petrol, Bleach = Fluid.Bleach }

Commands.debugGive = function(player, args)
    if not debugAllowed(player) then return end
    if type(args) ~= "table" or type(args.type) ~= "string" then return end
    if not getScriptManager():FindItem(args.type) then return end
    local inv = player:getInventory()
    local item = inv:AddItem(args.type)
    if not item then return end

    local fc = item:getFluidContainer()
    local litres = clampNumber(args.litres, 0, 100)
    if fc and litres > 0 then fc:addFluid(DEBUG_FLUIDS[args.fluid] or Fluid.Water, litres) end
    if fc and type(args.fraction) == "number" then   -- a drink that spawns full, drunk down to this share of its capacity
        fc:adjustAmount(fc:getCapacity() * clampNumber(args.fraction, 0, 1))
    end

    if instanceof(item, "Food") then
        local remaining = clampNumber(args.remaining, 0, 1)
        if args.remaining and remaining < 1 then item:setHungChange(item:getHungChange() * remaining) end
        if args.freeze then
            item:setFrozen(true)
            item:setFreezingTime(100)
        end
    elseif args.freeze and fc then
        item:setItemHeat(0.2)   -- the floor vanilla uses in a freezer: DSTB treats it as frozen
    end
    if args.hot then
        if instanceof(item, "Food") then item:setHeat(3.0) else item:setItemHeat(3.0) end   -- 3 = the hottest an item gets
    end
    sendAddItemToContainer(inv, item)
end

-- Debug: puts test cargo into the vehicle nearest the player (within 8 tiles): a mug of water and an apple in the trunk,
-- a mug in the front passenger seat, and a duffel bag with a mug in the trunk. The vehicle is also repaired and refuelled.
local function addToContainer(container, fullType, litres)
    local item = container:AddItem(fullType)
    if not item then return nil end
    if litres then item:getFluidContainer():addFluid(Fluid.Water, litres) end
    sendAddItemToContainer(container, item)
    return item
end

-- Repairs and refuels a vehicle, then fills it with the test cargo.
local function prepareVehicle(vehicle)
    vehicle:repair()
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part:getId() == "GasTank" then
            part:setContainerContentAmount(part:getContainerCapacity())
            vehicle:transmitPartModData(part)
        end
        local container = part:getItemContainer()
        if container then
            local id = part:getId()
            if id == "TruckBed" then
                addToContainer(container, "Base.MugWhite", 0.2)
                addToContainer(container, "Base.Apple")
                local bag = addToContainer(container, "Base.Bag_DuffelBag")
                if bag then addToContainer(bag:getInventory(), "Base.MugWhite", 0.2) end
            elseif id == "SeatFrontRight" then
                addToContainer(container, "Base.MugWhite", 0.2)
            end
        end
    end
end

-- Debug stress test: fills the inventory with a big mixed load (six bags with about 50 things each, three nested plastic
-- bags in every one, and 60 loose items), then times each server-side pass over it. Items are only added, never
-- removed, so run it on a throwaway character.
local STRESS_STUFF = {
    { "Base.MugWhite", 0.2 }, { "Base.Apple" }, { "Base.Bread" }, { "Base.TinnedSoupOpen" }, { "Base.Crisps" },
    { "Base.WaterBottle", 0.5 }, { "Base.Pencil" }, { "Base.Nails" }, { "Base.Hammer" }, { "Base.BeerCan", 0.1 },
}

local function stressItems(container, count)
    local i = 0
    while i < count do
        local def = STRESS_STUFF[i % #STRESS_STUFF + 1]
        if getScriptManager():FindItem(def[1]) then addToContainer(container, def[1], def[2]) end
        i = i + 1
    end
end

local function countItems(container)
    local n, items = 0, container:getItems()
    for i = 0, items:size() - 1 do
        n = n + 1
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then n = n + countItems(item:getInventory()) end
    end
    return n
end

local function timeIt(label, runs, fn)
    local t0 = getTimestampMs()
    for _ = 1, runs do fn() end
    return string.format("%s: %.3f ms", label, (getTimestampMs() - t0) / runs)
end

Commands.debugStress = function(player, args)
    if not debugAllowed(player) then return end
    local inv = player:getInventory()
    for _, bagType in ipairs({ "Base.Bag_ALICEpack", "Base.Bag_DuffelBag", "Base.Bag_Schoolbag", "Base.Bag_BigHikingBag", "Base.Bag_ALICEpack", "Base.Bag_DuffelBag" }) do
        local bag = addToContainer(inv, bagType)
        if bag then
            stressItems(bag:getInventory(), 25)
            for _ = 1, 3 do
                local inner = addToContainer(bag:getInventory(), "Base.Plasticbag")
                if inner then stressItems(inner:getInventory(), 8) end
            end
        end
    end
    stressItems(inv, 60)

    local runs = 100
    local lines = { string.format("%d items carried", countItems(inv)) }
    lines[#lines + 1] = timeIt("collect candidates", runs, function() DSTB.Spill.collectCandidates(player) end)
    lines[#lines + 1] = timeIt("full spill pass (a few seconds of walking)", runs, function() DSTB.Spill.apply(player, { walk = 0.01 }) end)
    lines[#lines + 1] = timeIt("ten-minute pass (settle scent, seep, contaminate)", runs, function()
        DSTB.Spill.settleScent(player)
        DSTB.Spill.seep(player, 0)
        DSTB.Spill.contaminateAll(player)
    end)
    lines[#lines + 1] = timeIt("client scent sum", runs, function() DSTB.Spill.playerScent(player) end)
    for _, line in ipairs(lines) do print("[DontSpillTheBeans] stress: " .. line) end
    notify(player, "debugStress", { lines = lines })
end

Commands.debugVehicleCargo = function(player, args)
    if not debugAllowed(player) then return end
    local best, bestD = nil, 8 * 8
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        local dx, dy = v:getX() - player:getX(), v:getY() - player:getY()
        local d = dx * dx + dy * dy
        if d < bestD then best, bestD = v, d end
    end
    if best then prepareVehicle(best) end
    notify(player, "debugCargo", { ok = best ~= nil })
end

-- Debug: two prepared cars in a line, facing east, the second one just behind the first, ready for the vanilla
-- "attach trailer" vehicle-menu option (drive the front car back until the bumpers are close).
Commands.debugTowPair = function(player, args)
    if not debugAllowed(player) then return end
    local x, y, z = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    local cell = getCell()
    local made = 0
    for _, dx in ipairs({ 10, 4 }) do   -- the front car first, the one to be towed behind it
        local square = cell:getGridSquare(x + dx, y, z)
        if square then
            local v = addVehicleDebug("Base.CarNormal", IsoDirections.E, nil, square)
            if v then
                prepareVehicle(v)
                made = made + 1
            end
        end
    end
    notify(player, "debugCargo", { ok = made == 2 })
end

-- Vehicle probe (debug): while on, every vehicle that moves (by its reported speed OR by how far it actually travelled)
-- is logged with both numbers, who is aboard and what tows it, so we can see where the server's speed reading is wrong.
local probeOn = false
local probePos = {}   -- vehicle id -> { x, y, ms }

Commands.debugVehicleProbe = function(player, args)
    if not debugAllowed(player) then return end
    probeOn = not probeOn
    probePos = {}
    print("[DontSpillTheBeans] vehicle probe " .. (probeOn and "ON" or "OFF"))
    notify(player, "debugProbe", { on = probeOn })
end

local function probeVehicles()
    local cell = getCell()
    local vehicles = cell and cell:getVehicles()
    if not vehicles then return end
    local now = getTimestampMs()
    local it = vehicles:iterator()
    while it:hasNext() do
        local v = it:next()
        local id = v:getId()
        local prev = probePos[id]
        local x, y = v:getX(), v:getY()
        probePos[id] = { x = x, y = y, ms = now }
        if prev and now > prev.ms then
            local metres = math.sqrt((x - prev.x) ^ 2 + (y - prev.y) ^ 2)
            local posKmh = metres / ((now - prev.ms) / 1000) * 3.6
            local speed = v:getCurrentSpeedKmHour()
            if math.abs(speed) >= 1 or posKmh >= 1 then
                local riders = 0
                for seat = 0, v:getMaxPassengers() - 1 do
                    if v:getCharacter(seat) then riders = riders + 1 end
                end
                local towedBy = v:getVehicleTowedBy()
                print(string.format("[DontSpillTheBeans] probe %s id=%d reported=%.1f km/h moved=%.1f km/h riders=%d towedBy=%s towing=%s",
                    tostring(v:getScriptName()), id, speed, posKmh, riders,
                    towedBy and tostring(towedBy:getId()) or "-", v:getVehicleTowing() and tostring(v:getVehicleTowing():getId()) or "-"))
            end
        end
    end
end

-- Debug: sets the player's fizz shake to full (value 1) or calm (0).
Commands.debugShake = function(player, args)
    if not debugAllowed(player) then return end
    DSTB.Fizz.set(player, clampNumber(args and args.value, 0, 1))
    notify(player, "debugShake", { value = clampNumber(args and args.value, 0, 1) })
end

-- Debug: sets hunger and thirst (0 to 1). A bottle of plain water only offers Drink while the character is thirsty.
Commands.debugNeeds = function(player, args)
    if not debugAllowed(player) or type(args) ~= "table" then return end
    local stats = player:getStats()
    if args.thirst ~= nil then stats:set(CharacterStat.THIRST, clampNumber(args.thirst, 0, 1)) end
    if args.hunger ~= nil then stats:set(CharacterStat.HUNGER, clampNumber(args.hunger, 0, 1)) end
end

Commands.debugMultiplier = function(player, args)
    if not debugAllowed(player) then return end
    DSTB.debugMultiplier = clampNumber(args and args.value, 0, 100)
    notify(player, "debugMultiplier", { value = DSTB.debugMultiplier })
end

local function onClientCommand(module, command, player, args)
    if module ~= DSTB.MODULE then return end
    local handler = Commands[command]
    if handler then handler(player, args) end
end

Events.OnClientCommand.Add(onClientCommand)

-- Every ten in-game minutes: dry wet bags, and let worn spilled-in bags seep into clothing.
local function onEveryTenMinutes()
    local function tick(p)
        DSTB.Wet.refresh(p)
        DSTB.Spill.settleScent(p)
        local scalded = DSTB.Spill.seep(p, 10)
        if scalded then notify(p, "scalded", { bags = scalded }) end
        DSTB.Spill.contaminateAll(p)
    end
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do tick(players:get(i)) end
    else
        local p = getPlayer()
        if p then tick(p) end
    end
end

Events.EveryTenMinutes.Add(onEveryTenMinutes)
Events.EveryOneMinute.Add(function() DSTB.Washer.update(1) end)

-- Vehicles: the server watches them itself (about once a second) rather than trusting client-reported speed.
local VEHICLE_TICK_MS = 1000
local lastVehicleTickMs
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if lastVehicleTickMs and now - lastVehicleTickMs < VEHICLE_TICK_MS then return end
    local dt = lastVehicleTickMs and math.min((now - lastVehicleTickMs) / 1000, Config.MaxReportSec) or 0
    lastVehicleTickMs = now
    if dt <= 0 then return end
    if probeOn then probeVehicles() end

    local players = {}
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do players[#players + 1] = online:get(i) end
    else
        local p = getPlayer()
        if p then players[1] = p end
    end
    if #players == 0 then return end

    local report = DSTB.Spill.vehicleTick(dt, players)
    if report then
        for player, events in pairs(report) do notify(player, "spilled", { events = events }) end
    end
end)
