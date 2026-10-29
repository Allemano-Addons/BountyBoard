-- PostDialog: the "Post Bounty" window. Shift-click an item (bag, chat, anywhere a link can be clicked) while it is
-- open to choose the item.
local _, BB = ...

local PostDialog = {}
BB.PostDialog = PostDialog

local Theme, W, C, L, Data = BB.Theme, BB.W, BB.Compat, BB.L, BB.Data
local format, floor = string.format, math.floor

local WIDTH, HEIGHT, PAD = 380, 510, 20
local FRAME_NAME = "AllemanoBountyBoardPostFrame"

local frame
local state = { type = "farm", days = 3, mats = "crafter" }

local TYPE_OPTIONS = {
    { value = "farm", label = "Farm" },
    { value = "craft", label = "Craft" },
    { value = "help", label = "Help" },
    { value = "kos", label = "Kill on Sight" },
    { value = "guild", label = "Guild goal" },
}

local function deadlineOptions()
    local out = {}
    for _, d in ipairs(Data.DEADLINE_DAYS) do
        out[#out + 1] = { value = d, label = d == 1 and L["1 day"] or format(L["%d days"], d) }
    end
    return out
end

local function setError(text)
    frame.error:SetText(text or "")
end

-- Shows the chosen item in the slot.
local function showItem()
    if not state.itemID then
        frame.slot.icon:Hide()
        frame.slot.iconBorder:Hide()
        frame.slot.name:SetText(L["Shift-click an item link here"])
        frame.slot.name:SetTextColor(Theme:Color("textFaint"))
        frame.slot.sub:SetText("")
        frame.slot.clear:Hide()
        return
    end
    local name, link, quality, icon = C.ItemInfo(state.itemID)
    if link then state.itemLink = link end
    frame.slot.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.slot.icon:Show()
    frame.slot.iconBorder.border:SetColor(C.QualityColor(quality))
    frame.slot.iconBorder:Show()
    frame.slot.name:SetText("[" .. (name or format(L["Item %d"], state.itemID)) .. "]")
    frame.slot.name:SetTextColor(C.QualityColor(quality))
    frame.slot.sub:SetText(format(L["In your bags: %d"], C.ItemCount(state.itemID)))
    frame.slot.clear:Show()
end

function PostDialog.SetItem(itemID, link)
    state.itemID, state.itemLink = itemID, link
    if frame then
        showItem()
        setError(nil)
    end
end

-- A link was clicked somewhere (a hook of the game's ChatEdit_InsertLink): take it if this window is open and the
-- player is not typing in the chat.
function PostDialog.OnLink(link)
    if not frame or not frame:IsShown() then return end
    -- text in an open chat box means the link went there
    local getActive = ChatEdit_GetActiveWindow or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow)
    local box = getActive and getActive()
    if box and box.GetText and box:GetText() ~= "" then return end
    local id = C.ItemIDFromLink(link)
    BB:Debug("link clicked: %s -> item %s", tostring(link), tostring(id))
    if id then PostDialog.SetItem(id, link) end
end

local function number(box, maximum)
    local n = floor(tonumber(box:GetText()) or 0)
    if maximum and n > maximum then n = maximum end
    return math.max(0, n)
end

-- A help bounty has a few words instead of an item and a quantity.
local function applyType()
    local help, kos, guild = state.type == "help", state.type == "kos", state.type == "guild"
    local craft = state.type == "craft"
    frame.recipientLabel:SetShown(guild)
    frame.recipient:SetShown(guild)
    frame.matsButton:SetShown(craft)
    frame.matsButton:Refresh()
    frame:SetHeight(guild and HEIGHT + 78 or craft and HEIGHT + 34 or HEIGHT)
    local words = help or kos
    frame.titleBox.placeholder:SetText(kos and L["The name of the player, for example Gankarn"] or L["For example: help with a Scholomance run"])
    frame.titleBox:SetMaxLetters(kos and Data.MAX_TARGET or Data.MAX_TITLE)
    frame.slot:SetShown(not words)
    frame.titleBox:SetShown(words)
    frame.qtyLabel:SetText(kos and L["Kills"] or guild and L["Amount needed"] or L["Quantity"])
    frame.itemLabel:SetText(help and L["What do you need help with?"] or kos and L["Player to hunt"] or craft and L["Item to craft"] or L["Item"])
    frame.qtyLabel:SetShown(not help)
    frame.qty:SetShown(not help)
    frame.rewardLabel:SetText(kos and L["Reward (total)"] or guild and L["Reward for each"] or L["Reward"])
    frame.note.placeholder:SetText(help and L["Where, when, what the helper should bring"] or kos and L["Why, where they usually are"] or L["Anything the hunter should know"])
    setError(nil)
end

local function post()
    local quantity = number(frame.qty, Data.MAX_QUANTITY)
    local reward = number(frame.gold, 214748) * 10000 + number(frame.silver) * 100 + number(frame.copper)
    local b, err = Data.Post({
        type = state.type, itemID = state.itemID, itemLink = state.itemLink, quantity = quantity, reward = reward,
        recipient = frame.recipient:GetText(), mats = state.mats,
        days = state.days, note = frame.note:GetText(), title = frame.titleBox:GetText(),
    })
    if not b then setError(err) return end
    BB.Comm.SendBounty(b, "high")
    PostDialog.Close()
    BB:Fire("NOTIFY", {
        title = L["BOUNTY POSTED"], good = true, itemID = b.itemID,
        text = b.type == "help" and format(L["%s for %s"], Data.ItemName(b), C.CoinString(b.reward))
            or format(L["%dx %s for %s"], b.quantity, Data.ItemName(b), C.CoinString(b.reward)),
    })
    if BB.Main then BB.Main.ShowTab("mine") end
end

local function label(parent, text, y)
    local fs = W.Text(parent, "semibold", 0, "textDim")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
    fs:SetText(text)
    return fs
end

-- A number box with a coin icon at its right end.
local function coinBox(parent, x, y, width, icon, maxLetters)
    local e = W.EditBox(parent, "0", Theme.size.inputH - 4)
    e:SetSize(width, Theme.size.inputH - 4)
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    e:SetNumeric(true)
    e:SetMaxLetters(maxLetters)
    e:SetTextInsets(10, 24, 0, 0)
    if icon then
        local t = e:CreateTexture(nil, "OVERLAY")
        t:SetSize(12, 12)
        t:SetPoint("RIGHT", -8, 0)
        t:SetTexture(icon)
    end
    return e
end

local function build()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    W.Panel(frame, "window", "line", Theme.radius.panel, 0.98)
    if UISpecialFrames then table.insert(UISpecialFrames, FRAME_NAME) end

    -- title bar (the drag handle)
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
    title:SetText(L["Post Bounty"])
    W.Line(bar, "bottom", "line")
    local close = W.IconButton(bar, "close", 24, nil, function() PostDialog.Close() end, "x")
    close:SetPoint("RIGHT", -12, 0)

    local y = Theme.size.titleH + 16

    -- type
    label(frame, L["Type"], y)
    frame.typeBox = W.Dropdown(frame, WIDTH - 2 * PAD, function() return TYPE_OPTIONS end, function(value) state.type = value applyType() end)
    frame.typeBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 20))
    frame.typeBox:Set("farm")
    y = y + 20 + 28 + 14

    -- item
    frame.itemLabel = label(frame, L["Item"], y)
    frame.titleBox = W.EditBox(frame, L["For example: help with a Scholomance run"], Theme.size.inputH)
    frame.titleBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 20))
    frame.titleBox:SetPoint("TOPRIGHT", frame, "TOPLEFT", WIDTH - PAD, -(y + 20))
    frame.titleBox:SetMaxLetters(Data.MAX_TITLE)
    frame.titleBox:Hide()
    local slot = CreateFrame("Button", nil, frame)
    slot:SetSize(WIDTH - 2 * PAD, 54)
    slot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 20))
    slot.bg = W.Fill(slot, "sidebar", 1)
    slot.bg:SetAllPoints()
    W.Round(slot.bg, Theme.radius.control)
    slot.dashed = W.DashedBorder(slot, 5, 3)
    slot.dashed:Layout("line")
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(36, 36)
    slot.icon:SetPoint("LEFT", 10, 0)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.iconBorder = CreateFrame("Frame", nil, slot)
    slot.iconBorder:SetAllPoints(slot.icon)
    slot.iconBorder.border = W.Border(slot.iconBorder, "line")
    W.RoundBorder(slot.iconBorder.border, Theme.radius.small)
    slot.name = W.Text(slot, "semibold", 2, "textFaint")
    slot.name:SetPoint("LEFT", slot.icon, "RIGHT", 10, 7)
    slot.name:SetPoint("RIGHT", slot, "RIGHT", -34, 0)
    slot.sub = W.Text(slot, "regular", -1, "textDim")
    slot.sub:SetPoint("TOPLEFT", slot.name, "BOTTOMLEFT", 0, -3)
    slot.clear = W.IconButton(slot, "close", 22, nil, function()
        PostDialog.SetItem(nil, nil)
    end, "x")
    slot.clear:SetPoint("RIGHT", -8, 0)
    -- an item dropped from the cursor works too
    local function fromCursor()
        if not GetCursorInfo then return end
        local kind, id, link = GetCursorInfo()
        if kind == "item" then
            PostDialog.SetItem(id or C.ItemIDFromLink(link), link)
            if ClearCursor then ClearCursor() end
        end
    end
    slot:SetScript("OnReceiveDrag", fromCursor)
    slot:SetScript("OnClick", fromCursor)
    frame.slot = slot
    y = y + 20 + 54 + 14

    -- quantity and reward
    frame.qtyLabel = label(frame, L["Quantity"], y)
    local rewardLabel = label(frame, L["Reward"], y)
    frame.rewardLabel = rewardLabel
    rewardLabel:ClearAllPoints()
    rewardLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 110, -y)
    frame.qty = coinBox(frame, PAD, y + 20, 96, nil, 4)
    frame.qty:SetText("1")
    frame.gold = coinBox(frame, PAD + 110, y + 20, 76, "Interface\\MoneyFrame\\UI-GoldIcon", 6)
    frame.silver = coinBox(frame, PAD + 110 + 82, y + 20, 70, "Interface\\MoneyFrame\\UI-SilverIcon", 2)
    frame.copper = coinBox(frame, PAD + 110 + 82 + 76, y + 20, 70, "Interface\\MoneyFrame\\UI-CopperIcon", 2)
    y = y + 20 + 30 + 14

    -- deadline
    label(frame, L["Deadline"], y)
    frame.deadline = W.Dropdown(frame, WIDTH - 2 * PAD, deadlineOptions, function(value) state.days = value end)
    frame.deadline:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 20))
    y = y + 20 + 28 + 14

    -- note
    label(frame, L["Note"], y)
    frame.note = W.EditBox(frame, L["Anything the hunter should know"], 66, true)
    frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 20))
    frame.note:SetPoint("TOPRIGHT", frame, "TOPLEFT", WIDTH - PAD, -(y + 20))
    frame.note:SetHeight(66)
    frame.note:SetMaxLetters(Data.MAX_NOTE)
    y = y + 20 + 66 + 8

    frame.error = W.Text(frame, "regular", -1, "danger")
    frame.error:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    frame.error:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)

    -- guild goals: who receives the items (the creator unless somebody else is named)
    frame.recipientLabel = label(frame, L["Deliver to"], y + 18)
    frame.recipient = W.EditBox(frame, L["Your name, or a guildmate such as the guild bank"], Theme.size.inputH)
    frame.recipient:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 38))
    frame.recipient:SetPoint("TOPRIGHT", frame, "TOPLEFT", WIDTH - PAD, -(y + 38))
    frame.recipient:SetMaxLetters(40)

    -- craft: who brings the materials
    local mats = CreateFrame("Button", nil, frame)
    mats:SetSize(WIDTH - 2 * PAD, 24)
    mats:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(y + 20))
    local box = CreateFrame("Frame", nil, mats)
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    W.Panel(box, "field", "line", Theme.radius.small, 1)
    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetSize(8, 8)
    tick:SetPoint("CENTER")
    W.OnAccent(function(r, g, bl) tick:SetColorTexture(r, g, bl, 1) end)
    local text = W.Text(mats, "regular", 0, "text")
    text:SetPoint("LEFT", box, "RIGHT", 10, 0)
    text:SetText(L["The crafter uses their own materials"])
    function mats:Refresh() tick:SetShown(state.mats ~= "creator") end
    mats:SetScript("OnClick", function(self)
        state.mats = state.mats == "creator" and "crafter" or "creator"
        self:Refresh()
    end)
    mats:Hide()
    frame.matsButton = mats

    -- footer
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(58)
    W.Line(footer, "top", "line")
    local postButton = W.Button(footer, L["Post"], "accent", post)
    postButton:SetSize(96, 30)
    postButton:SetPoint("RIGHT", -PAD, 0)
    local cancel = W.Button(footer, L["Cancel"], "default", function() PostDialog.Close() end)
    cancel:SetSize(96, 30)
    cancel:SetPoint("RIGHT", postButton, "LEFT", -10, 0)
    frame.postButton = postButton

    frame:SetScript("OnHide", function() W.CloseMenus() end)
