-- Toast: small notices at the top of the screen that fade by themselves: somebody took your bounty, a delivery or a
-- payment was verified. BB:Fire("NOTIFY", { title, text, itemID, good }) shows one.
local _, BB = ...

local Toast = {}
BB.Toast = Toast

local Theme, W, C, L, Data = BB.Theme, BB.W, BB.Compat, BB.L, BB.Data
local max, format = math.max, string.format

local WIDTH, HEIGHT, GAP = 340, 58, 8
local MAX_SHOWN = 4
local LIFETIME, FADE = 9, 0.6

-- note.kind -> the setting that can switch it off
local KIND_SETTING = { taken = "toastTaken", delivery = "toastDelivery", payment = "toastPayment" }
-- The sounds to choose from: the game's own (SOUNDKIT name, and the sound number if the client has no such name).
local SOUNDS = {
    { value = "toast", label = "Toast (default)", kit = "UI_BNET_TOAST", id = 18019 },
    { value = "ready", label = "Ready check", kit = "READY_CHECK", id = 8960 },
    { value = "raid", label = "Raid warning", kit = "RAID_WARNING", id = 8959 },
    { value = "quest", label = "Quest complete", kit = "IG_QUEST_LIST_COMPLETE", id = 878 },
    { value = "ping", label = "Map ping", kit = "MAP_PING", id = 3175 },
    { value = "auction", label = "Auction window", kit = "AUCTION_WINDOW_OPEN", id = 5274 },
    { value = "levelup", label = "Level up", kit = "LEVELUP", id = 888 },
    { value = "none", label = "Off" },
}

function Toast.SoundOptions()
    local list = {}
    for i, s in ipairs(SOUNDS) do list[i] = { value = s.value, label = s.label } end
    return list
end

-- Plays one of the sounds (also used as a preview in the settings).
function Toast.Play(choice)
    if not PlaySound then return end
    for _, s in ipairs(SOUNDS) do
        if s.value == choice and s.id then
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT[s.kit]) or s.id)
        end
    end
end

local anchor
local pool
local shown = {}       -- the toasts on screen, newest first
local ticker

local function colorHex(r, g, b)
    return format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The item's name in its quality colour.
function Toast.ItemText(itemID)
    local name, _, quality = C.ItemInfo(itemID)
    local r, g, b = C.QualityColor(quality)
    return "|cff" .. colorHex(r, g, b) .. (name or format(L["Item %d"], itemID)) .. "|r"
end

-- A bounty's thing in words: the item in its colour, or what a help bounty asks for.
function Toast.BountyText(b)
    if b.type == "help" or b.type == "kos" then return Data.ItemName(b) end
    return Toast.ItemText(b.itemID)
end

local function layout()
    for i, t in ipairs(shown) do
        t:ClearAllPoints()
        t:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (HEIGHT + GAP))
    end
end

local function release(toast)
    for i, t in ipairs(shown) do
        if t == toast then table.remove(shown, i) break end
    end
    toast:Hide()
    toast:SetAlpha(1)
    pool.free[#pool.free + 1] = toast
    for i, t in ipairs(pool.active) do
        if t == toast then table.remove(pool.active, i) break end
    end
    layout()
end

local function tick()
    local now = GetTime and GetTime() or 0
    for i = #shown, 1, -1 do
        local t = shown[i]
        local left = t.expires - now
        if left <= 0 then
            release(t)
        elseif left < FADE then
            t:SetAlpha(max(0, left / FADE))
        elseif not t:IsMouseOver() then
            t:SetAlpha(1)
        else
            t.expires = now + LIFETIME -- the mouse is on it: it stays
        end
    end
    if #shown == 0 and ticker then ticker:Cancel() ticker = nil end
end

local function create()
    local t = CreateFrame("Frame", nil, anchor)
    t:SetSize(WIDTH, HEIGHT)
    t:SetFrameStrata("FULLSCREEN_DIALOG")
    t:EnableMouse(true)
    t.bg = W.Panel(t, "field", "line", Theme.radius.panel, 0.98)

    t.stripe = t:CreateTexture(nil, "ARTWORK")
    t.stripe:SetPoint("TOPLEFT", 0, -6)
    t.stripe:SetPoint("BOTTOMLEFT", 0, 6)
    t.stripe:SetWidth(3)
    W.OnAccent(function(r, g, b) if not t.good then t.stripe:SetColorTexture(r, g, b, 1) end end)

    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(38, 38)
    t.icon:SetPoint("LEFT", 12, 0)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.iconBorder = CreateFrame("Frame", nil, t)
    t.iconBorder:SetAllPoints(t.icon)
    t.iconBorder.border = W.Border(t.iconBorder, "line")
    W.RoundBorder(t.iconBorder.border, Theme.radius.small)

    t.title = W.Text(t, "semibold", -1, "textDim")
    t.title:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, -1)
    t.title:SetPoint("RIGHT", t, "RIGHT", -34, 0)
    t.body = W.Text(t, "medium", 1, "text")
    t.body:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3)
    t.body:SetPoint("RIGHT", t, "RIGHT", -34, 0)
    t.body:SetWordWrap(true)
    t.body:SetHeight(30)
    t.body:SetJustifyV("TOP")

    t.close = W.IconButton(t, "close", 22, nil, function() release(t) end, "x")
    t.close:SetPoint("TOPRIGHT", -8, -8)
    return t
