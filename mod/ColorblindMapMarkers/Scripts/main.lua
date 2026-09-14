--[[
    ColorblindMapMarkers for "RV There Yet?"

    The in-game handheld map draws its route line and its checkpoint markers in
    red on tan paper. Red-on-tan is the single worst pairing for protanopia --
    a protanope sees red as very dark and very close in hue to the brown/tan
    paper, so the markers effectively disappear.

    Conveniently, the game does NOT bake red into its art:

      * the marker icons (TX_MapMarker_NextCheckpoint / _OldCheckpoint) are
        pure white textures that get tinted at runtime, and
      * the route line is a spline mesh using material MM_MapMarker, which
        exposes a "Color" vector parameter.

    So we never have to touch the packaged assets -- we just restate the tint
    and the material parameter at runtime. That keeps this mod tiny, keeps it
    working across game patches, and keeps it compatible with anything else
    that isn't fighting over the same two values.
--]]

local ok_config, config = pcall(require, "config")
if not ok_config or type(config) ~= "table" then
    print("[ColorblindMapMarkers] FATAL: could not load config.lua -- " ..
          tostring(config) .. "\n")
    return
end

local MOD = "[ColorblindMapMarkers]"

local function log(fmt, ...)
    print(string.format("%s " .. fmt .. "\n", MOD, ...))
end

local function vlog(fmt, ...)
    if config.verbose then log(fmt, ...) end
end

--------------------------------------------------------------------------------
-- Color handling
--------------------------------------------------------------------------------

-- UE stores material/widget colors in linear space, but humans pick colors in
-- sRGB. Convert so the config file can use ordinary hex codes.
local function srgb_channel_to_linear(c)
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function hex_to_linear(hex)
    local s = tostring(hex):gsub("#", "")
    if #s ~= 6 then
        log("WARNING: bad color %q, falling back to black", tostring(hex))
        s = "000000"
    end
    local r = tonumber(s:sub(1, 2), 16) / 255
    local g = tonumber(s:sub(3, 4), 16) / 255
    local b = tonumber(s:sub(5, 6), 16) / 255
    return {
        R = srgb_channel_to_linear(r),
        G = srgb_channel_to_linear(g),
        B = srgb_channel_to_linear(b),
        A = 1.0,
    }
end

local function as_vector(c)
    return { X = c.R, Y = c.G, Z = c.B }
end

local palette
do
    local chosen = config.preset == "custom"
        and config.custom
        or config.presets[config.preset]

    if type(chosen) ~= "table" then
        log("WARNING: unknown preset %q, using \"protan\"", tostring(config.preset))
        chosen = config.presets.protan
    end

    palette = {
        route  = hex_to_linear(chosen.route),
        marker = hex_to_linear(chosen.marker),
        player = hex_to_linear(chosen.player),
    }
    log("preset=%s route=%s marker=%s player=%s",
        tostring(config.preset), chosen.route, chosen.marker, chosen.player)
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function valid(obj)
    if not obj then return false end
    local ok, res = pcall(function() return obj:IsValid() end)
    return ok and res
end

local function class_name(obj)
    local ok, name = pcall(function()
        return obj:GetClass():GetFName():ToString()
    end)
    return ok and name or "<unknown>"
end

local function short_name(obj)
    local ok, name = pcall(function() return obj:GetFName():ToString() end)
    return ok and name or "<unknown>"
end

-- Try a list of method names until one works. Lets us cope with the handful of
-- different setters UMG exposes for "the color of this thing" without caring
-- which widget class we actually landed on.
local function try_setters(obj, setters, value)
    for _, method in ipairs(setters) do
        local ok = pcall(function() obj[method](obj, value) end)
        if ok then return method end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The route line: spline meshes using MM_MapMarker's "Color" parameter
--------------------------------------------------------------------------------

local function recolor_spline_meshes(map_actor)
    local changed = 0
    local vec = as_vector(palette.route)

    local ok = pcall(function()
        local comps = map_actor.SplineMeshComponents
        if not comps then return end
        comps:ForEach(function(_, elem)
            local comp = elem:get()
            if not valid(comp) then return end
            local applied = pcall(function()
                comp:SetVectorParameterValueOnMaterials(FName("Color"), vec)
            end)
            if applied then changed = changed + 1 end
        end)
    end)

    if not ok or changed == 0 then
        -- Fallback: the property name may have moved, so sweep every spline
        -- mesh component the engine knows about and keep the ones this actor
        -- owns.
        local all = FindAllOf("SplineMeshComponent")
        if all then
            for _, comp in ipairs(all) do
                if valid(comp) then
                    local owned = pcall(function()
                        return comp:GetOuter():GetFullName() == map_actor:GetFullName()
                    end)
                    if owned then
                        local applied = pcall(function()
                            comp:SetVectorParameterValueOnMaterials(FName("Color"), vec)
                        end)
                        if applied then changed = changed + 1 end
                    end
                end
            end
        end
    end

    return changed