end

function PostDialog.Open()
    if not frame then build() end
    state = { type = "farm", days = 3, mats = "crafter" }
    frame.typeBox:Set("farm")
    frame.titleBox:SetText("")
    frame.recipient:SetText("")
    applyType()
    frame.deadline:Set(3)
    frame.qty:SetText("1")
    frame.gold:SetText("")
    frame.silver:SetText("")
    frame.copper:SetText("")
    frame.note:SetText("")
    setError(nil)
    showItem()
    PostDialog.UpdateButton()
    frame:Show()
    frame:Raise()
end

-- The Post button is off at the limit of open bounties.
function PostDialog.UpdateButton()
    if not frame then return end
    local full = Data.OpenCount() >= Data.MAX_OPEN
    frame.postButton:SetAvailable(not full, format(L["You have %d open bounties, the most there can be."], Data.MAX_OPEN))
end

function PostDialog.Close()
    if frame then frame:Hide() end
end

function PostDialog.IsShown() return frame ~= nil and frame:IsShown() end

-- The window (for tests).
function PostDialog.Frame() return frame end

-- The game has moved these between versions (a global function, or a function of ChatFrameUtil), and an item click
-- may or may not pass through the chat functions: hook every place that exists.
local function onLink(link)
    if type(link) == "string" and not C.IsSecret(link) then PostDialog.OnLink(link) end
end
if hooksecurefunc then
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", onLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", onLink) end
    if HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", onLink) end
end

-- The game knows an item it was asked about: show its name.
BB:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID)
    if frame and frame:IsShown() and state.itemID == itemID then showItem() end
end)
