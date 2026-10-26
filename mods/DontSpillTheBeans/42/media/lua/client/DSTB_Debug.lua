-- Playtest helpers, only active when the game runs with -debug. Adds a "DSTB (debug)" world context menu.
-- "Give item" lists one entry per test case; entries for items that are not installed are left out.

require "DSTB_Config"
require "DSTB_Audio"

local DSTB = DontSpillTheBeans

-- { label, type, [litres], [fluid], [freeze], [hot], [remaining] }
local KIT = {
    { "Liquid containers (filled with water)", {
        { "Mug, 0.2 L  (open: spills)", "Base.MugWhite", litres = 0.2 },
        { "Glass tumbler, 0.2 L  (open: spills)", "Base.GlassTumbler", litres = 0.2 },
        { "Bowl, 0.3 L  (open: spills)", "Base.Bowl", litres = 0.3 },
        { "Water bottle, full  (sealed: never spills)", "Base.WaterBottle", litres = 1.0 },
        { "Beer can, full  (sealed while full; with Vessel Fixes: sealed until opened, then spills)", "Base.BeerCan", litres = 0.3 },
        { "Beer can, part full  (spills; with Vessel Fixes it is opened first)", "Base.BeerCan", litres = 0.1 },
        { "Mug of petrol, 0.2 L  (wets and dirties)", "Base.MugWhite", litres = 0.2, fluid = "Petrol" },
        { "Mug of bleach, 0.2 L  (wets and dirties)", "Base.MugWhite", litres = 0.2, fluid = "Bleach" },
        { "Mug, frozen  (frozen liquid: never spills)", "Base.MugWhite", litres = 0.2, freeze = true },
        { "Water bottle, part full", "Base.WaterBottle", litres = 0.5 },
        { "Water bottle, part full, frozen", "Base.WaterBottle", litres = 0.5, freeze = true },
    } },
    { "Food: spills (loose in a bag)", {
        { "Apple  (crushed)", "Base.Apple" },
        { "Apple, frozen  (solid: never spills while frozen)", "Base.Apple", freeze = true },
        { "Bread", "Base.Bread" },
        { "Pasta bowl  (not liquid: food rates, \"Crushed\")", "Base.PastaBowl" },
        { "Rice bowl  (not liquid)", "Base.RiceBowl" },
        { "Salad  (not liquid)", "Base.Salad" },
    } },
    { "Liquid foods (liquid spill rates, food stain, \"Spills\")", {
        { "Soup in a bowl", "Base.SoupBowl" },
        { "Stew", "Base.StewBowl" },
        { "Open tin of soup  (0.5 L estimate)", "Base.TinnedSoupOpen" },
        { "Bucket of soup  (0.8 L: wets a lot)", "Base.BucketOfSoup" },
        { "Oatmeal", "Base.Oatmeal" },
        { "Cup of tea (white mug)", "Base.HotDrinkWhite" },
        { "Cup of tea (teacup)", "Base.HotDrinkTea" },
        { "Cup of tea (ceramic teacup)", "Base.HotDrinkTeaCeramic" },
        { "Hot drink in a tumbler", "Base.HotDrinkTumbler" },
        { "Soup, half eaten  (half the volume)", "Base.SoupBowl", remaining = 0.5 },
    } },
    { "Hot (burns when spilled from something worn)", {
        { "Mug of hot water, 0.2 L  (open liquid)", "Base.MugWhite", litres = 0.2, hot = true },
        { "Cup of hot tea  (liquid food)", "Base.HotDrinkWhite", hot = true },
        { "Hot soup in a bowl  (liquid food)", "Base.SoupBowl", hot = true },
        { "Hot open tin of soup  (liquid food)", "Base.TinnedSoupOpen", hot = true },
        { "Hot bucket of soup", "Base.BucketOfSoup", hot = true },
        { "Hot apple  (crushed: burns too)", "Base.Apple", hot = true },
        { "Water bottle, hot  (sealed: never spills)", "Base.WaterBottle", litres = 0.5, hot = true },
    } },
    { "Carbonated (foam over when opened after exercise)", {
        { "Diet cola can, full", "Base.Pop" },
        { "Cola can, full", "Base.Pop2" },
        { "Soda can, full", "Base.Pop3" },
        { "Soda can (random), full", "Base.SodaCan" },
        { "Soda bottle (2 L), full", "Base.PopBottle" },
        { "Beer can, full", "Base.BeerCan" },
        { "Beer bottle, full", "Base.BeerBottle" },
        { "Champagne, full", "Base.Champagne" },
        { "Cider, full", "Base.Cider" },
        { "Cola can, half drunk  (no foam: already open)", "Base.Pop2", fraction = 0.5 },
        { "Water bottle, full  (not carbonated: no foam)", "Base.WaterBottle", litres = 1.0 },
        { "Juice, full  (not carbonated)", "Base.JuiceOrange" },
    } },
    { "Food: exempt", {
        { "Crisps, whole  (exempt while 100%)", "Base.Crisps" },
        { "Crisps, bitten  (no longer exempt)", "Base.Crisps", remaining = 0.5 },
        { "Heart box of chocolates  (always exempt)", "Base.Chocolate_HeartBox" },
        { "Chocolate bar, whole  (exempt while 100%)", "Base.Chocolate" },
        { "Chocolate bar, bitten  (no longer exempt)", "Base.Chocolate", remaining = 0.5 },
        { "Granola bar, whole  (exempt while 100%)", "Base.GranolaBar" },
        { "Granola bar, bitten", "Base.GranolaBar", remaining = 0.5 },
        { "Closed can of soup  (exempt by rule)", "Base.TinnedSoup" },
        { "Hot dog buns  (no treatment)", "Base.BunsHotdog" },
    } },
    { "Jars (Reseal Jar needs a jar lid)", {
        { "Jar lid", "Base.JarLid" },
        { "Vanilla: tomato jar, closed  (never spills)", "Base.CannedTomato" },
        { "Vanilla: tomato jar, opened  (open the closed one to compare)", "Base.CannedTomato_Open" },
        { "Vanilla: tomato jar, opened and half eaten", "Base.CannedTomato_Open", remaining = 0.5 },
        { "LTPE: avocado spread, closed", "Base.AvocadoSpread" },
        { "LTPE: avocado spread, opened", "Base.AvocadoSpread_Open" },
        { "LTPE: pemmican jar, closed", "Base.CannedPemmican" },
        { "LTPE: pemmican jar, opened and half eaten", "Base.CannedPemmican_Open", remaining = 0.5 },
        { "LTPE: apple juice jar, closed  (sealed fluid jar)", "LTPE.JuicedAppleJar" },
        { "LTPE: apple juice jar, opened  (full)", "LTPE.JuicedAppleJar_Open" },
        { "LTPE: apple juice jar, opened and half drunk", "LTPE.JuicedAppleJar_Open", fraction = 0.5 },
        { "LTPE: apple juice jar, opened, holding water  (reseal with another liquid)", "LTPE.JuicedAppleJar_Open", litres = 0.5, fluid = "Water", fraction = 0.5 },
        { "VFE: black olives, closed", "VFX.JarBlackOlives" },
        { "VFE: black olives, opened and half eaten", "VFX.JarBlackOlivesOpen", remaining = 0.5 },
        { "VFE: marinara sauce, closed", "VFX.HomemadeMarinara" },
        { "VFE: marinara sauce, opened", "VFX.HomemadeMarinara_Open" },
        { "VFE: marinara sauce, opened and half eaten", "VFX.HomemadeMarinara_Open", remaining = 0.5 },
    } },
    { "Tins (opened ones are held while eaten from; opening needs a tin opener)", {
        { "Tin opener", "Base.TinOpener" },
        { "Vanilla: tin of soup, closed  (exempt by rule)", "Base.TinnedSoup" },
        { "Vanilla: tin of soup, opened  (open the closed one to compare)", "Base.TinnedSoupOpen" },
        { "Vanilla: tin of soup, opened and half eaten", "Base.TinnedSoupOpen", remaining = 0.5 },
        { "Vanilla: tuna tin, closed", "Base.TunaTin" },
        { "Vanilla: tuna tin, opened and half eaten", "Base.TunaTinOpen", remaining = 0.5 },
        { "Vanilla: tin of beans, closed", "Base.TinnedBeans" },
        { "Vanilla: sardines, closed  (opens by hand: no tool)", "Base.CannedSardines" },
        { "VFE: savoury mince tin, closed  (opened by the game's recipe, patched by VFE)", "VFX.CannedSavoryMince" },
        { "VFE: savoury mince tin, opened and half eaten", "VFX.CannedSavoryMinceOpen", remaining = 0.5 },
        { "Wesch's empty cans: beans can, empty  (what an eaten tin of beans leaves; open container)", "Base.EmptyCanBeans" },
        { "Wesch's empty cans: beans can, half full of water  (spills)", "Base.EmptyCanBeans", litres = 0.15 },
        { "Wesch's empty cans: beans can, full of water  (spills)", "Base.EmptyCanBeans", litres = 0.3 },
        { "Wesch's empty cans: tuna tin, empty", "Base.EmptyTunaTin" },
        { "Wesch's empty cans: tuna tin, half full of water", "Base.EmptyTunaTin", litres = 0.075 },
        { "Wesch's empty cans: tuna tin, full of water", "Base.EmptyTunaTin", litres = 0.15 },
    } },
    { "Cans and bottles that are opened first (held while drunk from)", {
        { "Bottle opener", "Base.BottleOpener" },
        { "Corkscrew", "Base.Corkscrew" },
        { "Vanilla: beer bottle, sealed  (needs a bottle opener)", "Base.BeerBottle" },
        { "Vanilla: beer bottle, part drunk", "Base.BeerBottle", fraction = 0.5 },
        { "Vanilla: wine bottle, sealed  (needs a corkscrew)", "Base.Wine" },
        { "VFE: orange soda can, sealed  (opens by hand: Open and Drink)", "VFX.OrangeSodaCan" },
        { "VFE: orange soda can, part drunk", "VFX.OrangeSodaCan", fraction = 0.5 },
        { "Pomp's: Brawndo can, sealed  (greyed Drink until opened from the craft menu)", "PompsItems.Brawndo" },
        { "Authentic Z: cola can, sealed", "AuthenticZClothing.Pop2" },
        { "Vanilla: cola can  (sealed only with Vessel Fixes; otherwise drinks directly)", "Base.Pop2" },
        { "Vanilla: cola can, part drunk  (already open)", "Base.Pop2", fraction = 0.5 },
        { "Vanilla: beer can  (Vessel Fixes: sealed)", "Base.BeerCan" },
        { "Vanilla: aged wine, sealed  (Vessel Fixes: can be opened; needs a corkscrew)", "Base.WineAged" },
        { "Vanilla: milk carton, 1 L  (Vessel Fixes: sealed)", "Base.Milk" },
        { "Vanilla: milk carton, personal size  (Vessel Fixes: sealed)", "Base.Milk_Personalsized" },
        { "Vanilla: chocolate milk carton  (Vessel Fixes: sealed)", "Base.MilkChocolate_Personalsized" },
        { "Vanilla: juice box, grape  (Vessel Fixes: sealed)", "Base.JuiceBox" },
        { "Vanilla: juice box, apple  (Vessel Fixes: sealed)", "Base.JuiceBoxApple" },
        { "Vanilla: juice box, fruit punch  (Vessel Fixes: sealed)", "Base.JuiceBoxFruitpunch" },
        { "Vanilla: juice box, orange  (Vessel Fixes: sealed)", "Base.JuiceBoxOrange" },
        { "Vanilla: juice box, half drunk  (already open)", "Base.JuiceBox", fraction = 0.5 },
        { "Water bottle, full  (sealed: never held; Drink only shows while thirsty, see the menu above)", "Base.WaterBottle", litres = 1.0 },
    } },
    { "Bags and containers", {
        { "Backpack (ALICE)  (plain: liquids spill through)", "Base.Bag_ALICEpack" },
        { "Duffel bag  (plain)", "Base.Bag_DuffelBag" },
        { "Schoolbag  (plain)", "Base.Bag_Schoolbag" },
        { "Big hiking bag  (plain)", "Base.Bag_BigHikingBag" },
        { "Plastic bag  (protective)", "Base.Plasticbag" },
        { "Lunchbox  (protective)", "Base.Lunchbox" },
        { "Cooler  (protective)", "Base.Cooler" },
    } },
    { "Clothing (seepage, in order)", {
        { "Jeans (pants)", "Base.Trousers_Denim" },
        { "Underpants", "Base.Underpants_White" },
        { "Ankle socks", "Base.Socks_Ankle" },
        { "Shoes", "Base.Shoes_Black" },
        { "T-shirt", "Base.Tshirt_DefaultTEXTURE" },
        { "Denim shirt", "Base.Shirt_Denim" },
        { "Jumper", "Base.Jumper_RoundNeck" },
        { "Jacket", "Base.Jacket_Black" },
        { "Bandana (hat)", "Base.Hat_Bandana" },
        { "Dress  (placed by coverage)", "Base.Dress_Normal" },
        { "Leather gloves  (hands: first for foam)", "Base.Gloves_LeatherGloves" },
        { "Bulletproof vest  (torso, outermost)", "Base.Vest_BulletCivilian" },
        { "Robe  (jacket rank)", "Base.BlackRobe" },
        { "Formal shirt  (long sleeve)", "Base.Shirt_FormalWhite" },
        { "Sport T-shirt  (short sleeve)", "Base.Tshirt_Sport" },
        { "Tank top", "Base.Vest_DefaultTEXTURE" },
        { "Bra  (underwear top)", "Base.Bra_Strapless_White" },
        { "Shorts", "Base.Shorts_ShortSport" },
        { "Long skirt", "Base.Skirt_Normal" },
        { "Long socks", "Base.Socks_Long" },
        { "Baseball cap", "Base.Hat_BaseballCap" },
        { "Scarf", "Base.Scarf_White" },
        { "Bandana mask", "Base.Hat_RagBandanaMask" },
        { "Glasses", "Base.Glasses_Normal" },
        { "Boilersuit  (coverage)", "Base.Boilersuit" },
    } },
    { "Washer and dryer", {
        { "Bath towel  (wettable)", "Base.BathTowel" },
        { "Sandbag  (cannot get wet)", "Base.Sandbag" },
    } },
    { "Mod: Vanilla Foods Expanded", {
        { "Homemade jam  (always exempt)", "Base.VFXHomemadeJam" },
        { "Arborio rice  (exempt while 100%)", "VFX.ArborioRice" },
        { "Rice, bitten", "VFX.ArborioRice", remaining = 0.5 },
        { "Milkshake glass, 0.2 L  (open)", "VFX.MilkshakeGlass", litres = 0.2 },
        { "Cherry cola bottle, 0.3 L  (sealed)", "VFX.CherryColaBottle", litres = 0.3 },
        { "Banana milk, part full  (spills)", "VFX.BananaMilk", litres = 0.1 },
        { "Spice rack, small  (plain bag)", "VFX.SpiceRackSmallDark" },
    } },
    { "Mod: Pomp's Items", {
        { "Chocolate rabbit  (always exempt)", "PompsItems.ChocolateRabbit" },
        { "Bitters bar  (exempt while 100%)", "PompsItems.BittersBar" },
        { "Bitters bar, bitten", "PompsItems.BittersBar", remaining = 0.5 },
        { "Bottled green tea, 0.3 L  (sealed)", "PompsItems.PIBottledTeaGreenTea", litres = 0.3 },
        { "Brawndo, full  (sealed while full; with the Pomp's add-on: sealed until opened, then spills)", "PompsItems.Brawndo", litres = 0.3 },
        { "Brawndo, part full  (spills)", "PompsItems.Brawndo", litres = 0.1 },
    } },
    { "Mod: Sapph's Cooking", {
        { "Beef broth  (always exempt)", "SapphCooking.BeefBroth" },
        { "Arborio rice  (exempt while 100%)", "SapphCooking.ArborioRice" },
        { "Rice, bitten", "SapphCooking.ArborioRice", remaining = 0.5 },
        { "Cocktail glass, 0.1 L  (open)", "SapphCooking.CocktailGlass", litres = 0.1 },
        { "Bottle of apple juice, 0.3 L  (sealed)", "SapphCooking.BottleofAppleJuice", litres = 0.3 },
        { "Energy drink, full  (sealed while full; with the Sapph add-on: sealed until opened, then spills)", "SapphCooking.EnergyDrink", litres = 0.3 },
        { "Energy drink, part full  (spills)", "SapphCooking.EnergyDrink", litres = 0.1 },
        { "Chef apron  (plain bag)", "SapphCooking.Apron_Chef_Camo" },
    } },
    { "Mod: MRE", {
        { "MRE meal  (always exempt)", "bdtmre.bdtmre26a1" },
        { "MRE box A  (plain bag)", "bdtmre.bdtmreboxa" },
    } },
}