end

--------------------------------------------------------------------------------
-- The markers: UMG widgets whose white icon textures get tinted
--------------------------------------------------------------------------------

local BORDER_SETTERS = { "SetBrushColor", "SetContentColorAndOpacity" }
local IMAGE_SETTERS  = { "SetColorAndOpacity", "SetBrushTintColor" }

-- Read the alpha already present on a widget's color property.
--
-- This matters more than it sounds. These marker widgets wrap their icon in an
-- OUTER Border that exists only for layout and whose brush is fully transparent.
-- Tinting that with alpha 1.0 turns it into a solid colored square sitting on
-- top of the map -- which is exactly what the first release did. So we never
-- invent an alpha; we reuse whatever was there, and skip anything invisible.
local function current_alpha(widget, prop)
    local ok, v = pcall(function() return widget[prop] end)
    if not ok or not v then return nil end

    local ok_a, a = pcall(function() return v.A end)
    if ok_a and type(a) == "number" then return a end

    -- FSlateColor keeps the real color one level down
    local ok_s, spec = pcall(function() return v.SpecifiedColor end)
    if ok_s and spec then
        local ok_sa, sa = pcall(function() return spec.A end)
        if ok_sa and type(sa) == "number" then return sa end
    end
    return nil
end

local function with_alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

-- Alpha seen on each widget last pass, so we can tell "settled" from "animating".
local alpha_history = {}

local function widget_key(widget)
    local ok, name = pcall(function() return widget:GetFullName() end)
    return ok and name or tostring(widget)
end

-- Decide whether it's safe to write a color to this widget right now.
--
-- The game fades some markers in when you open the map -- the next-checkpoint
-- one especially. That fade animates the same color property we want to set, so
-- writing mid-fade means our write and the animation fight over it: sometimes
-- the marker latches visible, usually it doesn't. (This is what made one marker
-- "almost never there" in v0.2.0.)
--
-- So: only write when the widget is either fully opaque, or its alpha hasn't
-- moved since the previous pass. Anything mid-animation is left alone and picked
-- up on a later pass, once it has settled.
local SETTLE_WINDOW = 0.05 -- seconds between samples for a comparison to mean anything

local function alpha_is_settled(widget, alpha)
    local key = widget_key(widget)
    local now = os.clock()
    local prev = alpha_history[key]

    -- Fully opaque: nothing left to fade into, always safe.
    if alpha >= 0.99 then
        alpha_history[key] = { a = alpha, t = now }
        return true
    end

    -- Two samples taken in the same frame are identical no matter what the
    -- animation is doing, so they prove nothing. Our hooks can fire several
    -- times per frame, hence the time gate rather than a plain "did it change".
    if prev and (now - prev.t) >= SETTLE_WINDOW then
        local settled = math.abs(alpha - prev.a) < 0.001
        alpha_history[key] = { a = alpha, t = now }
        return settled
    end

    if not prev then
        alpha_history[key] = { a = alpha, t = now }
    end
    return false
end

local function diagnose_widget(user_widget, widget, cls, alpha)
    if not config.diagnose then return end
    local function probe(fn, default)
        local ok, v = pcall(fn)
        if ok and v ~= nil then return v end
        return default
    end
    local ro = probe(function() return widget.RenderOpacity end, -1)
    local vis = probe(function() return widget:GetVisibility() end, -1)
    log("  DIAG %s.%s (%s) alpha=%.3f renderOpacity=%s visibility=%s",
        short_name(user_widget), short_name(widget), cls, alpha,
        tostring(ro), tostring(vis))
end

local function walk_widget(widget, depth, visit)
    if not valid(widget) or depth > 12 then return end
    visit(widget, depth)

    local ok, count = pcall(function() return widget:GetChildrenCount() end)
    if not ok or not count then return end
    for i = 0, count - 1 do
        local ok_child, child = pcall(function() return widget:GetChildAt(i) end)
        if ok_child and valid(child) then
            walk_widget(child, depth + 1, visit)
        end
    end
end

