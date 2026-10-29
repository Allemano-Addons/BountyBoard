-- Launcher: the square button that opens the board, like the other Allemano addons have. Left click opens the
-- window, right click the settings, drag it anywhere; it stays where it is dropped. It can be hidden in the
-- settings or with /bb button.
local _, BB = ...

local Launcher = {}
BB.Launcher = Launcher

local Theme, W, L, Data = BB.Theme, BB.W, BB.L, BB.Data
local format = string.format

local SIZE = 30
local button

local function place()
    local saved = BB.db and BB.db.settings.button
    button:ClearAllPoints()
    if saved and saved.point then
        button:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    elseif Minimap then
        button:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -44, 0) -- a step left of where the first button sits
    else
        button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -40)
    end
end

local function showTooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L["Allemano Bounty Board"])
    GameTooltip:AddLine(format(L["%d open bounties, %d jobs of yours"], Data.ActiveCount(), #Data.Jobs()), 0.86, 0.87, 0.90)
    GameTooltip:AddLine(L["Left-click: open the board"], 0.86, 0.87, 0.90)
    GameTooltip:AddLine(L["Right-click: settings"], 0.86, 0.87, 0.90)
    GameTooltip:AddLine(L["Drag: move this button"], 0.55, 0.58, 0.64)
    GameTooltip:Show()
end

local function build()
    button = CreateFrame("Button", nil, UIParent)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local _, border = W.Panel(button, "window", "line", Theme.radius.control, 1)
    button.border = border

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexture("Interface\\AddOns\\" .. BB.name .. "\\Media\\wow\\mark")

    button:SetScript("OnClick", function(_, mouseButton)
        if GameTooltip then GameTooltip:Hide() end
        if mouseButton == "RightButton" then BB.Settings.Toggle() else BB.Main.Toggle() end
    end)
    -- the frame lights up in the accent while the mouse is on it
    button:SetScript("OnEnter", function(self)
        self.border:SetColor(Theme:Accent())
        showTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.border:SetColor(Theme:Color("line"))
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnDragStart", function(self)
        if GameTooltip then GameTooltip:Hide() end
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        BB.db.settings.button = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    Launcher.button = button
end

-- Places the button and shows or hides it as the settings say.
function Launcher.Refresh()
    if not button then return end
    place()
    button:SetShown(not BB.db or BB.db.settings.launcherShown ~= false)
end

BB:On("LOGIN", function()
    build()
    Launcher.Refresh()
end)
BB:On("SETTINGS_CHANGED", function(key) if key == "launcherShown" then Launcher.Refresh() end end)

function Launcher.Toggle()
    if not BB.db then return end
    BB.Settings.Set("launcherShown", BB.db.settings.launcherShown == false)
    BB:Print(BB.db.settings.launcherShown == false and L["The launcher button is hidden."] or L["The launcher button is shown."])
end
