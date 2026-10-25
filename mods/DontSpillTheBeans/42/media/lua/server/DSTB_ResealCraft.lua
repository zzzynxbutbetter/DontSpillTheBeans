-- Opening a resealed jar gives back what was left in it. The recipes that open jars do not all carry the contents over
-- (some make a full jar whatever the closed one held), so after one runs, the jar it made is set to what the resealed jar
-- held: its food values and how far it had spoiled, or its liquid (see Commands.resealJar). Server / single player only:
-- that is where a hand-craft is carried out.
if isClient() then return end

require "DSTB_Config"
if not ISHandcraftAction then pcall(require, "Entity/TimedActions/ISHandcraftAction") end
if not (ISHandcraftAction and ISHandcraftAction.performRecipe) then
    print("[DontSpillTheBeans] ISHandcraftAction.performRecipe not found: resealed jars will open full")
    return
end

local DSTB = DontSpillTheBeans
local Config = DSTB.Config

-- What the resealed jars among the recipe's inputs held, taken before the recipe uses them up.
local function resealedInputs(data)
    local held = {}
    local inputs = data:getAllInputItems()
    for i = 0, inputs:size() - 1 do
        local item = inputs:get(i)
        local md = item:getModData()
        if md.DSTB_resealed then
            local entry = { left = md.DSTB_left }
            local fc = item:getFluidContainer()
            if fc then entry.fluid = fc:copy() end
            if instanceof(item, "Food") then entry.aged = item:getAge() / math.max(1, item:getOffAgeMax()) end
            held[#held + 1] = entry
        end
    end
    return held
end

local function restore(player, item, entry)
    local fc = item:getFluidContainer()
    if entry.fluid and fc then fc:copyFluidsFrom(entry.fluid) end
    if instanceof(item, "Food") then
        local left = entry.left
        if left then
            item:setHungChange(left.hung)
            item:setThirstChange(left.thirst)
            item:setCalories(left.cal)
            item:setCarbohydrates(left.carb)
            item:setLipids(left.lip)
            item:setProteins(left.prot)
        end
        if entry.aged then item:setAge(entry.aged * item:getOffAgeMax()) end
    end
    syncItemFields(player, item)
end

local performRecipe = ISHandcraftAction.performRecipe
function ISHandcraftAction:performRecipe()
    local data = self.logic and self.logic:getRecipeData()
    local held = data and resealedInputs(data) or {}
    local result = performRecipe(self)
    if data then
        local created = data:getAllCreatedItems()
        local n = 0
        for i = 0, created:size() - 1 do
            local item = created:get(i)
            if Config.Reseal[item:getFullType()] then
                n = n + 1
                if held[n] then restore(self.character, item, held[n]) end
            end
        end
    end
    return result
end
