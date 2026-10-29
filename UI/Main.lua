-- Main: the window (title bar, tabs, the board, the bottom bar). /bb and /bounty toggle it.
local _, BB = ...

local Main = {}
BB.Main = Main

local Theme, W, C, L, Data, Comm = BB.Theme, BB.W, BB.Compat, BB.L, BB.Data, BB.Comm
local format = string.format

local FRAME_NAME = "AllemanoBountyBoardFrame"
local TABS = {
    { key = "board", label = "Board" },
    { key = "mine", label = "My Bounties" },
    { key = "jobs", label = "My Jobs" },
    { key = "history", label = "History" },
}

local frame, tabButtons, tab = nil, {}, "board"
local ticker

function Main.ApplyScale()
    if frame and BB.db then frame:SetScale(BB.db.settings.scale or 1) end
end

local function savePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    BB.db.settings.window = { point = point, relPoint = relPoint, x = x, y = y }
end

local function restorePosition()
    local w = BB.db and BB.db.settings.window
    frame:ClearAllPoints()
    if w and w.point then
        frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- Title, counters and the bottom bar follow the data.
function Main.Update()
    if not frame then return end
    local guild = C.GuildName()
    local open = Data.ActiveCount()
    frame.title:SetText(L["Allemano Bounty Board"])
    frame.titleInfo:SetText(guild and format("%s · %s", guild, format(L["%d open"], open)) or L["No guild"])
    frame.jobsBadge:SetCount(#Data.Jobs())
    frame.stats:SetText(format(L["%d jobs completed · %d open bounties"], Data.Completed(Data.Me()), Data.OpenCount()))
    local full = Data.OpenCount() >= Data.MAX_OPEN
    frame.postButton:SetAvailable(not full, format(L["You have %d open bounties, the most there can be."], Data.MAX_OPEN))
    local age = Comm.SyncAge()
    frame.synced:SetText(age and format(L["Synced %s"], age < 5 and L["just now"] or Data.AgeText(age)) or L["Not synced yet"])
end

function Main.ResetPosition()
    if not BB.db then return end
    BB.db.settings.window = {}
    if frame then restorePosition() end
end

function Main.ShowTab(key)
    tab = key
    if BB.db then BB.db.settings.lastTab = key end
    for k, b in pairs(tabButtons) do b:SetSelected(k == key) end
    BB.Board.SetView(key)
    Main.Update()
end

local function createTab(parent, info, x)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(Theme.size.tabH)
    b.text = W.Text(b, "semibold", 1, "textDim")
    b.text:SetPoint("LEFT", 2, 0)
    b.text:SetText(L[info.label])
    local width = b.text:GetStringWidth() + 4
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT")
    b.line:SetPoint("BOTTOMRIGHT")
    b.line:SetHeight(2)
    W.OnAccent(function(r, g, bl) b.line:SetColorTexture(r, g, bl, 1) end)
    if info.key == "jobs" then
        parent.jobsBadge = W.Badge(b)
        parent.jobsBadge:SetPoint("LEFT", b.text, "RIGHT", 6, 0)
    end
    b:SetWidth(width)
    b:SetPoint("LEFT", parent, "LEFT", x, 0)
    function b:SetSelected(on)
        self.selected = on
        self.line:SetShown(on)
        self.text:SetTextColor(Theme:Color(on and "text" or "textDim"))
    end
    b:SetScript("OnEnter", function(self) if not self.selected then self.text:SetTextColor(Theme:Color("text")) end end)
    b:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    b:SetScript("OnClick", function() Main.ShowTab(info.key) end)
    b:SetSelected(false)
    return b, x + width + 22
end

local function build()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(Theme.size.windowW, Theme.size.windowH)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    W.Panel(frame, "window", "line", Theme.radius.panel, 0.98)
    if UISpecialFrames then table.insert(UISpecialFrames, FRAME_NAME) end
    restorePosition()
    Main.ApplyScale()

    -- title bar, also the drag handle
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(Theme.size.titleH)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    W.Line(bar, "bottom", "line")

    local mark = bar:CreateTexture(nil, "ARTWORK")
    mark:SetSize(24, 24)
    mark:SetPoint("LEFT", 14, 0)
    mark:SetTexture("Interface\\AddOns\\" .. BB.name .. "\\Media\\wow\\mark")
    frame.title = W.Text(bar, "heading", 5, "text")
    frame.title:SetPoint("LEFT", mark, "RIGHT", 10, 0)
    frame.titleInfo = W.Text(bar, "regular", 0, "textDim")
    frame.titleInfo:SetPoint("LEFT", frame.title, "RIGHT", 10, -1)
    local close = W.IconButton(bar, "close", 24, nil, function() Main.Hide() end, "x")
    close:SetPoint("RIGHT", -12, 0)
    local settings = W.Button(bar, L["Settings"], "ghost", function() BB.Settings.Toggle() end)
    settings:SetPoint("RIGHT", close, "LEFT", -8, 0)

    -- tabs
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 16, 0)
    tabs:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -16, 0)
    tabs:SetHeight(Theme.size.tabH)
    local x = 0
    for _, info in ipairs(TABS) do
        tabButtons[info.key], x = createTab(tabs, info, x)
    end
    frame.jobsBadge = tabs.jobsBadge
    local tabLine = tabs:CreateTexture(nil, "BORDER")
    tabLine:SetPoint("BOTTOMLEFT", -16, 0)
    tabLine:SetPoint("BOTTOMRIGHT", 16, 0)
    tabLine:SetColorTexture(Theme:Color("line"))
    W.PixelSize(tabLine, tabs, "h")

    -- bottom bar
    local bottom = CreateFrame("Frame", nil, frame)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(Theme.size.bottomH)
    W.Line(bottom, "top", "line")
    local post = W.Button(bottom, "+ " .. L["Post Bounty"], "accent", function() BB.PostDialog.Open() end)
    frame.postButton = post
    post:SetHeight(Theme.size.inputH)
    post:SetPoint("LEFT", 16, 0)
    frame.stats = W.Text(bottom, "regular", 0, "textDim")
    frame.stats:SetPoint("LEFT", post, "RIGHT", 18, 0)
    frame.synced = W.Text(bottom, "regular", 0, "textFaint")
    frame.synced:SetPoint("RIGHT", -16, 0)
    frame.synced:SetJustifyH("RIGHT")

    -- the board fills what is left
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", -16, 0)
    content:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    BB.Board.Create(content)

    frame:SetScript("OnShow", function()
        Main.Update()
        if not ticker then ticker = C.Ticker(5, function() if frame:IsShown() then Main.Update() BB.Board.Request() end end) end
    end)
    frame:SetScript("OnHide", function()
        W.CloseMenus()
        if ticker then ticker:Cancel() ticker = nil end
    end)
    local start = BB.db and BB.db.settings.defaultTab or "board"
    if start == "last" then start = BB.db and BB.db.settings.lastTab or "board" end
    Main.ShowTab(tabButtons[start] and start or "board")
end

function Main.Show()
    if not frame then build() end
    frame:Show()
    frame:Raise()
end

function Main.Hide()
    if frame then frame:Hide() end
end

function Main.Toggle()
    if frame and frame:IsShown() then Main.Hide() else Main.Show() end
end

function Main.Frame() return frame end
function Main.Tab() return tab end

BB:On("BOUNTIES_CHANGED", Main.Update)
BB:On("GUILD_CHANGED", Main.Update)