end

-- note: { title, text, itemID (optional), good (optional: green) }
function Toast.Show(note)
    local settings = BB.db and BB.db.settings
    if settings then
        if settings.toasts == false then return end
        local key = KIND_SETTING[note.kind]
        if key and settings[key] == false then return end
        Toast.Play(settings.soundChoice or "toast")
    end
    if not anchor then
        anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetSize(WIDTH, 1)
        anchor:SetPoint("TOP", UIParent, "TOP", 0, -90)
        pool = W.Pool(create)
    end
    while #shown >= MAX_SHOWN do release(shown[#shown]) end

    local t = pool:Acquire()
    t.good = note.good and true or false
    if t.good then t.stripe:SetColorTexture(Theme:Color("good")) else t.stripe:SetColorTexture(Theme:Accent()) end
    t.title:SetText(note.title or "")
    t.title:SetTextColor(Theme:Color(t.good and "good" or "textDim"))
    t.body:SetText(note.text or "")
    if note.itemID and note.itemID > 0 then
        local _, _, quality, icon = C.ItemInfo(note.itemID)
        t.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        t.icon:Show()
        t.iconBorder.border:SetColor(C.QualityColor(quality))
        t.iconBorder:Show()
    else
        t.icon:Hide()
        t.iconBorder:Hide()
    end
    t.expires = (GetTime and GetTime() or 0) + LIFETIME
    t:SetAlpha(1)
    table.insert(shown, 1, t)
    layout()
    t:Show()
    if not ticker then ticker = C.Ticker(0.1, tick) end
    return t
end

-- Test hook: how many toasts are on screen.
function Toast.Count() return #shown end

BB:On("NOTIFY", Toast.Show)

-- Somebody took one of my bounties.
BB:On("BOUNTY_TAKEN", function(b, who)
    Toast.Show({
        kind = "taken", title = L["BOUNTY BOARD"], itemID = b.itemID,
        text = format(L["%s took your bounty: %s"], who, Toast.BountyText(b)),
    })
end)

-- A helper says the help is done: the creator confirms it on the board.
BB:On("HELP_DONE", function(b, who)
    Toast.Show({
        kind = "delivery", title = L["HELP DONE"], good = true,
        text = b.type == "kos"
            and format(L["%s has made the kills: %s. Confirm it on the board."], C.ShortName(who) or who, Data.ItemName(b))
            or format(L["%s says the help is done: %s. Confirm it on the board."], C.ShortName(who) or who, b.title or L["Help"]),
    })
end)

-- A bounty I took was settled by its creator (the creator's version is the one that counts).
BB:On("BOUNTY_STATUS", function(b, _, new)
    if Data.IsMine(b) or not Data.IAmTaker(b) then return end
    local name = Toast.BountyText(b)
    if new == "paid" then
        Toast.Show({ kind = "payment", title = L["PAYMENT VERIFIED"], itemID = b.itemID, good = true,
            text = format(L["%s confirmed the payment for %dx %s"], b.creator, b.quantity, name) })
    elseif new == "delivered" then
        Toast.Show({ kind = "delivery", title = L["DELIVERY VERIFIED"], itemID = b.itemID, good = true,
            text = format(L["%s confirmed your delivery of %dx %s"], b.creator, b.quantity, name) })
    elseif new == "cancelled" then
        Toast.Show({ title = L["BOUNTY CANCELLED"], itemID = b.itemID,
            text = format(L["%s cancelled the bounty for %s"], b.creator, name) })
    end
end)
