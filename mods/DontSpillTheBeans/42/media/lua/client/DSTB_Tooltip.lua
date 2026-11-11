-- Adds lines to the item card (the hover tooltip): whether the item is safe to carry loose in a bag, what is spilled
-- in a bag, and bars for a bag's wetness and dirt.
-- The text lines ride on the item's single custom tooltip line, borrowed for the duration of the render and put
-- back afterwards, so nothing is saved on the item and a wet bag's own "Wet" line is kept. The bars are layout rows
-- added after the item's own card is drawn, which needs a copy of the vanilla render (as Nature's Call does).

require "ISUI/ISToolTipInv"
require "DSTB_Config"
require "DSTB_Spill"
require "DSTB_Wet"

local DSTB = DontSpillTheBeans

local renderOriginal = ISToolTipInv.render

local BAR_MIN = 0.05        -- below this a bag shows no bar
local BAR_BOTTOM = 5

-- Green (none) to red (full), in the player's own good/bad highlight colours: what vanilla uses for a garment's
-- Dirty and Wet bars.
local function severity(fraction)
    local good, bad = getCore():getGoodHighlitedColor(), getCore():getBadHighlitedColor()
    return good:getR() + (bad:getR() - good:getR()) * fraction,
        good:getG() + (bad:getG() - good:getG()) * fraction,
        good:getB() + (bad:getB() - good:getB()) * fraction
end

local function bagBars(item)
    if not item or not instanceof(item, "InventoryContainer") then return nil end
    local bars = {}
    local wet = math.min(1, DSTB.Wet.get(item) / 100)   -- a bag's wetness, live (it dries)
    local dirt = math.min(1, DSTB.Spill.dirtLevel(item))
    -- Dirty before Wet, the order of a garment's card.
    if dirt >= BAR_MIN then bars[#bars + 1] = { getText("Tooltip_clothing_dirty") .. ":", dirt } end
    if wet >= BAR_MIN then bars[#bars + 1] = { getText("Tooltip_clothing_wet") .. ":", wet } end
    return #bars > 0 and bars or nil
end

-- Draws the bars under whatever the card already holds, growing the card to fit.
local function appendBars(tooltip, bars)
    local layout = tooltip:beginLayout()
    local textManager = getTextManager()
    local font = tooltip:getFont()
    local left = textManager:MeasureStringX(font, "0")
    local gap = math.max(textManager:MeasureStringX(font, "W"), 8)
    local available = tooltip:getWidth() - left * 2
    local barWidth = math.max(40, math.floor(available / 2))
    layout:setMinLabelWidth(math.max(0, math.floor(available - barWidth - gap)))
    layout:setMinValueWidth(barWidth)
    for _, bar in ipairs(bars) do
        local row = layout:addItem()
        row:setLabel(bar[1], 1, 1, 0.8, 1)
        local r, g, b = severity(bar[2])
        row:setProgress(bar[2], r, g, b, 1)
    end
    local height = tooltip:getHeight()
    layout:render(left, height, tooltip)
    tooltip:setHeight(height + #bars * textManager:getFontHeight(font) + BAR_BOTTOM)
    tooltip:endLayout(layout)
end

-- ISToolTipInv:render, with the bars added after the item's own DoTooltip in both the measuring and the drawing pass.
local function renderWithBars(self, bars)
    if ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end

    local mx = getMouseX() + 24
    local my = getMouseY() + 24
    if not self.followMouse then
        mx = self:getX()
        my = self:getY()
        if self.anchorBottomLeft then
            mx = self.anchorBottomLeft.x
            my = self.anchorBottomLeft.y
        end
    end

    local function doTooltip()
        self.item:DoTooltip(self.tooltip)
        appendBars(self.tooltip, bars)
    end

    self.tooltip:setX(mx)
    self.tooltip:setY(my)
    self.tooltip:setWidth(50)
    self.tooltip:setMeasureOnly(true)
    doTooltip()
    self.tooltip:setMeasureOnly(false)

    local core = getCore()
    local maxX, maxY = core:getScreenWidth(), core:getScreenHeight()
    local tw, th = self.tooltip:getWidth(), self.tooltip:getHeight()

    self.tooltip:setX(math.max(0, math.min(mx, maxX - tw - 1)))
    if not self.followMouse and self.anchorBottomLeft then
        self.tooltip:setY(math.max(0, math.min(my - th, maxY - th - 1)))
    else
        self.tooltip:setY(math.max(0, math.min(my, maxY - th - 1)))
    end

    if self.contextMenu and self.contextMenu.joyfocus then
        local playerNum = self.contextMenu.player
        self.tooltip:setX(getPlayerScreenLeft(playerNum) + 60)
        self.tooltip:setY(getPlayerScreenTop(playerNum) + 60)
    elseif self.contextMenu and self.contextMenu.currentOptionRect then
        if self.contextMenu.currentOptionRect.height > 32 then
            self:setY(my + self.contextMenu.currentOptionRect.height)
        end
        self:adjustPositionToAvoidOverlap(self.contextMenu.currentOptionRect)
    end

    self:setX(self.tooltip:getX())
    self:setY(self.tooltip:getY())
    self:setWidth(tw)
    self:setHeight(th)

    if self.followMouse and self.contextMenu == nil then
        self:adjustPositionToAvoidOverlap({ x = mx - 24 * 2, y = my - 24 * 2, width = 24 * 2, height = 24 * 2 })
    end

    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    doTooltip()
end

function ISToolTipInv:render()
    local item = self.item
    local suffix = item and DSTB.Spill.hint(item)
    local bars = bagBars(item)
    local fizzy = false   -- a full carbonated drink: opening it after exercise makes it foam over
    if item and DSTB.fizzEnabled() and DSTB.Config.CarbonatedItems[item:getFullType()] then
        local fc = item:getFluidContainerFromSelfOrWorldItem()
        fizzy = fc ~= nil and not fc:isEmpty() and fc:getFilledRatio() >= 0.999
    end
    local soiled = item and instanceof(item, "InventoryContainer") and DSTB.Wet.tooltipKey(item) or nil
    if not suffix and not soiled and not bars and not fizzy then
        if item and DSTB.Wet.isStoredKey(item:getTooltip()) then item:setTooltip(nil) end   -- left by an earlier version
        return renderOriginal(self)
    end

    local previous = item:getTooltip()
    if DSTB.Wet.isStoredKey(previous) then previous = nil end
    local text = previous and getText(previous) or nil
    for _, line in ipairs({ soiled and getText(soiled) or false, suffix and getText("Tooltip_DontSpillTheBeans_Hint" .. suffix) or false, fizzy and getText("Tooltip_DontSpillTheBeans_HintFizzy") or false }) do
        if line then text = text and (text .. "\n" .. line) or line end   -- our lines go on their own rows, under the item's own text
    end
    -- The card runs the text through the translator, where a bare % starts a format code: write it as %%.
    item:setTooltip(text and text:gsub("%%", "%%%%") or nil)
    local ok, err
    if bars then
        ok, err = pcall(renderWithBars, self, bars)
    else
        ok, err = pcall(renderOriginal, self)
    end
    item:setTooltip(previous)
    if not ok then error(err, 0) end
end
