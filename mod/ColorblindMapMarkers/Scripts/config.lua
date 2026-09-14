-- ColorblindMapMarkers -- user configuration
--
-- Colors are written as "#RRGGBB" sRGB hex, the same values you'd pick in any
-- image editor. The mod converts them to UE's linear color space for you.

local config = {}

--------------------------------------------------------------------------------
-- Preset
--------------------------------------------------------------------------------
-- Which built-in palette to use. Set to "custom" to use the `custom` table below.
--
--   "protan"  - for protanopia / protanomaly (red-blind, red looks dark)
--   "deutan"  - for deuteranopia / deuteranomaly (green-blind)
--   "tritan"  - for tritanopia (blue-blind) -- avoids blue, uses warm red/orange
--   "mono"    - no hue reliance at all: near-black markers, maximum luminance
--               contrast against the tan paper map
--   "custom"  - use `config.custom`
config.preset = "protan"

--------------------------------------------------------------------------------
-- Presets
--------------------------------------------------------------------------------
-- `route`  = the tracking/route line drawn across the map
-- `marker` = checkpoint / campsite / exit markers
-- `player` = your RV's own position marker (kept distinct from the others)
--
-- Design note: the map is not flat tan paper. Measured across the game's four
-- RideMap textures, it runs from cream paper (#FFEDCB) through tan and olive
-- down to near-black forest (#2C382F), with a median luminance around 0.27.
-- That means most of the map is mid-to-dark, so *dark* markers are what stay
-- readable over the largest share of it:
--
--   stock red  #FF3200   ~24% of map area keeps >=3:1 contrast
--   cyan       #00FFFF   ~49%   (bright, but washes out against paper)
--   navy       #0A1A66   ~76%   <- default: dark enough, still clearly blue
--   near-black #141414   ~82%   (best contrast, but no color coding)
--
-- Blue is the right hue because the blue-yellow axis is the one protanopes and
-- deuteranopes keep; going dark is what buys the luminance contrast on top.
-- No single flat color can win everywhere on a map this varied -- these are the
-- best compromises, and you can tune them below.
config.presets = {
    protan = {
        route  = "#0A1A66",  -- navy: reads blue, dark enough for contrast
        marker = "#06104F",  -- deeper navy for checkpoint markers
        player = "#141414",  -- near-black; the RV icon's shape sets it apart
    },
    deutan = {
        -- Same logic: the blue-yellow axis survives deuteranopia too.
        route  = "#0A1A66",
        marker = "#06104F",
        player = "#141414",
    },
    tritan = {
        -- Blue is the bad axis here, so lean on deep red instead.
        route  = "#5C0A00",
        marker = "#400700",
        player = "#141414",
    },
    mono = {
        route  = "#141414",
        marker = "#000000",
        player = "#3A3A3A",
    },
}

-- Used when config.preset == "custom"
config.custom = {
    route  = "#0A1A66",
    marker = "#06104F",
    player = "#141414",
}

--------------------------------------------------------------------------------
-- Behaviour
--------------------------------------------------------------------------------
-- How often (milliseconds) to re-apply colors. The game rebuilds the map's
-- spline line and marker widgets as you drive, so we refresh periodically.
-- Raise this if you are chasing every last frame; 1000 is already very cheap.
config.refresh_ms = 1000

-- Recolor the player's own RV marker too. Turn this off to leave it stock.
config.recolor_player_marker = true

-- Recolor the text labels under markers ("CAMP SITE", "EXIT TO ROUTE 65").
-- These ship in red, so leaving this off keeps the exact problem this mod
-- exists to fix.
config.recolor_labels = true

-- Log every widget the mod visits, and why it did or didn't recolor it.
-- This runs on every refresh, so it writes to UE4SS.log continuously -- turn it
-- on only while working out why something isn't being recolored.
config.verbose = false

-- Extra per-widget state dump (alpha, render opacity, visibility) on every
-- refresh. Noisier still; for diagnosing one specific misbehaving marker.
config.diagnose = false

return config
