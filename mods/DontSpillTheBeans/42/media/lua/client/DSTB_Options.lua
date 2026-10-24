-- The mod's page in Options > Mods, shared by the parts of the client that add settings to it (sounds, inventory tint).
-- Missing PZAPI (old game build): DSTB.Options.page is nil and every setting is at its default.

local DSTB = DontSpillTheBeans

local Options = {}
DSTB.Options = Options

if PZAPI and PZAPI.ModOptions then
    Options.page = PZAPI.ModOptions:create("DontSpillTheBeans", "Don't Spill the Beans")
end
