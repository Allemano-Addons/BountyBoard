-- Theme: the colours, sizes and fonts of the Allemano look, copied from Hush's Theme.lua (the "Allemano" theme only),
-- under this addon's own table. Kept in this file on purpose: the shared LibAllemano library will replace it later.
local addonName, BB = ...

local Theme = {}
BB.Theme = Theme

local C = BB.Compat
local floor, strlower = math.floor, string.lower

local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end
Theme.Hex = hex

-- The palette of the Allemano theme (near-black, neutral).
Theme.colors = {
    window    = { hex("121418") },
    sidebar   = { hex("0E1013") },
    field     = { hex("181B20") },
    selected  = { hex("1F232A") },
    line      = { hex("262A31") },
    text      = { hex("ECEDEF") },
    textDim   = { hex("9098A1") },
    textFaint = { hex("6E757E") },
    good      = { hex("3FC77F") },
    warn      = { hex("E8A33D") },
    danger    = { hex("E0564F") },
    -- one colour for each kind of bounty (the tag and the stripe of a card)
    typeFarm  = { hex("E8C547") },
    typeCraft = { hex("F0763A") },
    typeHelp  = { hex("4F9BFF") },
    typeKos   = { hex("E5484D") },
    typeGuild = { hex("A98BFF") },
}

-- Corner radii in UI units.
Theme.radius = { control = 6, panel = 10, small = 4 }

Theme.size = {
    windowW = 780,
    windowH = 540,
    windowMinW = 640,
    windowMinH = 420,
    titleH = 44,
    tabH = 34,
    filterH = 26,
    searchH = 28,
    bottomH = 52,
    padding = 14,
    gap = 10,
    cardH = 116,
    inputH = 34,
}

Theme.textSizes = { S = 11, M = 12, L = 14 }

function Theme:Color(key)
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

-- The accent: hot magenta unless the saved settings say another "RRGGBB".
Theme.DEFAULT_ACCENT = "E040A0"
function Theme:Accent()
    local s = BB.db and BB.db.settings
    local value = s and s.accent
    if type(value) ~= "string" or #value ~= 6 or not tonumber(value, 16) then value = Theme.DEFAULT_ACCENT end
    return hex(value)
end

-- Hover is the accent a little lighter (E040A0 gives about E85CB0), pressed a little darker (about C4338A).
function Theme:AccentHover()
    local r, g, b = self:Accent()
    return r + (1 - r) * 0.15, g + (1 - g) * 0.15, b + (1 - b) * 0.15
end
function Theme:AccentPressed()
    local r, g, b = self:Accent()
    return r * 0.88, g * 0.88, b * 0.88
end

function Theme:TextSize(delta)
    local s = BB.db and BB.db.settings and BB.db.settings.textSize or "M"
    return (self.textSizes[s] or 12) + (delta or 0)
end

-- ---------------------------------------------------------------------------
-- Fonts: Barlow (shipped in Media/Fonts) when the game accepts the files, otherwise the game's own font.
-- ---------------------------------------------------------------------------
local FONT_DIR = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"
local FALLBACK = "Fonts\\FRIZQT__.TTF"

local BUNDLED = {
    regular  = FONT_DIR .. "Barlow-Regular.ttf",
    medium   = FONT_DIR .. "Barlow-Medium.ttf",
    semibold = FONT_DIR .. "Barlow-SemiBold.ttf",
    heading  = FONT_DIR .. "BarlowCondensed-SemiBold.ttf",
}

Theme.fonts = { regular = FALLBACK, medium = FALLBACK, semibold = FALLBACK, heading = FALLBACK }

local function normalizePath(p) return p and strlower((p:gsub("/", "\\"))) or "" end

local probe
-- Does the game load this font file? Newer clients answer true or false, older ones nil (then the path is compared).
local function fontLoads(path)
    probe = probe or UIParent:CreateFontString(nil, "BACKGROUND")
    probe:SetFont(FALLBACK, 12, "")
    local ok = probe:SetFont(path, 12, "")
    if ok == true then return true end
    if ok == false then return false end
    return normalizePath(probe:GetFont()) == normalizePath(path)
end

-- The choices of the settings: Barlow (shipped) or one of the game's own fonts for everything.
Theme.fontChoices = {
    { value = "barlow", label = "Barlow" },
    { value = "frizqt", label = "Friz Quadrata (game)", path = "Fonts\\FRIZQT__.TTF" },
    { value = "arialn", label = "Arial Narrow (game)", path = "Fonts\\ARIALN.TTF" },
    { value = "morpheus", label = "Morpheus (game)", path = "Fonts\\MORPHEUS.TTF" },
    { value = "skurri", label = "Skurri (game)", path = "Fonts\\SKURRI.TTF" },
}

local function sharedMedia()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

-- The fonts to choose from: ours and the game's, and every font LibSharedMedia has registered (from other addons)
-- that this client accepts.
function Theme:FontOptions()
    local list = {}
    for _, c in ipairs(self.fontChoices) do list[#list + 1] = { value = c.value, label = c.label } end
    local media = sharedMedia()
    if media then
        local names = {}
        for _, name in ipairs(media:List("font") or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local path = media:Fetch("font", name, true)
            if path and fontLoads(path) then list[#list + 1] = { value = "lsm:" .. name, label = name } end
        end
    end
    return list
end

function Theme:ApplyFonts()
    local choice = BB.db and BB.db.settings.font or "barlow"
    local own
    for _, c in ipairs(self.fontChoices) do
        if c.value == choice then own = c.path end
    end
    if type(choice) == "string" and choice:sub(1, 4) == "lsm:" then
        local media = sharedMedia()
        own = media and media:Fetch("font", choice:sub(5), true) or FALLBACK
    end
    for kind, path in pairs(BUNDLED) do
        if own then
            self.fonts[kind] = fontLoads(own) and own or FALLBACK
        else
            self.fonts[kind] = fontLoads(path) and path or FALLBACK
        end
    end
    self.fontStatus = self.fonts.regular == FALLBACK and "game font" or (own and "chosen font" or "Barlow")
end

-- Apply a font to a FontString. kind: regular, medium, semibold or heading.
function Theme:SetFont(fs, kind, delta)
    fs:SetFont(self.fonts[kind or "regular"] or FALLBACK, self:TextSize(delta), "")
    fs:SetShadowOffset(0, 0)
end

-- ---------------------------------------------------------------------------
-- Pixel-perfect sizing
-- ---------------------------------------------------------------------------
-- The size of one physical pixel in the frame's own units.
function Theme:Pixel(frame)
    local _, physH = C.GetPhysicalScreenSize()
    return 768 / physH / (frame or UIParent):GetEffectiveScale()
end

-- A size rounded to whole physical pixels.
function Theme:Snap(value, frame)
    local px = self:Pixel(frame)
    return floor(value / px + 0.5) * px
end

Theme:ApplyFonts()

-- The saved choice is known at ADDON_LOADED; a change in the settings is applied at once.
local function reapply()
    Theme:ApplyFonts()
    if BB.W then BB.W.RefreshFonts() end
    if BB.Board then BB.Board.Request() end
    if BB.Main then BB.Main.Update() end
end
BB:On("DB_READY", reapply)
BB:On("SETTINGS_CHANGED", function(key) if key == "font" or key == "textSize" then reapply() end end)