local function give(player, entry)
    sendClientCommand(player, DSTB.MODULE, "debugGive", {
        type = entry[2], litres = entry.litres, fraction = entry.fraction, fluid = entry.fluid, freeze = entry.freeze, remaining = entry.remaining, hot = entry.hot,
    })
end

-- A rolling push is spread over about two seconds: one big hit reads as a crash to the car (it gets damaged).
local ROLL_TICKS = 120
local rolls = {}   -- list of { vehicle, perTick, left }

function DSTB.startRoll(vehicle, total)
    rolls[#rolls + 1] = { vehicle = vehicle, perTick = total / ROLL_TICKS, left = ROLL_TICKS }
end

Events.OnTick.Add(function()
    for i = #rolls, 1, -1 do
        local r = rolls[i]
        local v = r.vehicle
        local f = v:getForwardVector(Vector3f.new())
        -- Bullet space: x, up, z. Applied at the centre, so it pushes without spinning or tipping the car.
        v:applyImpulseGeneric(v:getX(), v:getY(), v:getZ(), f:x(), f:z(), 0, r.perTick)
        r.left = r.left - 1
        if r.left <= 0 then table.remove(rolls, i) end
    end
end)

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test or not isDebugEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(context:addOption("DSTB (debug)"), sub)

    local giveMenu = ISContextMenu:getNew(sub)
    sub:addSubMenu(sub:addOption("Give item"), giveMenu)
    for _, group in ipairs(KIT) do
        local list = ISContextMenu:getNew(giveMenu)
        local count = 0
        for _, entry in ipairs(group[2]) do
            if getScriptManager():FindItem(entry[2]) then
                list:addOption(entry[1], player, give, entry)
                count = count + 1
            end
        end
        if count > 0 then
            giveMenu:addSubMenu(giveMenu:addOption(group[1]), list)
        else
            local opt = giveMenu:addOption(group[1] .. "  (none installed: enable the mod on this save)")
            opt.notAvailable = true
        end
    end

    if isClient() then
        -- Multiplayer has no debug scenarios: admin chat commands do the same job.
        sub:addOption("Teleport to the test highway (admin)", player, function()
            SendCommandToServer("/teleportto 10601,8834,0")
        end)
        sub:addOption("Spawn a car next to me (admin)", player, function()
            SendCommandToServer("/addvehicle Base.CarNormal")
        end)
    end
    sub:addOption("Add test cargo to the nearest vehicle, repaired and refuelled (mugs, apple, duffel bag)", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugVehicleCargo", {})
    end)
    sub:addOption("Spawn two prepared cars in a line for towing (east of me)", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugTowPair", {})
    end)
    for _, strength in ipairs({ 60000, 250000, 1000000 }) do
        sub:addOption("Roll the nearest vehicle forward, total push " .. strength .. " (rolling empty car test)", player, function(p)
            local best, bestD = nil, 10 * 10
            local it = getCell():getVehicles():iterator()
            while it:hasNext() do
                local v = it:next()
                local dx, dy = v:getX() - p:getX(), v:getY() - p:getY()
                local d = dx * dx + dy * dy
                if d < bestD then best, bestD = v, d end
            end
            if best then DSTB.startRoll(best, strength) end
        end)
    end
    sub:addOption("Toggle vehicle probe (logs speed readings)", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugVehicleProbe", {})
    end)
    sub:addOption("Stress test: add ~380 items and time the spill passes (use a throwaway character)", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugStress", {})
    end)
    local sounds = ISContextMenu:getNew(sub)
    sub:addSubMenu(sub:addOption("Sounds"), sounds)
    for _, name in ipairs({ "Burn", "FoamOver", "EmptyBase", "EmptyDry", "EmptyLiquid", "EmptyWet" }) do
        sounds:addOption("Play " .. name, player, function(p) DSTB.Audio.event(p, name) end)
    end
    for _, spill in ipairs({
        { "dry food (crushed)", { food = 1.5 } }, { "liquid", { liquid = 0.4 } }, { "liquid food", { drink = 1 } },
        { "a little of everything", { food = 0.3, liquid = 0.1, drink = 0.3 } }, { "everything, a lot", { food = 2, liquid = 0.5, drink = 1.5 } },
    }) do
        sounds:addOption("Spill " .. spill[1] .. " into my worn bag (walk to hear it)", player, function(p)
            sendClientCommand(p, DSTB.MODULE, "debugSoil", spill[2])
        end)
    end
    sub:addOption("Make the spilled contents of my bag go off (bad smell)", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugSour", {})
    end)
    sub:addOption("Fizz: set my shake to full (as if just sprinted)", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugShake", { value = 1 })
    end)
    sub:addOption("Make me thirsty and hungry (plain water only offers Drink while thirsty)", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugNeeds", { thirst = 0.6, hunger = 0.6 })
    end)
    sub:addOption("Make me full: not thirsty, not hungry", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugNeeds", { thirst = 0, hunger = 0 })
    end)
    sub:addOption("Fizz: calm my shake", player, function(p)
        sendClientCommand(p, DSTB.MODULE, "debugShake", { value = 0 })
    end)
    sub:addOption("Show my scent (Starving Zombies)", player, function(p)
        local total, parts = DSTB.Spill.playerScent(p)
        local text = string.format("DSTB scent %.1f tiles (SZ total smell now %s; scent integration %s)", total,
            tostring(p:getModData().szSmell), DSTB.scentEnabled() and "ON" or "OFF")
        print("[DontSpillTheBeans] " .. text)
        for _, part in ipairs(parts) do print(string.format("[DontSpillTheBeans]   %.1f  %s", part.scent, part.name)) end
        HaloTextHelper.addText(p, string.format("Scent %.1f", total), "[br/]", HaloTextHelper.getColorWhite())
    end)
    for _, m in ipairs({ 1, 10, 50 }) do
        sub:addOption("Spill rate x" .. m, player, function(p)
            sendClientCommand(p, DSTB.MODULE, "debugMultiplier", { value = m })
        end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
