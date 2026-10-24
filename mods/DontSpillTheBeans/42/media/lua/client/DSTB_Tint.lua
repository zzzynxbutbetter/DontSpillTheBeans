-- Inventory rows of bags that have something spilled in them are tinted green (a bag that has gone off, a stronger green).
-- The inventory pane draws its rows in one big function that gives no hook per item, so the function is wrapped and, after
-- it has drawn, the pane's own list of rows is read to find the rows that hold such a bag. That list (`self.items`, one
-- entry per row, in order: the item, or for the first row of a stack the stack with its items) is what the pane itself uses
-- to know which item is under the mouse, so it is right for any layout (vanilla, or a mod that re-lays out the rows).
-- The wrapper is put in place when the game starts, after every mod has loaded: some inventory mods replace the whole
-- function while loading, which would throw away a wrapper installed earlier. Setting: Options > Mods > Don't Spill the Beans.

require "ISUI/ISInventoryPane"
require "DSTB_Audio"   -- (its settings come first on the options page)
require "DSTB_Options"

local DSTB = DontSpillTheBeans

local page = DSTB.Options.page
if page then page:addTitle("Inventory") end
local enabled = page and page:addTickBox("TintSpilledBags", "Tint spilled-in bags green in the inventory", true) or nil
local function tintOn() return enabled == nil or enabled:getValue() end

local SPILLED = { r = 0.45, g = 0.75, b = 0.1, a = 0.15 }
local SOUR = { r = 0.55, g = 0.62, b = 0.28, a = 0.17 }   -- murky, sickly olive

local function tintRows(pane)
    local rows = pane.items
    if not rows or not pane.itemHgt or pane.itemHgt <= 0 then return end
    local scroll = pane:getYScroll()
    -- Row i is drawn at (i - 1) * itemHgt + headerHgt, in the pane's scrolled coordinates.
    local first = math.max(1, math.floor((-scroll - pane.headerHgt) / pane.itemHgt))
    local last = math.min(#rows, math.ceil((-scroll + pane:getHeight()) / pane.itemHgt) + 1)
    for i = first, last do
        local entry = rows[i]
        local item = entry
        if type(entry) == "table" then item = entry.items and entry.items[1] or nil end   -- the first row of a stack
        if item and instanceof(item, "InventoryContainer") then
            local md = item:getModData()
            if md.DSTB_spilled then
                local c = md.DSTB_sour and SOUR or SPILLED
                pane:drawRect(1, (i - 1) * pane.itemHgt + pane.headerHgt, pane:getWidth() - 1 - (pane:isVScrollBarVisible() and 13 or 0), pane.itemHgt, c.a, c.r, c.g, c.b)
            end
        end
    end
end

local installed = false

local function install()
    if installed or not ISInventoryPane then return end
    installed = true
    local renderdetails = ISInventoryPane.renderdetails
    function ISInventoryPane:renderdetails(doDragged, ...)
        renderdetails(self, doDragged, ...)
        if doDragged or not tintOn() then return end
        if self.dragging ~= nil and self.dragStarted then return end   -- rows are moving: leave them alone
        tintRows(self)
    end
end

Events.OnGameStart.Add(install)
