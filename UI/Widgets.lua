-- Widgets: flat building blocks in the Allemano look, copied from Hush's Widgets.lua (no Blizzard textures or
-- templates, no Hush events) under this addon's own table. Kept in this file on purpose: the shared LibAllemano
-- library will replace it later.
local _, BB = ...

local Theme = BB.Theme
local addonName = BB.name

local W = {}
BB.W = W

local max, min, floor, abs = math.max, math.min, math.floor, math.abs
local tremove = table.remove

-- ---------------------------------------------------------------------------
-- Pixel-sized textures: re-sized when the UI scale changes
-- ---------------------------------------------------------------------------
local pixelItems = {}

local function applyPixel(item)
    local px = Theme:Pixel(item.frame)
    if item.axis == "h" then item.tex:SetHeight(px * item.n) else item.tex:SetWidth(px * item.n) end
end

-- Keep tex exactly n physical pixels high ("h") or wide ("w").
function W.PixelSize(tex, frame, axis, n)
    local item = { tex = tex, frame = frame, axis = axis, n = n or 1 }
    pixelItems[#pixelItems + 1] = item
    applyPixel(item)
end

function W.RefreshPixels()
    for i = 1, #pixelItems do applyPixel(pixelItems[i]) end
end

BB:RegisterEvent("UI_SCALE_CHANGED", W.RefreshPixels)
BB:RegisterEvent("DISPLAY_SIZE_CHANGED", W.RefreshPixels)

-- A solid colour texture.
function W.Fill(frame, colorKey, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    local r, g, b = Theme:Color(colorKey)
    t:SetColorTexture(r, g, b, alpha or 1)
    t.bbColor = { r, g, b, alpha or 1 } -- read by W.Round
    return t
end

-- A 1 px line along one side of frame ("top", "bottom", "left", "right").
function W.Line(frame, side, colorKey, layer)
    local t = W.Fill(frame, colorKey or "line", 1, layer or "BORDER")
    if side == "top" or side == "bottom" then
        local p = side == "top" and "TOP" or "BOTTOM"
        t:SetPoint(p .. "LEFT")
        t:SetPoint(p .. "RIGHT")
        W.PixelSize(t, frame, "h")
    else
        local p = side == "left" and "LEFT" or "RIGHT"
        t:SetPoint("TOP" .. p)
        t:SetPoint("BOTTOM" .. p)
        W.PixelSize(t, frame, "w")
    end
    return t
end

-- A 1 px border. Recolour with border:SetColor(r, g, b, a) (also after W.RoundBorder).
local SIDES = { "top", "bottom", "left", "right" }
local borderMethods = {}
function borderMethods:SetColor(r, g, b, a)
    self.color = { r, g, b, a or 1 }
    for _, side in ipairs(SIDES) do self[side]:SetColorTexture(r, g, b, a or 1) end
end

function W.Border(frame, colorKey)
    local b = setmetatable({}, { __index = borderMethods })
    for _, side in ipairs(SIDES) do b[side] = W.Line(frame, side, colorKey) end
    local r, g, bl = Theme:Color(colorKey or "line")
    b.color = { r, g, bl, 1 }
    return b
end

-- ---------------------------------------------------------------------------
-- Rounded corners. W.Round turns a flat texture into a rounded rectangle and W.RoundBorder does the same for a
-- W.Border; the callers keep using the same methods (SetColorTexture, SetAlpha, Show/Hide, SetPoint, SetColor).
-- Corners come from Media/ui (a white circle and rings, tinted); if those do not load the corners are square.
-- ---------------------------------------------------------------------------
local UI_MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\ui\\"
local QUADS = { -- corner point, texcoords of that quarter of the circle
    { "TOPLEFT", 0, 0.5, 0, 0.5 }, { "TOPRIGHT", 0.5, 1, 0, 0.5 },
    { "BOTTOMLEFT", 0, 0.5, 0.5, 1 }, { "BOTTOMRIGHT", 0.5, 1, 0.5, 1 },
}
local RING_SIZES = { 4, 6, 8, 10 }

local function ringFile(radius)
    local best = RING_SIZES[1]
    for _, s in ipairs(RING_SIZES) do
        if abs(s - radius) < abs(best - radius) then best = s end
    end
    return UI_MEDIA .. "ring" .. best
end

-- The largest radius that fits the current size (tiny frames get smaller corners).
local function fitRadius(radius, w, h)
    return max(0, min(radius, floor(min(w or 0, h or 0) / 2)))
end

function W.Round(tex, radius)
    if not tex or tex.round then return tex end
    radius = radius or Theme.radius.control
    local parent = tex:GetParent()
    local layer, sub = tex:GetDrawLayer()
    local R = {
        color = tex.bbColor and { unpack(tex.bbColor) } or { 1, 1, 1, 1 },
        alpha = tex:GetAlpha(), shown = tex:IsShown(), corners = {}, rects = {}, parts = {},
    }

    -- An invisible frame carries the geometry; the pieces are textures on the parent, so they keep the
    -- original draw layer (under the text, above the parent's background).
    local anchor = CreateFrame("Frame", nil, parent)
    anchor:SetSize(tex:GetSize())
    for i = 1, tex:GetNumPoints() do anchor:SetPoint(tex:GetPoint(i)) end
    tex:Hide()

    local function piece(list)
        local t = parent:CreateTexture(nil, layer, nil, sub)
        list[#list + 1] = t
        R.parts[#R.parts + 1] = t
        return t
    end
    for _, q in ipairs(QUADS) do
        local t = piece(R.corners)
        t.quad = q
        R.ok = t:SetTexture(UI_MEDIA .. "round") ~= false
        if R.ok then t:SetTexCoord(q[2], q[3], q[4], q[5]) end
    end
    local mid, left, right = piece(R.rects), piece(R.rects), piece(R.rects)

    local function layout()
        local r = fitRadius(radius, anchor:GetWidth(), anchor:GetHeight())
        for _, t in ipairs(R.corners) do
            t:ClearAllPoints()
            t:SetPoint(t.quad[1], anchor, t.quad[1])
            t:SetSize(max(r, 0.01), max(r, 0.01))
            t:SetShown(R.shown and r > 0)
        end
        mid:ClearAllPoints()
        mid:SetPoint("TOPLEFT", anchor, "TOPLEFT", r, 0)
        mid:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -r, 0)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -r)
        left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", r, r)
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -r, -r)
        right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, r)
        left:SetShown(R.shown and r > 0)
        right:SetShown(R.shown and r > 0)
    end
    local function paint()
        local c = R.color
        for _, t in ipairs(R.rects) do t:SetColorTexture(c[1], c[2], c[3], c[4]) end
        for _, t in ipairs(R.corners) do
            if R.ok then t:SetVertexColor(c[1], c[2], c[3], c[4]) else t:SetColorTexture(c[1], c[2], c[3], c[4]) end
        end
    end
    local function show(on)
        R.shown = on and true or false
        mid:SetShown(R.shown)
        layout()
    end
    anchor:SetScript("OnSizeChanged", layout)

    tex.round = R
    tex.SetColorTexture = function(_, r, g, b, a) R.color = { r, g, b, a or 1 } paint() end
    tex.SetVertexColor = tex.SetColorTexture
    tex.SetAlpha = function(_, a)
        R.alpha = a
        for _, t in ipairs(R.parts) do t:SetAlpha(a) end
    end
    tex.GetAlpha = function() return R.alpha end
    tex.Show = function() show(true) end
    tex.Hide = function() show(false) end
    tex.SetShown = function(_, on) show(on) end
    tex.IsShown = function() return R.shown end
    tex.IsVisible = function() return R.shown and parent:IsVisible() end
    tex.SetPoint = function(_, ...) anchor:SetPoint(...) end
    tex.ClearAllPoints = function() anchor:ClearAllPoints() end
    tex.SetAllPoints = function(_, rel) anchor:SetAllPoints(rel or parent) end
    tex.SetSize = function(_, w, h) anchor:SetSize(w, h) end
    tex.SetWidth = function(_, w) anchor:SetWidth(w) end
    tex.SetHeight = function(_, h) anchor:SetHeight(h) end
    tex.GetWidth = function() return anchor:GetWidth() end
    tex.GetHeight = function() return anchor:GetHeight() end
    tex.SetDrawLayer = function(_, l, s)
        for _, t in ipairs(R.parts) do t:SetDrawLayer(l, s) end
    end

    paint()
    tex:SetAlpha(R.alpha)
    show(R.shown)
    return tex
end

function W.RoundBorder(b, radius)
    if not b or b.round then return b end
    radius = radius or Theme.radius.control
    local frame = b.top:GetParent()
    local layer, sub = b.top:GetDrawLayer()
    for _, side in ipairs(SIDES) do b[side]:Hide() end

    local R = { corners = {}, lines = {} }
    local file = ringFile(radius)
    for _, q in ipairs(QUADS) do
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t.quad = q
        R.ok = t:SetTexture(file) ~= false
        if R.ok then t:SetTexCoord(q[2], q[3], q[4], q[5]) end
        R.corners[#R.corners + 1] = t
    end
    local top, bottom = frame:CreateTexture(nil, layer, nil, sub), frame:CreateTexture(nil, layer, nil, sub)
    local left, right = frame:CreateTexture(nil, layer, nil, sub), frame:CreateTexture(nil, layer, nil, sub)
    R.lines = { top, bottom, left, right }
    W.PixelSize(top, frame, "h")
    W.PixelSize(bottom, frame, "h")
    W.PixelSize(left, frame, "w")
    W.PixelSize(right, frame, "w")

    local function layout()
        local r = fitRadius(radius, frame:GetWidth(), frame:GetHeight())
        for _, t in ipairs(R.corners) do
            t:ClearAllPoints()
            t:SetPoint(t.quad[1], frame, t.quad[1])
            t:SetSize(max(r, 0.01), max(r, 0.01))
            t:SetShown(r > 0)
        end
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", r, 0)
        top:SetPoint("TOPRIGHT", -r, 0)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", r, 0)
        bottom:SetPoint("BOTTOMRIGHT", -r, 0)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", 0, -r)
        left:SetPoint("BOTTOMLEFT", 0, r)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", 0, -r)
        right:SetPoint("BOTTOMRIGHT", 0, r)
    end
    frame:HookScript("OnSizeChanged", layout)

    b.round = R
    b.SetColor = function(self, r, g, bl, a)
        self.color = { r, g, bl, a or 1 }
        for _, t in ipairs(R.lines) do t:SetColorTexture(r, g, bl, a or 1) end
        for _, t in ipairs(R.corners) do
            if R.ok then t:SetVertexColor(r, g, bl, a or 1) else t:SetColorTexture(r, g, bl, a or 1) end
        end
    end
    local c = b.color or { Theme:Color("line") }
    b:SetColor(c[1], c[2], c[3], c[4] or 1)
    layout()
    return b
end

-- A rounded panel: background fill and border in one call. Returns the fill and the border.
function W.Panel(frame, fillKey, borderKey, radius, alpha)
    local bg = W.Fill(frame, fillKey or "field", alpha or 1)
    bg:SetAllPoints()
    local border = W.Border(frame, borderKey or "line")
    W.Round(bg, radius)
    W.RoundBorder(border, radius)
    return bg, border
end

-- ---------------------------------------------------------------------------
-- Accent colour: everything registered here is recoloured when the accent changes
-- ---------------------------------------------------------------------------
local accentFns = {}

-- fn(r, g, b) runs now and on every accent change.
function W.OnAccent(fn)
    accentFns[#accentFns + 1] = fn
    fn(Theme:Accent())
end

function W.ApplyAccent()
    local r, g, b = Theme:Accent()
    for i = 1, #accentFns do accentFns[i](r, g, b) end
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
local fontItems = {}

function W.Text(parent, kind, delta, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Theme:SetFont(fs, kind, delta)
    fs:SetTextColor(Theme:Color(colorKey or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fontItems[#fontItems + 1] = { fs = fs, kind = kind, delta = delta }
    return fs
end

function W.RefreshFonts()
    for i = 1, #fontItems do
        local f = fontItems[i]
        Theme:SetFont(f.fs, f.kind, f.delta)
    end
end

-- ---------------------------------------------------------------------------
-- Tooltip (own, flat)
-- ---------------------------------------------------------------------------
local tip
function W.ShowTooltip(owner, text)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        W.Panel(tip, "field", "line", Theme.radius.control, 0.98)
        tip.text = W.Text(tip, "regular", -1, "text")
        tip.text:SetPoint("CENTER")
    end
    tip.text:SetText(text)
    tip:SetSize(tip.text:GetStringWidth() + 16, tip.text:GetStringHeight() + 10)
    tip:ClearAllPoints()
    -- below the owner; above it near the bottom of the screen
    if (owner:GetBottom() or 100) * owner:GetEffectiveScale() < 80 then
        tip:SetPoint("BOTTOM", owner, "TOP", 0, 4)
    else
        tip:SetPoint("TOP", owner, "BOTTOM", 0, -4)
    end
    tip:Show()
end

function W.HideTooltip()
    if tip then tip:Hide() end
end

-- ---------------------------------------------------------------------------
-- Icons drawn from rectangles and lines (no texture files)
-- ---------------------------------------------------------------------------
local function rect(box, x, y, w, h)
    local t = box:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", box, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    return t
end

local function line(frame, x1, y1, x2, y2, thickness)
    if not frame.CreateLine then return nil end
    local l = frame:CreateLine(nil, "ARTWORK")
    l:SetThickness(thickness)
    l:SetStartPoint("CENTER", frame, x1, y1)
    l:SetEndPoint("CENTER", frame, x2, y2)
    return l
end

local ICONS = {
    plus = function(f, s)
        local m = s / 2 - 1
        return { rect(f, 0, m, s, 2), rect(f, m, 0, 2, s) }
    end,
    close = function(f, s)
        local h = s / 2
        local a, b = line(f, -h, -h, h, h, 1.5), line(f, -h, h, h, -h, 1.5)
        if a then return { a, b } end
    end,
    chevronDown = function(f, s)
        local q = s / 4
        local a, b = line(f, -q * 1.5, q * 0.75, 0, -q * 0.75, 1.5), line(f, 0, -q * 0.75, q * 1.5, q * 0.75, 1.5)
        if a then return { a, b } end
    end,
}

-- Draws an icon in an even-sized box in the middle of frame; a text glyph stands in if lines are not supported.
function W.Icon(frame, name, size, fallbackGlyph)
    size = size - size % 2
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(size, size)
    box:SetPoint("CENTER")
    local parts = ICONS[name] and ICONS[name](box, size)
    if parts and #parts > 0 then
        local icon = { parts = parts, box = box }
        function icon:SetColor(r, g, b, a)
            for _, p in ipairs(self.parts) do p:SetColorTexture(r, g, b, a or 1) end
        end
        function icon:SetShown(shown) self.box:SetShown(shown) end
        return icon
    end
    local fs = W.Text(box, "semibold", 2)
    fs:SetPoint("CENTER")
    fs:SetText(fallbackGlyph or "?")
    return {
        box = box,
        SetColor = function(_, r, g, b, a) fs:SetTextColor(r, g, b, a or 1) end,
        SetShown = function(self, shown) self.box:SetShown(shown) end,
    }
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
-- A small square icon button. onClick(self, mouseButton).
function W.IconButton(parent, iconName, size, tooltip, onClick, fallbackGlyph)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 24, size or 24)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    W.Round(b.bg, Theme.radius.small)
    b.icon = W.Icon(b, iconName, 10, fallbackGlyph)
    b.icon:SetColor(Theme:Color("textDim"))
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        self.icon:SetColor(Theme:Color("text"))
        if tooltip then W.ShowTooltip(self, tooltip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        self.icon:SetColor(Theme:Color("textDim"))
        W.HideTooltip()
    end)
    b:RegisterForClicks("LeftButtonUp")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- A flat text button. style: "default", "accent", "ghost" (text only) or "danger".
-- b:SetLabel(text), b:SetAvailable(bool) (a greyed button does nothing).
function W.Button(parent, label, style, onClick)
    style = style or "default"
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(Theme.size.inputH - 6)
    b.style = style
    b.text = W.Text(b, "semibold", 0, style == "ghost" and "textDim" or "text")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(b.text:GetStringWidth() + 24)

    if style ~= "ghost" then
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        b.border = W.Border(b, "line")
        W.Round(b.bg)
        W.RoundBorder(b.border)
    end

    -- The accent button: the accent mixed into the field colour (so it is clearly lit, also when the accent is grey),
    -- bright text; lighter on hover with a lighter border, darker when pressed. A disabled one is flat with faint text.
    local function mix(from, to, t) return from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t end
    local function paintAccent(self)
        local field = { Theme:Color("field") }
        local accent = { Theme:Accent() }
        local amount, borderAmount = 0.42, 0.75
        if self.pressed then amount, borderAmount = 0.30, 0.6
        elseif self.hover then amount, borderAmount = 0.56, 1 end
        self.bg:SetColorTexture(mix(field, accent, amount))
        local r, g, bl = mix(field, accent, borderAmount)
        if self.hover and not self.pressed then r, g, bl = mix({ r, g, bl }, { 1, 1, 1 }, 0.25) end
        self.border:SetColor(r, g, bl, 1)
        self.text:SetTextColor(Theme:Color("text"))
    end

    local function paint(self)
        if self.unavailable then
            if self.bg then
                self.bg:SetColorTexture(Theme:Color("field"))
                self.border:SetColor(Theme:Color("line"))
            end
            self.text:SetTextColor(Theme:Color("textFaint"))
            return
        end
        if style == "accent" then
            paintAccent(self)
        elseif style == "danger" then
            self.bg:SetColorTexture(Theme:Color("danger"))
            self.border:SetColor(Theme:Color("danger"))
            self.text:SetTextColor(Theme:Color("text"))
        elseif style == "ghost" then
            self.text:SetTextColor(Theme:Color("textDim"))
        else
            self.bg:SetColorTexture(Theme:Color("field"))
            self.border:SetColor(Theme:Color("line"))
            self.text:SetTextColor(Theme:Color("text"))
        end
    end
    W.OnAccent(function() paint(b) end)

    b:SetScript("OnEnter", function(self)
        if self.unavailable then
            if self.disabledTip then W.ShowTooltip(self, self.disabledTip) end
            return
        end
        self.hover = true
        if style == "accent" then paintAccent(self)
        elseif style == "danger" then self.bg:SetAlpha(0.85)
        elseif style == "ghost" then self.text:SetTextColor(Theme:Color("text"))
        else self.bg:SetColorTexture(Theme:Color("selected")) end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover, self.pressed = false, false
        W.HideTooltip()
        if style == "danger" then self.bg:SetAlpha(1) end
        paint(self)
    end)
    b:SetScript("OnMouseDown", function(self)
        if self.unavailable then return end
        self.pressed = true
        if style == "accent" then paintAccent(self) end
    end)
    b:SetScript("OnMouseUp", function(self)
        self.pressed = false
        if not self.unavailable then paint(self) end
    end)

    function b:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(math.max(self.minWidth or 0, self.text:GetStringWidth() + 24))
    end
    -- tip: what to say when somebody points at it while it is off
    function b:SetAvailable(on, reason)
        self.unavailable = not on
        self.disabledTip = (not on) and reason or nil
        self.hover, self.pressed = false, false
        paint(self)
    end

    b:SetScript("OnClick", function(self, ...)
        if self.unavailable then return end
        if onClick then onClick(self, ...) end
    end)
    return b
end

-- ---------------------------------------------------------------------------
-- Edit box (one line, or several for a note)
-- ---------------------------------------------------------------------------
function W.EditBox(parent, placeholder, height, multiline)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetHeight(height or Theme.size.searchH)
    e:SetAutoFocus(false)
    Theme:SetFont(e, "regular", 0)
    fontItems[#fontItems + 1] = { fs = e, kind = "regular", delta = 0 }
    e:SetTextColor(Theme:Color("text"))
    if multiline then
        e:SetMultiLine(true)
        e:SetTextInsets(10, 10, 8, 8)
        if e.SetJustifyV then e:SetJustifyV("TOP") end
    else
        e:SetTextInsets(10, 10, 0, 0)
    end

    e.bg = W.Fill(e, "field", 1)
    e.bg:SetAllPoints()
    e.border = W.Border(e, "line")
    W.Round(e.bg)
    W.RoundBorder(e.border)

    e.placeholder = W.Text(e, "regular", 0, "textFaint")
    if multiline then e.placeholder:SetPoint("TOPLEFT", 10, -8) else e.placeholder:SetPoint("LEFT", 10, 0) end
    e.placeholder:SetText(placeholder or "")

    local function update(self)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end
    e:SetScript("OnEditFocusGained", function(self)
        self.border:SetColor(Theme:Accent())
        update(self)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self.border:SetColor(Theme:Color("line"))
        update(self)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if multiline then
        -- a note is one paragraph: Enter finishes it
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end
    e:HookScript("OnTextChanged", update)
    return e
end

-- ---------------------------------------------------------------------------
-- Badge (a counter in a pill)
-- ---------------------------------------------------------------------------
function W.Badge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(16)
    b.bg = b:CreateTexture(nil, "ARTWORK")
    b.bg:SetAllPoints()
    W.Round(b.bg, 8)
    W.OnAccent(function(r, g, bl) b.bg:SetColorTexture(r, g, bl, 1) end)
    b.text = W.Text(b, "semibold", -2, "sidebar")
    b.text:SetPoint("CENTER", 0, 0)
    function b:SetCount(n)
        if not n or n <= 0 then self:Hide() return end
        self.text:SetText(n > 99 and "99+" or tostring(n))
        self:SetWidth(max(16, self.text:GetStringWidth() + 8))
        self:Show()
    end
    b:Hide()
    return b
end

-- A status label in a rounded outline ("Taken by Bearhug"). colorKey: a palette key. b:SetText(text, colorKey).
function W.Tag(parent, colorKey, delta)
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(22)
    t.border = W.Border(t, colorKey or "line")
    W.RoundBorder(t.border, Theme.radius.small)
    t.text = W.Text(t, "semibold", delta or -1, colorKey or "textDim")
    t.text:SetPoint("CENTER")
    function t:SetText(text, key)
        self.text:SetText(text)
        if key then
            self.text:SetTextColor(Theme:Color(key))
            self.border:SetColor(Theme:Color(key))
        end
        self:SetWidth(Theme:Snap(self.text:GetStringWidth() + 18, self)) -- whole pixels, so the outline is sharp
    end
    return t
end

-- ---------------------------------------------------------------------------
-- Progress bar: bar:SetProgress(fraction, colorKey or nil for the accent)
-- ---------------------------------------------------------------------------
function W.ProgressBar(parent, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(height or 6)
    bar.track = W.Fill(bar, "line", 1)
    bar.track:SetAllPoints()
    W.Round(bar.track, 3)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetWidth(1)
    W.Round(bar.fill, 3)
    bar.value, bar.key = 0, nil
    local function paint()
        if bar.key then bar.fill:SetColorTexture(Theme:Color(bar.key)) else bar.fill:SetColorTexture(Theme:Accent()) end
    end
    function bar:SetProgress(fraction, key)
        fraction = max(0, min(1, fraction or 0))
        self.value, self.key = fraction, key
        self.fill:SetShown(fraction > 0)
        self.fill:SetWidth(max(1, (self:GetWidth() or 0) * fraction))
        paint()
    end
    bar:SetScript("OnSizeChanged", function(self) self:SetProgress(self.value, self.key) end)
    W.OnAccent(paint)
    return bar
end

-- ---------------------------------------------------------------------------
-- Frame pool (reused cards and rows)
-- ---------------------------------------------------------------------------
function W.Pool(create, reset)
    local pool = { free = {}, active = {} }
    function pool:Acquire()
        local obj = tremove(self.free) or create()
        self.active[#self.active + 1] = obj
        obj:Show()
        return obj
    end
    function pool:ReleaseAll()
        for i = #self.active, 1, -1 do
            local obj = self.active[i]
            obj:Hide()
            obj:ClearAllPoints()
            if reset then reset(obj) end
            self.free[#self.free + 1] = obj
            self.active[i] = nil
        end
    end
    return pool
end

-- ---------------------------------------------------------------------------
-- Thin scrollbar. onScroll(newOffset) runs while dragging; call :Update(offset, contentH, viewH) after drawing.
-- ---------------------------------------------------------------------------
function W.Scrollbar(parent, onScroll)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPRIGHT", -2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetWidth(4)
    bar:SetFrameLevel(parent:GetFrameLevel() + 10)
    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(4)
    thumb.tex = W.Fill(thumb, "line", 1, "OVERLAY")
    thumb.tex:SetAllPoints()
    W.Round(thumb.tex, 2)
    thumb:EnableMouse(true)
    bar.thumb = thumb
    bar.offset, bar.maxOffset = 0, 0

    -- OnUpdate only while the mouse button is held.
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        self.startY = cy / self:GetEffectiveScale()
        self.startOffset = bar.offset
        self.tex:SetColorTexture(Theme:Color("textFaint"))
        self:SetScript("OnUpdate", function(s)
            -- stop if the button was released outside the game frame
            if not IsMouseButtonDown("LeftButton") then
                s:SetScript("OnUpdate", nil)
                s.tex:SetColorTexture(Theme:Color("line"))
                return
            end
            local _, y = GetCursorPosition()
            y = y / s:GetEffectiveScale()
            local trackH = bar:GetHeight() - s:GetHeight()
            if trackH > 0 then onScroll(s.startOffset + (s.startY - y) / trackH * bar.maxOffset) end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self.tex:SetColorTexture(Theme:Color("line"))
    end)

    function bar:Update(offset, contentH, viewH)
        self.offset = offset
        self.maxOffset = max(0, contentH - viewH)
        if contentH <= viewH or viewH <= 0 then
            self:Hide()
            return
        end
        self:Show()
        local trackH = self:GetHeight()
        local thumbH = max(24, trackH * viewH / contentH)
        local pos = (trackH - thumbH) * (offset / self.maxOffset)
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -pos)
    end

    bar:Hide()
    return bar
end

-- A scrolling area: area.content is the frame to put things in (set its height with :SetContentHeight(h)); the mouse
-- wheel and a thin scrollbar move it.
function W.ScrollArea(parent)
    local area = CreateFrame("ScrollFrame", nil, parent)
    area.content = CreateFrame("Frame", nil, area)
    area.content:SetSize(1, 1)
    area:SetScrollChild(area.content)
    area.offset, area.contentH = 0, 0
    area:EnableMouseWheel(true)

    area.bar = W.Scrollbar(area, function(offset) area:ScrollTo(offset) end)

    function area:ScrollTo(offset)
        local viewH = self:GetHeight() or 0
        self.offset = max(0, min(offset or 0, max(0, self.contentH - viewH)))
        self:SetVerticalScroll(self.offset)
        self.bar:Update(self.offset, self.contentH, viewH)
    end
    function area:SetContentHeight(h)
        self.contentH = h
        self.content:SetHeight(max(1, h))
        self:ScrollTo(self.offset)
    end
    area:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.offset - delta * 48) end)
    area:SetScript("OnSizeChanged", function(self, w)
        self.content:SetWidth(max(1, w or 1))
        self:ScrollTo(self.offset)
    end)
    return area
end

-- ---------------------------------------------------------------------------
-- Dashed accent border (the item slot of the post dialog). Call :Layout() after resizing.
-- ---------------------------------------------------------------------------
function W.DashedBorder(frame, dash, gap)
    dash, gap = dash or 6, gap or 4
    local d = { frame = frame, textures = {} }
    function d:Layout(colorKey)
        local w, h = frame:GetWidth(), frame:GetHeight()
        local px = Theme:Pixel(frame)
        local r, g, b
        if colorKey then r, g, b = Theme:Color(colorKey) else r, g, b = Theme:Accent() end
        local n = 0
        local function seg(point, x, y, sw, sh)
            n = n + 1
            local t = self.textures[n]
            if not t then
                t = frame:CreateTexture(nil, "OVERLAY")
                self.textures[n] = t
            end
            t:ClearAllPoints()
            t:SetPoint(point, frame, point, x, y)
            t:SetSize(sw, sh)
            t:SetColorTexture(r, g, b, 1)
            t:Show()
        end
        for x = 0, w - 1, dash + gap do
            local len = min(dash, w - x)
            seg("TOPLEFT", x, 0, len, px)
            seg("BOTTOMLEFT", x, 0, len, px)
        end
        for y = 0, h - 1, dash + gap do
            local len = min(dash, h - y)
            seg("TOPLEFT", 0, -y, px, len)
            seg("TOPRIGHT", 0, -y, px, len)
        end
        for i = n + 1, #self.textures do self.textures[i]:Hide() end
    end
    return d
end

-- ---------------------------------------------------------------------------
-- Menu (own, flat; no UIDropDownMenu, so no taint). items: { text, onClick, disabled, checked, danger }
-- ---------------------------------------------------------------------------
local MENU_ITEM_H = 24
local menu

function W.CloseMenus()
    if menu then menu:Hide() end
end

function W.IsMenuOpen()
    return menu ~= nil and menu:IsShown()
end

local function menuButton(m, i)
    local b = m.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, m)
    b:SetHeight(MENU_ITEM_H)
    b.hover = W.Fill(b, "selected", 1)
    b.hover:SetAllPoints()
    b.hover:Hide()
    W.Round(b.hover, Theme.radius.small)
    b.hover:ClearAllPoints()
    b.hover:SetPoint("TOPLEFT", 4, 0)
    b.hover:SetPoint("BOTTOMRIGHT", -4, 0)
    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetSize(6, 6)
    b.check:SetPoint("LEFT", 10, 0)
    W.Round(b.check, 3)
    W.OnAccent(function(r, g, bl) b.check:SetColorTexture(r, g, bl, 1) end)
    b.text = W.Text(b, "regular", 0, "text")
    b.text:SetPoint("LEFT", 24, 0)
    b:SetScript("OnEnter", function(self) if not self.item.disabled then self.hover:Show() end end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", function(self)
        local item = self.item
        if item.disabled then return end
        W.CloseMenus()
        if item.onClick then item.onClick() end
    end)
    m.buttons[i] = b
    return b
end

local function getMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(20)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    W.Panel(menu, "field", "line", Theme.radius.control, 0.98)
    menu.buttons = {}
    menu:Hide()
    return menu
end

-- Lays out the part of the list that is on show (a long list scrolls with the mouse wheel).
local MENU_MAX = 14
local function layoutMenu(m)
    local items = m.items
    local visible = math.min(#items, MENU_MAX)
    m.offset = math.max(0, math.min(m.offset, #items - visible))
    local y = 4
    for i = 1, visible do
        local item = items[m.offset + i]
        local b = menuButton(m, i)
        b.item = item
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", 0, -y)
        b.check:SetShown(item.checked == true)
        b.text:SetText(item.text)
        b.text:SetTextColor(Theme:Color(item.disabled and "textFaint" or item.danger and "danger" or "text"))
        b:Show()
        y = y + MENU_ITEM_H
    end
    for i = visible + 1, #m.buttons do m.buttons[i]:Hide() end
    m:SetSize(m.width, y + 4)
end

-- anchor: a frame (the menu opens below it) or nil (at the cursor).
function W.OpenMenu(items, anchor)
    W.HideTooltip()
    local m = getMenu()
    m.items, m.offset = items, 0
    if not m.measure then
        m.measure = W.Text(m, "regular", 0, "text")
        m.measure:Hide()
        m:EnableMouseWheel(true)
        m:SetScript("OnMouseWheel", function(self, delta)
            self.offset = self.offset - delta * 3
            layoutMenu(self)
        end)
    end
    local width = (anchor and anchor:GetWidth()) or 160
    for _, item in ipairs(items) do
        m.measure:SetText(item.text)
        width = max(width, m.measure:GetStringWidth() + 52)
    end
    m.width = width
    -- the fonts of the buttons follow the text settings
    layoutMenu(m)
    for _, b in ipairs(m.buttons) do Theme:SetFont(b.text, "regular", 0) end
    m:ClearAllPoints()
    if anchor then
        m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        local x, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, cy / scale)
    end
    m:Show()
end

-- A click anywhere else closes the menu.
do
    local watcher = CreateFrame("Frame")
    if pcall(watcher.RegisterEvent, watcher, "GLOBAL_MOUSE_DOWN") then
        watcher:SetScript("OnEvent", function()
            if W.IsMenuOpen() and not menu:IsMouseOver() then W.CloseMenus() end
        end)
    else
        -- no such event here: an invisible full-screen catcher below the menu
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(1)
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", function() W.CloseMenus() end)
        catcher:Hide()
        hooksecurefunc(W, "OpenMenu", function() catcher:Show() end)
        hooksecurefunc(W, "CloseMenus", function() catcher:Hide() end)
    end
end

-- ---------------------------------------------------------------------------
-- Choices: a segmented control and a dropdown. Both have :Set(value) (no callback) and call onChange(value).
-- ---------------------------------------------------------------------------
-- options: { { value, label, disabled = true, tooltip = "Coming soon" }, ... }
function W.Segment(parent, options, onChange)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(26)
    s.buttons = {}
    local x = 0
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, s)
        b.value, b.disabled, b.tip, b.color = opt.value, opt.disabled, opt.tooltip, opt.color
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        W.Round(b.bg, Theme.radius.small)
        b.border = W.Border(b, "line")
        W.RoundBorder(b.border, Theme.radius.small)
        b.text = W.Text(b, "semibold", -1, "textDim")
        b.text:SetPoint("CENTER")
        b.text:SetText(opt.label)
        local w = max(40, b.text:GetStringWidth() + 28)
        b:SetSize(w, 26)
        b:SetPoint("LEFT", x, 0)
        x = x + w + 6
        b:SetScript("OnClick", function(self)
            if self.disabled then return end
            s:Set(self.value)
            if onChange then onChange(self.value) end
        end)
        b:SetScript("OnEnter", function(self)
            if self.disabled then
                if self.tip then W.ShowTooltip(self, self.tip) end
            elseif self.value ~= s.value then
                self.text:SetTextColor(Theme:Color("text"))
            end
        end)
        b:SetScript("OnLeave", function() W.HideTooltip() s:Set(s.value) end)
        s.buttons[i] = b
    end
    s:SetWidth(x - 6)
    function s:Set(value)
        self.value = value
        local colored = not BB.db or BB.db.settings.typeColors ~= false
        for _, b in ipairs(self.buttons) do
            -- an option may have a colour of its own (the kinds of bounty); the others use the accent
            local r, g, bl
            if b.color and colored then r, g, bl = Theme:Color(b.color) else r, g, bl = Theme:Accent() end
            if b.value == value and not b.disabled then
                b.bg:SetColorTexture(r, g, bl, 0.22)
                b.border:SetColor(r, g, bl, 1)
                b.text:SetTextColor(Theme:Color("text"))
            else
                b.bg:SetColorTexture(Theme:Color("field"))
                b.border:SetColor(Theme:Color("line"))
                if b.color and colored and not b.disabled then
                    b.text:SetTextColor(r, g, bl)
                else
                    b.text:SetTextColor(Theme:Color(b.disabled and "textFaint" or "textDim"))
                end
            end
        end
    end
    W.OnAccent(function() if s.value ~= nil then s:Set(s.value) end end)
    return s
end

-- getOptions() -> { { value, label, disabled }, ... }
function W.Dropdown(parent, width, getOptions, onChange)
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(width or 200, 28)
    d.bg = W.Fill(d, "field", 1)
    d.bg:SetAllPoints()
    d.border = W.Border(d, "line")
    W.Round(d.bg)
    W.RoundBorder(d.border)
    d.text = W.Text(d, "regular", 0, "text")
    d.text:SetPoint("LEFT", 10, 0)
    d.text:SetWidth((width or 200) - 36)
    d.arrow = W.Icon(d, "chevronDown", 8, "v")
    d.arrow.box:ClearAllPoints()
    d.arrow.box:SetPoint("RIGHT", -10, 0)
    d.arrow:SetColor(Theme:Color("textDim"))

    function d:Set(value)
        self.value = value
        local label = tostring(value)
        for _, opt in ipairs(getOptions()) do
            if opt.value == value then label = opt.label break end
        end
        self.text:SetText(label)
    end

    d:SetScript("OnEnter", function(self) self.border:SetColor(Theme:Color("textFaint")) end)
    d:SetScript("OnLeave", function(self) self.border:SetColor(Theme:Color("line")) end)
    d:SetScript("OnClick", function(self)
        if W.IsMenuOpen() then W.CloseMenus() return end
        local items = {}
        for _, opt in ipairs(getOptions()) do
            items[#items + 1] = {
                text = opt.label, disabled = opt.disabled, checked = opt.value == self.value,
                onClick = function()
                    self:Set(opt.value)
                    if onChange then onChange(opt.value) end
                end,
            }
        end
        W.OpenMenu(items, self)
    end)
    return d
end
