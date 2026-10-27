-- Adds a line to the item card (the hover tooltip) saying whether the item is safe to carry loose in a bag.
-- The item's single custom tooltip line is borrowed for the duration of the render and put back afterwards,
-- so nothing is saved on the item and a wet bag's own "Wet" line is kept.

require "ISUI/ISToolTipInv"
require "DSTB_Config"
require "DSTB_Spill"
require "DSTB_Wet"

local DSTB = DontSpillTheBeans

local renderOriginal = ISToolTipInv.render

function ISToolTipInv:render()
    local item = self.item
    local suffix = item and DSTB.Spill.hint(item)
    local wet = item and instanceof(item, "InventoryContainer") and math.floor(DSTB.Wet.get(item) + 0.5) or 0   -- a bag's wetness, live (it dries)
    local dirt = item and instanceof(item, "InventoryContainer") and math.floor(DSTB.Spill.dirtLevel(item) * 100 + 0.5) or 0
    local fizzy = false   -- a full carbonated drink: opening it after exercise makes it foam over
    if item and DSTB.fizzEnabled() and DSTB.Config.CarbonatedItems[item:getFullType()] then
        local fc = item:getFluidContainerFromSelfOrWorldItem()
        fizzy = fc ~= nil and not fc:isEmpty() and fc:getFilledRatio() >= 0.999
    end
    local soiled = item and instanceof(item, "InventoryContainer") and DSTB.Wet.tooltipKey(item) or nil
    if not suffix and not soiled and wet < 5 and dirt < 5 and not fizzy then
        if item and DSTB.Wet.isStoredKey(item:getTooltip()) then item:setTooltip(nil) end   -- left by an earlier version
        return renderOriginal(self)
    end

    local previous = item:getTooltip()
    if DSTB.Wet.isStoredKey(previous) then previous = nil end
    local text = previous and getText(previous) or nil
    for _, line in ipairs({ soiled and getText(soiled) or false, suffix and getText("Tooltip_DontSpillTheBeans_Hint" .. suffix) or false, fizzy and getText("Tooltip_DontSpillTheBeans_HintFizzy") or false, wet >= 5 and getText("Tooltip_DontSpillTheBeans_BagWetness", wet) or false, dirt >= 5 and getText("Tooltip_DontSpillTheBeans_BagDirt", dirt) or false }) do
        if line then text = text and (text .. "\n" .. line) or line end   -- our lines go on their own rows, under the item's own text
    end
    -- The card runs the text through the translator, where a bare % starts a format code: write it as %%.
    item:setTooltip(text and text:gsub("%%", "%%%%") or nil)
    local ok, err = pcall(renderOriginal, self)
    item:setTooltip(previous)
    if not ok then error(err, 0) end
end
