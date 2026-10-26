-- Per-mod integrations: each DSTB_Compat_<Mod>.lua only adds ids to DontSpillTheBeans.Config tables, so it is
-- harmless when that mod is not installed. Add new ones here. Vanilla loads first so the mods can refine it.

require "DSTB_Config"
require "DSTB_Compat_Vanilla"              -- Project Zomboid food rules
require "DSTB_Compat_Vanilla_Containers"   -- Project Zomboid fluid containers and bags
require "DSTB_Compat_VFE"                  -- Vanilla Foods Expanded (3577903007)
require "DSTB_Compat_VFE_Containers"
require "DSTB_Compat_Pomps"                -- Pomp's Items - Just the Food (2792348686)
require "DSTB_Compat_Pomps_Containers"
require "DSTB_Compat_Sapph"                -- Sapph's Cooking (3409143790)
require "DSTB_Compat_Sapph_Containers"
require "DSTB_Compat_MRE"                  -- MRE Mod (3765409550)
require "DSTB_Compat_MRE_Containers"
require "DSTB_Compat_AuthZ"                -- Authentic Z (2335368829): Current, Backpacks+ and Lite
require "DSTB_Compat_AuthZ_Containers"
require "DSTB_Compat_LTPE"                 -- Long Term Preservation Extended (3597673472): the main mod and its eight DLC mods
require "DSTB_Compat_LTPE_Containers"
require "DSTB_Compat_EmptyCans_Containers"      -- Wesch's Empty Can Models (3422869729): the empty cans that tins leave behind
require "DSTB_Compat_Reseal"               -- jars that can be resealed after opening: the game, Vanilla Foods Expanded and Long Term Preservation Extended
