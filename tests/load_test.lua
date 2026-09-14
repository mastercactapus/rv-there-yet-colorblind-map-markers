-- Loads the mod against stubbed UE4SS globals so we can catch load-time errors,
-- verify the palette math, and regression-test widget recoloring -- all without
-- launching the game.

package.path = "mod/ColorblindMapMarkers/Scripts/?.lua;" .. package.path

local logged, loop_ms, hooks = {}, nil, {}

--------------------------------------------------------------------------------
-- Fake UMG widgets
--------------------------------------------------------------------------------

local function make_widget(cls, name, props, children)
    local w = { _children = children or {}, calls = {} }
    for k, v in pairs(props or {}) do w[k] = v end

    function w:IsValid() return true end
    function w:GetFName() return { ToString = function() return name end } end
    function w:GetClass()
        return { GetFName = function() return { ToString = function() return cls end } end }
    end
    function w:GetChildrenCount() return #self._children end
    function w:GetChildAt(i) return self._children[i + 1] end

    function w:SetBrushColor(c) self.calls[#self.calls + 1] = { "SetBrushColor", c } end
    function w:SetColorAndOpacity(c) self.calls[#self.calls + 1] = { "SetColorAndOpacity", c } end

    return w
end

-- Mirrors the real WG_Map_Checkpoint: an OUTER transparent Border used purely
-- for layout, wrapping the circle-art Border and a red text label. Tinting that
-- outer Border was what painted solid squares over the map in v0.1.0.
local outer_border, circle_border, label

local function build_checkpoint()
    circle_border = make_widget("Border", "CheckpointBorder",
        { BrushColor = { R = 1.0, G = 0.03, B = 0.0, A = 1.0 } })
    label = make_widget("TextBlock", "CheckpointText",
        { ColorAndOpacity = { SpecifiedColor = { R = 1.0, G = 0.0, B = 0.0, A = 1.0 } } })
    outer_border = make_widget("Border", "Border",
        { BrushColor = { R = 1.0, G = 1.0, B = 1.0, A = 0.0 } },
        { circle_border, label })

    return { WidgetTree = { RootWidget = outer_border }, IsValid = function() return true end,
             GetFName = function() return { ToString = function() return "WG_Map_Checkpoint" end } end }
end

local checkpoint = build_checkpoint()

-- A marker caught mid fade-in: its Border is partly transparent and its alpha is
-- still moving. Writing to it here is what made a marker "almost never there".
local fading_border = make_widget("Border", "CheckpointBorder",
    { BrushColor = { R = 1.0, G = 0.03, B = 0.0, A = 0.40 } })
local fading_widget = {
    WidgetTree = { RootWidget = fading_border },
    IsValid = function() return true end,
    GetFName = function() return { ToString = function() return "WG_Map_CampSite" end } end,
}

-- Controllable clock so the settle window is deterministic.
local fake_time = 0.0
os.clock = function() return fake_time end

--------------------------------------------------------------------------------
-- UE4SS stubs
--------------------------------------------------------------------------------

_G.print = function(s) logged[#logged + 1] = tostring(s):gsub("%s+$", "") end
_G.FName = function(s) return { __fname = s } end
_G.ExecuteInGameThread = function(fn) fn() end
_G.RegisterHook = function(target, pre, post)
    hooks[#hooks + 1] = { target = target, post = post }
end
_G.FindAllOf = function(cls)
    if cls == "WG_Map_Checkpoint_C" then return { checkpoint } end
    if cls == "WG_Map_CampSite_C" then return { fading_widget } end
    return nil
end
_G.LoopAsync = function(ms, fn) loop_ms = ms; fn() end

local ok, err = pcall(dofile, "mod/ColorblindMapMarkers/Scripts/main.lua")

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

local failures = {}
local function check(cond, msg) if not cond then failures[#failures + 1] = msg end end

check(ok, "main.lua raised: " .. tostring(err))
check(loop_ms == 1000, "expected LoopAsync(1000), got " .. tostring(loop_ms))
check(#hooks == 4, "expected 4 hook registrations, got " .. #hooks)

-- The regression: a fully transparent Border must be left completely untouched.
check(#outer_border.calls == 0,
      "transparent outer Border was recolored (" .. #outer_border.calls ..
      " calls) -- this is the 'solid blue square' bug")

-- The circle art must be recolored, keeping its original opaque alpha.
check(#circle_border.calls == 1, "circle Border not recolored")
if circle_border.calls[1] then
    local method, c = circle_border.calls[1][1], circle_border.calls[1][2]
    check(method == "SetBrushColor", "circle Border used " .. method)
    check(math.abs(c.A - 1.0) < 1e-6, "circle Border alpha not preserved: " .. tostring(c.A))
    check(c.B > c.R, "circle Border is not blue-dominant")
end

-- The red label must be recolored too.
check(#label.calls == 1, "TextBlock label not recolored")
if label.calls[1] then
    local c = label.calls[1][2]
    local spec = c.SpecifiedColor or c
    check(spec.B > spec.R, "label is not blue-dominant")
end

-- A widget mid fade-in must be left alone on first sight...
check(#fading_border.calls == 0,
      "wrote to a marker while its alpha was still moving -- this is the " ..
      "'marker almost never appears' bug")

-- ...and two samples inside the same frame must not count as "settled",
-- because they are identical regardless of what the animation is doing.
hooks[1].post()
check(#fading_border.calls == 0, "same-frame samples were treated as settled")

-- ...but once its alpha has held steady across the settle window, recolor it.
fake_time = fake_time + 0.2
hooks[1].post()
check(#fading_border.calls == 1,
      "settled marker was not recolored (" .. #fading_border.calls .. " calls)")
if fading_border.calls[1] then
    local c = fading_border.calls[1][2]
    check(math.abs(c.A - 0.40) < 1e-6,
          "settled marker lost its alpha: " .. tostring(c.A))
end

io.write("--- mod output ---\n")
for _, line in ipairs(logged) do io.write("  ", line, "\n") end
io.write("------------------\n")

if #failures == 0 then
    io.write("PASS\n")
else
    for _, f in ipairs(failures) do io.write("FAIL: ", f, "\n") end
    os.exit(1)
end
