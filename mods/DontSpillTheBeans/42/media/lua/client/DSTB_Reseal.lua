-- "Reseal Jar" on an opened jar (Config.Reseal): closes it again with a jar lid, which opening the jar handed back.
-- The server does the swap (see Commands.resealJar): the jar becomes the closed one again. The action looks and sounds
-- like opening that jar (the animation, tool models, sound and time of the recipe that opens it).

require "TimedActions/ISBaseTimedAction"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISFluidContainerMenu"
require "DSTB_Config"

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

local FALLBACK_SECONDS = 3   -- when the opening recipe cannot be found; action time runs at 48 per second at normal game speed

DSTB_ResealAction = ISBaseTimedAction:derive("DSTB_ResealAction")

-- The recipe that opens `jar`, by the full name the generated table holds.
local function openingRecipe(jar)
    local name = Config.ResealRecipe[jar:getFullType()]
    return name and getScriptManager():getCraftRecipe(name) or nil
end

-- Whether one of the recipe's items goes in hand `n` (1 or 2) while it is carried out (the input flag Prop1 / Prop2).
local function holdsItem(recipe, n)
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if (n == 1 and input:isProp1()) or (n == 2 and input:isProp2()) then return true end
    end
    return false
end

function DSTB_ResealAction:isValid()
    return self.character:getInventory():containsRecursive(self.jar) and not self.character:getVehicle()
end

-- The inventory rows of the jar and the lid show the progress bar while it runs, as the items of a craft do.
local function setProgress(self, delta)
    for _, item in ipairs({ self.jar, self.lid }) do
        if item then item:setJobDelta(delta) end
    end
end

function DSTB_ResealAction:update()
    setProgress(self, self:getJobDelta())
end

function DSTB_ResealAction:start()
    self.lid = self.character:getInventory():getFirstTypeRecurse(Config.ResealLid)
    for _, item in ipairs({ self.jar, self.lid }) do
        if item then item:setJobType(getText("ContextMenu_DontSpillTheBeans_ResealJar")) end
    end
    setProgress(self, 0)
    local script = self.recipe and self.recipe:getTimedActionScript()
    if not script then
        self:setActionAnim("Loot")
        self.character:reportEvent("EventLootItem")
        return
    end
    self:setActionAnim(script:getActionAnim())
    if script:getAnimVarKey() then self:setAnimVariable(script:getAnimVarKey(), script:getAnimVarVal()) end
    -- The hands hold what the opening recipe has in them: a hand that one of its items is flagged for holds that item (here the
    -- jar being resealed), else the tool of its timed action.
    local prop1, prop2 = script:getProp1(), script:getProp2()
    local jarModel = self.jar:getStaticModel()
    local held1, held2 = holdsItem(self.recipe, 1), holdsItem(self.recipe, 2)
    if held1 then prop1 = jarModel end
    if held2 then prop2 = jarModel end
    if (prop1 and prop1 ~= "") or (prop2 and prop2 ~= "") then
        self:setOverrideHandModels(prop1 ~= "" and prop1 or nil, prop2 ~= "" and prop2 or nil)
    end
    if script:getSound() and script:getSoundTime() == ActionSoundTime.ACTION_START then
        self.sound = self.character:playSound(script:getSound())
    end
    self.script = script
end

local function stopSound(self)
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then self.character:stopOrTriggerSound(self.sound) end
    self.sound = nil
end

function DSTB_ResealAction:stop()
    setProgress(self, 0)
    stopSound(self)
    ISBaseTimedAction.stop(self)
end

function DSTB_ResealAction:perform()
    setProgress(self, 0)
    stopSound(self)
    if self.script and self.script:getCompletionSound() then self.character:playSound(self.script:getCompletionSound()) end
    sendClientCommand(self.character, DSTB.MODULE, "resealJar", { id = self.jar:getID() })
    DSTB.Carried.invalidate(self.character)
    ISBaseTimedAction.perform(self)
end

function DSTB_ResealAction:new(character, jar)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.jar = jar
    o.recipe = openingRecipe(jar)
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = character:isTimedActionInstant() and 1 or (o.recipe and o.recipe:getTime(character) * 5 or FALLBACK_SECONDS * 48)
    return o
end

local function reseal(player, jar)
    ISTimedActionQueue.add(DSTB_ResealAction:new(player, jar))
end

-- The icon beside the option is the closed jar it makes, as the Open option of a closed jar shows the open one.
local icons = {}
local function iconOf(closedType)
    if icons[closedType] == nil then
        local item = instanceItem(closedType)
        icons[closedType] = item and item:getTexture() or false
    end
    return icons[closedType] or nil
end

-- Where the Open option of a closed jar sits: right after the options that come before the crafting ones and before those that
-- come after them (the fluid, grab and "evolved recipe" menus, "used in recipes", then Unequip and Drop). The first option any of
-- those later menus adds is remembered while the menu is built, and Reseal goes in front of it.
local anchorName
local function noteAnchor(owner, name)
    local original = owner[name]
    if not original then return end
    owner[name] = function(context, ...)
        local before = #context.options
        local result = original(context, ...)
        if not anchorName and #context.options > before then anchorName = context.options[before + 1].name end
        return result
    end
end
noteAnchor(ISFluidContainerMenu, "createMenu")
noteAnchor(ISInventoryPaneContextMenu, "doRecipeListForItem")
noteAnchor(ISInventoryPaneContextMenu, "doGrabMenu")
noteAnchor(ISInventoryPaneContextMenu, "doEvorecipeMenu")

local createMenu = ISInventoryPaneContextMenu.createMenu
ISInventoryPaneContextMenu.createMenu = function(...)
    anchorName = nil
    return createMenu(...)
end

local function addResealOption(context, player, item)
    local text = getText("ContextMenu_DontSpillTheBeans_ResealJar")
    local before = anchorName or getText("ContextMenu_Unequip")
    local option
    if context:getOptionFromName(before) then
        option = context:insertOptionBefore(before, text, player, reseal, item)
    else
        option = context:addOption(text, player, reseal, item)
    end
    option.iconTexture = iconOf(Config.Reseal[item:getFullType()])
    return option
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    if not DSTB.resealEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    for _, entry in ipairs(items) do
        local item = instanceof(entry, "InventoryItem") and entry or entry.items[1]
        local fluid = item and item:getFluidContainer()
        if item and Config.Reseal[item:getFullType()] and (instanceof(item, "Food") or (fluid and not fluid:isEmpty()))
            and player:getInventory():containsRecursive(item) then
            local option = addResealOption(context, player, item)
            if not player:getInventory():getFirstTypeRecurse(Config.ResealLid) then
                option.notAvailable = true
                local tip = ISToolTip:new()
                tip:initialise()
                tip:setVisible(false)
                tip.description = getText("Tooltip_DontSpillTheBeans_ResealNeedsLid")
                option.toolTip = tip
            end
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