local function recolor_user_widget(user_widget, color)
    local changed = 0

    local ok, root = pcall(function() return user_widget.WidgetTree.RootWidget end)
    if not ok or not valid(root) then return 0 end

    walk_widget(root, 0, function(w)
        local cls = class_name(w)
        local used, alpha

        if cls == "Border" then
            alpha = current_alpha(w, "BrushColor") or 1.0
            diagnose_widget(user_widget, w, cls, alpha)
            if alpha <= 0.004 then
                -- Transparent layout spacer. Recoloring it would paint a solid
                -- square over the map, so leave it completely alone.
                vlog("  %s.%s (Border) skipped: transparent",
                     short_name(user_widget), short_name(w))
                return
            end
            if not alpha_is_settled(w, alpha) then
                vlog("  %s.%s (Border) deferred: alpha %.3f still moving",
                     short_name(user_widget), short_name(w), alpha)
                return
            end
            used = try_setters(w, BORDER_SETTERS, with_alpha(color, alpha))

        elseif cls == "Image" then
            alpha = current_alpha(w, "ColorAndOpacity") or 1.0
            diagnose_widget(user_widget, w, cls, alpha)
            if alpha <= 0.004 then return end
            if not alpha_is_settled(w, alpha) then return end
            used = try_setters(w, IMAGE_SETTERS, with_alpha(color, alpha))

        elseif cls == "TextBlock" or cls == "RichTextBlock" then
            -- The "CAMP SITE" / "EXIT TO ROUTE 65" labels ship red.
            if not config.recolor_labels then return end
            alpha = current_alpha(w, "ColorAndOpacity") or 1.0
            diagnose_widget(user_widget, w, cls, alpha)
            if alpha <= 0.004 then return end
            if not alpha_is_settled(w, alpha) then return end
            local c = with_alpha(color, alpha)
            if pcall(function()
                w:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 })
            end) then
                used = "SetColorAndOpacity"
            elseif pcall(function() w.ColorAndOpacity.SpecifiedColor = c end) then
                used = "ColorAndOpacity.SpecifiedColor"
            end

        else
            return
        end

        if used then
            changed = changed + 1
            vlog("  %s.%s (%s) alpha=%.2f <- %s",
                 short_name(user_widget), short_name(w), cls, alpha, used)
        end
    end)

    return changed
end

-- Widget blueprint class -> which palette entry it should take.
local WIDGET_CLASSES = {
    WG_Map_Checkpoint_C    = "marker",
    WG_Map_CampSite_C      = "marker",
    WG_Map_ExitToRoute65_C = "marker",
    WG_Map_DeathMarker_C   = "marker",
    WG_Map_Truck_C         = "player",
}

local function recolor_marker_widgets()
    local total = 0

    for cls, role in pairs(WIDGET_CLASSES) do
        if role ~= "player" or config.recolor_player_marker then
            local instances = FindAllOf(cls)
            if instances then
                for _, w in ipairs(instances) do
                    if valid(w) then
                        total = total + recolor_user_widget(w, palette[role])
                    end
                end
            end
        end
    end

    return total
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------

local last_report = { splines = -1, widgets = -1 }

local function apply()
    local maps = FindAllOf("BP_Interactable_Map_C")
    local splines = 0

    if maps then
        for _, map_actor in ipairs(maps) do
            if valid(map_actor) then
                splines = splines + recolor_spline_meshes(map_actor)
            end
        end
    end

    local widgets = recolor_marker_widgets()

    -- Only log when the picture changes, so we don't spam UE4SS.log once per second.
    if splines ~= last_report.splines or widgets ~= last_report.widgets then
        log("applied: %d spline segment(s), %d marker widget element(s)", splines, widgets)
        last_report.splines = splines
        last_report.widgets = widgets
    end
end

-- Re-apply on a timer. The map rebuilds its spline line and respawns marker
-- widgets as you drive and as checkpoints change, so a one-shot pass would get
-- overwritten. A 1s sweep over a handful of objects is not measurable.
LoopAsync(config.refresh_ms, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(apply)
        if not ok then
            log("ERROR during apply: %s", tostring(err))
        end
    end)
    return false -- keep looping
end)

-- Re-apply immediately after the game rebuilds map visuals.
--
-- The timer alone isn't enough: while panning the map the game rewrites marker
-- colors faster than we refresh, so a marker could be caught mid-race and show
-- its stock color until the next tick -- visible as flicker that depended on
-- exactly when you stopped moving. Post-hooking the functions that do the
-- rewriting means we always get the last word.
local HOOK_TARGETS = {
    "/Game/Ride/Interactables/Misc/Map/BP_Interactable_Map.BP_Interactable_Map_C:UpdateCheckpointVisuals",
    "/Game/Ride/Interactables/Misc/Map/BP_Interactable_Map.BP_Interactable_Map_C:SetupWidgets",
    "/Game/Ride/Interactables/Misc/Map/BP_Interactable_Map.BP_Interactable_Map_C:ConstructSplineMesh",
    "/Game/Ride/Interactables/Misc/Map/WG_Map_Checkpoint.WG_Map_Checkpoint_C:SetOldCheckpoint",
}

local hooked = 0
for _, target in ipairs(HOOK_TARGETS) do
    -- Blueprint function names can move between game patches; a missing one
    -- must not take the whole mod down, so each hook is optional.
    local ok = pcall(RegisterHook, target, function() end, function()
        pcall(apply)
    end)
    if ok then
        hooked = hooked + 1
    end
    vlog("hook %s: %s", target, ok and "registered" or "unavailable")
end

log("loaded -- %d/%d hooks, refreshing every %dms",
    hooked, #HOOK_TARGETS, config.refresh_ms)
