-- Playtest-only helper (lives in scripts/playtest-mod, linked into the isolated playtest instance by launch-playtest.ps1,
-- never shipped). Launches Patrick's Debug Scenario straight from the main menu and sets up a Don't Spill the Beans
-- vehicle test: mugs of water in a worn pack, the trunk, a seat and a bag in the trunk, the spill rate x10 and the
-- vehicle probe on. Enter the car, drive, and watch the console and the probe lines.

local MODULE = "DontSpillTheBeans"

local function nearestVehicle(player)
    local best, bestD
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        local dx, dy = v:getX() - player:getX(), v:getY() - player:getY()
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then best, bestD = v, d end
    end
    return best
end

local function mug(container, litres)
    local item = container:AddItem("Base.MugWhite")
    item:getFluidContainer():addFluid(Fluid.Water, litres)
    return item
end

local function setup()
    local p = getPlayer()
    local inv = p:getInventory()

    -- Carried: a worn backpack with a mug of water and an apple in it.
    local pack = inv:AddItem("Base.Bag_ALICEpack")
    p:setWornItem(pack:getBodyLocation(), pack)
    mug(pack:getInventory(), 0.2)
    pack:getInventory():AddItem("Base.Apple")

    -- Cargo: loose mug and apple in the trunk, a mug in the front passenger seat, and a duffel bag with a mug in the trunk.
    local car = nearestVehicle(p)
    if car then
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            local container = part:getItemContainer()
            if container then
                local id = part:getId()
                if id == "TruckBed" then
                    mug(container, 0.2)
                    container:AddItem("Base.Apple")
                    mug(container:AddItem("Base.Bag_DuffelBag"):getInventory(), 0.2)
                elseif id == "SeatFrontRight" then
                    mug(container, 0.2)
                end
            end
        end
    else
        print("[DSTBPlaytest] no vehicle found near the player")
    end

    sendClientCommand(p, MODULE, "debugMultiplier", { value = 10 })
    sendClientCommand(p, MODULE, "debugVehicleProbe", {})
    print("[DSTBPlaytest] vehicle test set up")
end

local scenario = debugScenarios and debugScenarios.PatrickScenario
if scenario then
    local original = scenario.onStart
    scenario.forceLaunch = true
    scenario.onStart = function()
        if original then original() end
        local ok, err = pcall(setup)
        if not ok then print("[DSTBPlaytest] setup failed: " .. tostring(err)) end
    end
    pcall(function() getDebugOptions():setBoolean("DebugScenario.ForceLaunch", true) end)
else
    print("[DSTBPlaytest] Patrick's Debug Scenario not found")
end
