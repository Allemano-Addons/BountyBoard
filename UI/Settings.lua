-- Settings: a small window (/bb settings, or the Settings button in the title bar). Everything is saved in
-- BB.db.settings and takes effect at once.
local _, BB = ...

local Settings = {}
BB.Settings = Settings

local Theme, W, L = BB.Theme, BB.W, BB.L
local format = string.format

local WIDTH, PAD = 360, 20
local FRAME_NAME = "AllemanoBountyBoardSettingsFrame"

local frame
local refreshers = {}

local SCALES = { 0.7, 0.8, 0.9, 1 }
local HISTORY_DAYS = { 7, 14, 30, 60 }

local function options(list, label)
    local out = {}
    for _, v in ipairs(list) do out[#out + 1] = { value = v, label = label(v) } end
    return out
end

local TABS = {
    { value = "board", label = "Board" }, { value = "mine", label = "My Bounties" },
    { value = "jobs", label = "My Jobs" }, { value = "history", label = "History" },
    { value = "last", label = "The tab I used last" },
}

-- Changes a setting and lets the rest of the addon know.
function Settings.Set(key, value)
    if not BB.db then return end
    BB.db.settings[key] = value
    if key == "scale" and BB.Main then BB.Main.ApplyScale() end
    if key == "historyDays" and BB.Data then BB.Data.Prune() end
    if key == "soundChoice" and BB.Toast then BB.Toast.Play(value) end -- a preview
    BB:Fire("SETTINGS_CHANGED", key, value)
    for _, fn in ipairs(refreshers) do fn() end
end

function Settings.Get(key)
    return BB.db and BB.db.settings[key]
end

local function heading(parent, text, y)
    local fs = W.Text(parent, "semibold", 1, "text")
    W.OnAccent(function(r, g, b) fs:SetTextColor(r, g, b) end)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
    fs:SetText(string.upper(text))
    return fs
end

local function checkbox(parent, text, key, y)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(WIDTH - 2 * PAD, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    W.Panel(box, "field", "line", Theme.radius.small, 1)
    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetSize(8, 8)
    tick:SetPoint("CENTER")
    W.OnAccent(function(r, g, bl) tick:SetColorTexture(r, g, bl, 1) end)
    local label = W.Text(b, "regular", 0, "text")
    label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    label:SetText(text)
    local function refresh() tick:SetShown(Settings.Get(key) ~= false) end
    b:SetScript("OnClick", function() Settings.Set(key, Settings.Get(key) == false) end)
    refreshers[#refreshers + 1] = refresh
    b.Refresh = refresh
    return b
end

local function dropdown(parent, text, y, getOptions, key)
    local fs = W.Text(parent, "regular", 0, "textDim")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
    fs:SetText(text)
    local d = W.Dropdown(parent, 170, getOptions, function(value) Settings.Set(key, value) end)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -(y - 5))
    refreshers[#refreshers + 1] = function() d:Set(Settings.Get(key)) end
    return d
end

local function build()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(WIDTH, 808)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    W.Panel(frame, "window", "line", Theme.radius.panel, 0.98)
    if UISpecialFrames then table.insert(UISpecialFrames, FRAME_NAME) end

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(Theme.size.titleH)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local title = W.Text(bar, "heading", 4, "text")
    title:SetPoint("LEFT", PAD, 0)
    title:SetText(L["Settings"])
    W.Line(bar, "bottom", "line")
    local close = W.IconButton(bar, "close", 24, nil, function() Settings.Hide() end, "x")
    close:SetPoint("RIGHT", -12, 0)

    local y = Theme.size.titleH + 16
    heading(frame, L["Notifications"], y)
    y = y + 28
    checkbox(frame, L["Show notifications"], "toasts", y)
    y = y + 28
    checkbox(frame, L["Somebody took my bounty"], "toastTaken", y)
    y = y + 28
    checkbox(frame, L["Delivery verified"], "toastDelivery", y)
    y = y + 28
    checkbox(frame, L["Payment verified"], "toastPayment", y)
    y = y + 28
    y = y + 4
    dropdown(frame, L["Sound"], y, function() return BB.Toast.SoundOptions() end, "soundChoice")
    y = y + 28
    checkbox(frame, L["Colour bounties by type"], "typeColors", y)
    y = y + 40

    heading(frame, L["Guild goals"], y)
    y = y + 34
    dropdown(frame, L["Who can post them"], y, function()
        return {
            { value = 0, label = L["Guild Master only"] }, { value = 1, label = L["Rank 1 and up"] },
            { value = 2, label = L["Rank 2 and up"] }, { value = 3, label = L["Rank 3 and up"] },
            { value = 99, label = L["Everyone"] },
        }
    end, "guildPostRank")
    y = y + 44

    heading(frame, L["Hunting"], y)
    y = y + 28
    checkbox(frame, L["Count kills of open hunts automatically"], "autoHunt", y)
    y = y + 40

    heading(frame, L["Text"], y)
    y = y + 34
    dropdown(frame, L["Font"], y, function()
        return Theme:FontOptions()
    end, "font")
    y = y + 38
    dropdown(frame, L["Text size"], y, function()
        return { { value = "S", label = L["Small"] }, { value = "M", label = L["Medium"] }, { value = "L", label = L["Large"] } }
    end, "textSize")
    y = y + 44

    heading(frame, L["Window"], y)
    y = y + 34
    dropdown(frame, L["Size"], y, function()
        return options(SCALES, function(v) return format("%d%%", v * 100) end)
    end, "scale")
    y = y + 38
    dropdown(frame, L["Open on"], y, function()
        local list = {}
        for i, t in ipairs(TABS) do list[i] = { value = t.value, label = L[t.label] } end
        return list
    end, "defaultTab")
    y = y + 38
    dropdown(frame, L["Keep history for"], y, function()
        return options(HISTORY_DAYS, function(v) return format(L["%d days"], v) end)
    end, "historyDays")
    y = y + 44
    local reset = W.Button(frame, L["Reset window position"], "default", function()
        if BB.Main then BB.Main.ResetPosition() end
    end)
    reset:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    y = y + 38
    checkbox(frame, L["Show the launcher button"], "launcherShown", y)

    frame:SetScript("OnHide", function() W.CloseMenus() end)
end

function Settings.Show()
    if not frame then build() end
    for _, fn in ipairs(refreshers) do fn() end
    frame:Show()
    frame:Raise()
end

function Settings.Hide()
    if frame then frame:Hide() end
end

function Settings.Toggle()
    if frame and frame:IsShown() then Settings.Hide() else Settings.Show() end
end

function Settings.Frame() return frame end
