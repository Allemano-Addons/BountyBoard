-- Board: the card grid of the four tabs (Board, My Bounties, My Jobs, History) with the filter row of the board.
local _, BB = ...

local Board = {}
BB.Board = Board

local Theme, W, C, L, Data, Comm = BB.Theme, BB.W, BB.Compat, BB.L, BB.Data, BB.Comm
local format, floor, max = string.format, math.floor, math.max
local tsort = table.sort

local CARD_H, GAP, PAD = 134, 10, 14
local SHOWN_TAKERS = 2
local STALE = 120 -- seconds before a taker's number shows its age

local view = "board"
local filterType, searchText = "all", ""
local frame, area, empty, filterRow, clearRow, pool
local dirty = false
local updateClear

-- "completed 2 min ago": when a finished bounty ended
local FINISHED = {
    paid = L["completed"], closed = L["closed"], cancelled = L["cancelled"], expired = L["expired"],
}

local HELP_ICON = "Interface\\Icons\\Ability_Warrior_RallyingCry"
local KOS_ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

local TYPE_COLOR = { farm = "typeFarm", craft = "typeCraft", help = "typeHelp", kos = "typeKos", guild = "typeGuild" }

local OUTCOME = {
    paid = { L["COMPLETE"], "good" }, delivered = { L["DELIVERED"], "good" }, taken = { L["TAKEN"], "warn" },
    closed = { L["CLOSED"], "textDim" }, expired = { L["EXPIRED"], "textDim" }, cancelled = { L["CANCELLED"], "textDim" },
}

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
local function takeJob(b)
    local entry, err = Data.Take(b.id)
    if not entry then BB:Print(err) return end
    Comm.SendTake(b, entry)
    BB.Progress.Taken(b)
    BB:Fire("NOTIFY", {
        title = b.type == "help" and L["HELP OFFERED"] or b.type == "kos" and L["HUNT ACCEPTED"]
            or b.type == "guild" and L["CONTRIBUTING"] or b.type == "craft" and L["CRAFT ACCEPTED"] or L["JOB TAKEN"],
        itemID = b.itemID, good = true,
        text = b.type == "help" and format(L["Help %s with: %s."], C.ShortName(b.creator), Data.ItemName(b))
            or b.type == "kos" and format(L["Kill %s %d times. %s pays."], b.title, b.quantity, C.ShortName(b.creator))
            or b.type == "craft" and format(b.mats == "creator" and L["Craft %dx %s for %s. They supply the materials."] or L["Craft %dx %s for %s. Use your own materials."], b.quantity, Data.ItemName(b), C.ShortName(b.creator))
            or b.type == "guild" and format(L["Bring %dx %s to %s. Trade it to them."], b.quantity - (b.deliveredQty or 0), Data.ItemName(b), C.ShortName(Data.Recipient(b)))
            or format(L["Bring %dx %s to %s."], b.quantity, Data.ItemName(b), C.ShortName(b.creator)),
    })
end

local function claimHelp(b)
    local entry, err = Data.ClaimHelp(b.id)
    if not entry then BB:Print(err) return end
    Comm.SendProgress(b, entry)
end

local function confirmHelp(b)
    local done, err = Data.ConfirmHelp(b.id)
    if not done then BB:Print(err) return end
    Comm.SendBounty(done, "high")
end

local function cancelBounty(b)
    local done, err = Data.Cancel(b.id)
    if not done then BB:Print(err) return end
    Comm.SendCancel(done)
end

local function completeBounty(b)
    local done, err = Data.Complete(b.id)
    if not done then BB:Print(err) return end
    Comm.SendBounty(done, "high")
end

local function abandonJob(b)
    local entry, err = Data.Abandon(b.id)
    if not entry then BB:Print(err) return end
    Comm.SendAbandon(b, entry)
end

-- ---------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------
local function takerRow(card)
    local row = CreateFrame("Frame", nil, card)
    row:SetHeight(20)
    row.text = W.Text(row, "regular", -1, "textDim")
    row.text:SetPoint("TOPLEFT")
    row.text:SetPoint("TOPRIGHT")
    row.bar = W.ProgressBar(row, 4)
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetPoint("BOTTOMRIGHT")
    return row
end

local function createCard()
    local card = CreateFrame("Frame", nil, area.content)
    card:SetHeight(CARD_H)
    W.Panel(card, "field", "line", Theme.radius.panel, 1)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("TOPLEFT", 12, -12)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.iconBorder = CreateFrame("Frame", nil, card)
    card.iconBorder:SetAllPoints(card.icon)
    card.iconBorder.border = W.Border(card.iconBorder, "line")
    W.RoundBorder(card.iconBorder.border, Theme.radius.small)

    card.stripe = card:CreateTexture(nil, "ARTWORK")
    card.stripe:SetPoint("TOPLEFT", 1, -12)
    card.stripe:SetPoint("BOTTOMLEFT", 1, 12)
    card.stripe:SetWidth(3)

    card.status = W.Tag(card, "textDim")
    card.status:SetPoint("TOPRIGHT", -12, -12)
    card.status:Hide()

    card.title = W.Text(card, "semibold", 2, "text")
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 0)
    card.title:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    card.kind = W.Tag(card, "textDim", -2)
    card.kind:SetHeight(16)
    card.kind:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, 2)
    card.sub = W.Text(card, "regular", -1, "textDim")
    card.sub:SetPoint("LEFT", card.kind, "RIGHT", 8, 0)
    card.sub:SetPoint("RIGHT", card, "RIGHT", -12, 0)

    card.note = W.Text(card, "regular", -1, "textFaint")
    card.note:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -10)
    card.note:SetPoint("RIGHT", card, "RIGHT", -12, 0)

    card.rows = {}
    for i = 1, SHOWN_TAKERS do
        local row = takerRow(card)
        row:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -8 - (i - 1) * 24)
        row:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        card.rows[i] = row
    end

    card.reward = W.Text(card, "semibold", 1, "text")
    card.reward:SetPoint("BOTTOMLEFT", 12, 12)

    card.action = W.Button(card, L["Take Job"], "accent")
    card.action:SetHeight(24)
    card.action:SetPoint("BOTTOMRIGHT", -12, 10)
    card.second = W.Button(card, L["Close"], "default")
    card.second:SetHeight(24)
    card.second:SetPoint("RIGHT", card.action, "LEFT", -6, 0)
    card.tag = W.Tag(card, "good")
    card.tag:SetPoint("BOTTOMRIGHT", -12, 10)

    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        if self.link and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return card
end

local function resetCard(card)
    card.bounty, card.link = nil, nil
    if card.armTimer then card.armTimer = nil end
end

-- The takers to show: me first, then the most advanced.
local function sortedTakers(b)
    local list = {}
    for name, entry in pairs(b.takers) do
        if not entry.left then list[#list + 1] = { name = name, entry = entry } end
    end
    local me = Data.Me()
    tsort(list, function(a, c)
        local am, cm = C.SameName(a.name, me), C.SameName(c.name, me)
        if am ~= cm then return am end
        if (a.entry.progress or 0) ~= (c.entry.progress or 0) then return (a.entry.progress or 0) > (c.entry.progress or 0) end
        return a.name < c.name
    end)
    return list
end

-- A guild goal: one bar for everybody (delivered, and on the way in the bags) and the biggest contributor.
local function fillGuildGoal(card, b)
    local delivered = b.deliveredQty or 0
    local onTheWay, best = 0, nil
    for name, entry in pairs(b.takers) do
        if not entry.left then
            onTheWay = onTheWay + (entry.progress or 0)
            if (entry.delivered or 0) > 0 and (not best or entry.delivered > best.delivered) then
                best = { name = name, delivered = entry.delivered }
            end
        end
    end
    onTheWay = math.min(onTheWay, math.max(0, b.quantity - delivered))
    card.note:SetShown(false)
    local row1, row2 = card.rows[1], card.rows[2]
    row1:Show()
    row1.text:SetText(format(L["%d/%d delivered"], delivered, b.quantity) .. (onTheWay > 0 and format(L[" · %d in bags"], onTheWay) or ""))
    row1.text:SetTextColor(Theme:Color("text"))
    row1.bar:SetProgress(delivered / max(1, b.quantity), delivered >= b.quantity and "good" or nil)
    if best then
        row2:Show()
        row2.text:SetText(format(L["Most: %s  %d"], C.ClassColored(best.name), best.delivered))
        row2.text:SetTextColor(Theme:Color("textDim"))
        row2.bar:SetProgress(0)
        row2.bar:Hide()
    elseif b.note ~= "" then
        row2:Show()
        row2.text:SetText(b.note)
        row2.text:SetTextColor(Theme:Color("textFaint"))
        row2.bar:Hide()
    else
        row2:Hide()
    end
    row1.bar:Show()
end

local function fillTakers(card, b, now)
    if b.type == "guild" then fillGuildGoal(card, b) return end
    card.rows[2].bar:Show()
    local list = sortedTakers(b)
    local showNote = #list == 0
    card.note:SetShown(showNote)
    card.note:SetText(showNote and (b.note ~= "" and b.note or (b.type == "help" and L["Nobody has offered to help yet."] or b.type == "kos" and L["Nobody has accepted this hunt yet."] or L["Nobody has taken this job yet."])) or "")
    for i, row in ipairs(card.rows) do
        local t = list[i]
        if not t then
            row:Hide()
        elseif i == SHOWN_TAKERS and #list > SHOWN_TAKERS then
            row:Show()
            row.text:SetText(format(L["+%d more hunters"], #list - SHOWN_TAKERS + 1))
            row.text:SetTextColor(Theme:Color("textDim"))
            row.bar:SetProgress(0)
        else
            row:Show()
            local e = t.entry
           local mineRow = C.SameName(t.name, Data.Me())
            if b.type == "help" then
                local done = (e.delivered or 0) > 0
                row.text:SetText(C.ClassColored(t.name) .. "  " .. (done and L["says it is done"] or L["offered to help"]))
                row.bar:SetProgress(done and 1 or 0, "good")
            else
                local have = e.progress or 0
                local hunt = b.type == "kos"
                local text = format(hunt and L["%s  %d/%d kills"] or L["%s  %d/%d in bags"], C.ClassColored(t.name), have, b.quantity)
                if not hunt and (e.delivered or 0) > 0 then text = text .. format(L[" · %d delivered"], e.delivered) end
                local age = now - (e.updatedAt or now)
                if not Data.IsTerminal(b) and not mineRow and age >= STALE then
                    text = text .. " · " .. format(L["updated %s"], Data.AgeText(age))
                end
                row.text:SetText(text)
                local done = hunt and have or have + (e.delivered or 0)
                row.bar:SetProgress(done / max(1, b.quantity), done >= b.quantity and "good" or nil)
            end
            row.text:SetTextColor(Theme:Color(mineRow and "text" or "textDim"))
        end
    end
end

-- Two clicks within three seconds confirm an action. The state is kept per bounty and action (not on the button),
-- so the redraws that happen every few seconds do not reset a "Sure?" that is waiting.
local armedAt = {}
local ARM_SECONDS = 3

local function armed(button, key, label, confirmLabel, run)
    local function waiting()
        local at = armedAt[key]
        return at ~= nil and (GetTime and GetTime() or 0) - at < ARM_SECONDS
    end
    -- the button keeps one width for both texts, so it does not jump when the text changes
    button.minWidth = nil
    button:SetLabel(confirmLabel)
    local wide = button:GetWidth()
    button.minWidth = wide
    button:SetLabel(waiting() and confirmLabel or label)
    button.armKey = key
    button:SetScript("OnClick", function(self)
        if waiting() then
            armedAt[key] = nil
            self:SetLabel(label)
            run()
        else
            local now = GetTime and GetTime() or 0
            armedAt[key] = now
            self:SetLabel(confirmLabel)
            C.After(ARM_SECONDS + 0.05, function()
                if armedAt[key] == now then
                    armedAt[key] = nil
                    if self.armKey == key then self:SetLabel(label) end
                end
            end)
        end
    end)
end

local function fillCard(card, b, now)
    card.bounty = b
    local help = b.type == "help"
    local kos = b.type == "kos"
    local confirm = help or kos
    local _, link, quality, icon
    if help or kos then
        icon, quality = help and HELP_ICON or KOS_ICON, kos and 4 or 1
    else
        _, link, quality, icon = C.ItemInfo(b.itemID)
    end
    card.link = link or b.itemLink
    card.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.iconBorder.border:SetColor(C.QualityColor(quality))
    local r, g, bl = C.QualityColor(quality)
    card.title:SetTextColor(r, g, bl)
    card.title:SetText(confirm and Data.ItemName(b) or format("%dx %s", b.quantity, Data.ItemName(b)))
    local guild = b.type == "guild"
    local craft = b.type == "craft"
    local typeKey = TYPE_COLOR[b.type] or "textDim"
    local coloured = not BB.db or BB.db.settings.typeColors ~= false
    card.kind:SetText(string.upper(help and L["Help"] or kos and L["Kill"] or guild and L["Guild"] or craft and L["Craft"] or L["Farm"]),
        coloured and typeKey or "textDim")
    if coloured then
        card.stripe:SetColorTexture(Theme:Color(typeKey))
        card.stripe:Show()
    else
        card.stripe:Hide()
    end
    local mine = Data.IsMine(b)
    local creator = C.ClassColored(b.creator, b.class)
    if Data.IsTerminal(b) then
        local verb = FINISHED[b.status] or L["finished"]
        card.sub:SetText(creator .. " · " .. verb .. " " .. Data.AgeText(now - (b.finishedAt or now)))
    else
        local to = guild and not C.SameName(Data.Recipient(b), b.creator)
            and (" · " .. format(L["deliver to %s"], C.ClassColored(Data.Recipient(b)))) or ""
        local mats = craft and (" · " .. (b.mats == "creator" and L["mats supplied"] or L["own mats"])) or ""
        card.sub:SetText(creator .. " · " .. Data.TimeLeftText(b, now) .. to .. mats)
    end

    local outcome = OUTCOME[b.status]
    if outcome and b.status ~= "open" then
        card.status:SetText(outcome[1], outcome[2])
        card.status:Show()
    else
        card.status:Hide()
    end

    fillTakers(card, b, now)
    card.reward:SetText(b.reward > 0 and (C.CoinString(b.reward) .. (guild and (" " .. L["each"]) or "")) or L["No reward"])

    -- the right-hand side of the bottom row
    card.action:Hide()
    card.second:Hide()
    card.tag:Hide()
    card.tag:ClearAllPoints()
    card.tag:SetPoint("BOTTOMRIGHT", -12, 10)
    if Data.IsTerminal(b) then
        card.tag:Hide() -- finished: the status tag in the corner says how
    elseif mine then
        card.action:Show()
        card.action:SetScript("OnClick", nil)
        armed(card.action, b.id .. "|cancel", L["Cancel"], L["Sure?"], function() cancelBounty(b) end)
        if b.status ~= "open" and not (confirm and b.status == "delivered") then
            card.second:Show()
            card.second:SetScript("OnClick", nil)
            if confirm then
                armed(card.second, b.id .. "|confirm", kos and L["Confirm kills"] or L["Confirm help"], L["Sure?"], function() confirmHelp(b) end)
            else
                armed(card.second, b.id .. "|complete", L["Complete"], L["Sure?"], function() completeBounty(b) end)
            end
        elseif confirm then
            -- confirmed; only the gold is missing
            card.tag:SetText(L["Awaiting payment"], "warn")
            card.tag:ClearAllPoints()
            card.tag:SetPoint("RIGHT", card.action, "LEFT", -8, 0)
            card.tag:Show()
        end
    elseif Data.IAmTaker(b) then
        local entry = Data.TakerEntry(b, Data.Me())
        if confirm and (entry.delivered or 0) > 0 then
            if b.status == "delivered" then
                card.tag:SetText(L["Confirmed, awaiting payment"], "good")
            else
                card.tag:SetText(L["Waiting for confirmation"], "warn")
            end
            card.tag:Show()
        elseif help then
            card.action:Show()
            card.action:SetScript("OnClick", nil)
            armed(card.action, b.id .. "|abandon", L["Abandon"], L["Sure?"], function() abandonJob(b) end)
            card.second:Show()
            card.second:SetScript("OnClick", nil)
            armed(card.second, b.id .. "|helped", L["I helped"], L["Sure?"], function() claimHelp(b) end)
        else
            card.tag:SetText(guild and L["Contributing"] or L["Taken by you"], "good")
            card.tag:Show()
            if (entry.delivered or 0) == 0 then
                card.action:Show()
                card.action:SetScript("OnClick", nil)
                armed(card.action, b.id .. "|abandon", L["Abandon"], L["Sure?"], function() abandonJob(b) end)
                card.tag:ClearAllPoints()
                card.tag:SetPoint("RIGHT", card.action, "LEFT", -8, 0)
            end
        end
    else
        card.action:Show()
        card.action:SetLabel(help and L["Offer Help"] or kos and L["Hunt"] or guild and L["Contribute"] or craft and L["Craft"] or L["Take Job"])
        card.action:SetScript("OnClick", function() takeJob(b) end)
    end
end

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------
local function matches(b)
    if view == "board" then
        if filterType ~= "all" and b.type ~= filterType then return false end
        if searchText ~= "" then
            local hay = string.lower(Data.ItemName(b) .. " " .. (b.creator or "") .. " " .. (b.note or ""))
            if not hay:find(searchText, 1, true) then return false end
        end
    end
    return true
end

local function listFor()
    if view == "mine" then return Data.Mine() end
    if view == "jobs" then return Data.Jobs() end
    if view == "history" then return Data.History() end
    return Data.Board()
end

local EMPTY = {
    board = "No open bounties yet. Post the first one!",
    mine = "You have no bounties. Click + Post Bounty to make one.",
    jobs = "You have not taken any jobs. Pick one on the Board.",
    history = "Nothing has finished yet.",
}

function Board.Refresh()
    dirty = false
    if not frame or not frame:IsVisible() then return end
    pool:ReleaseAll()
    local now = C.Now()
    local width = area:GetWidth()
    if not width or width < 100 then dirty = true return end
    local snap = function(v) return Theme:Snap(v, area.content) end
    local colW = snap((width - PAD * 2 - GAP) / 2)
    local list, shown = listFor(), 0
    local noGuild = not C.GuildName()
    for _, b in ipairs(noGuild and {} or list) do
        if matches(b) then
            shown = shown + 1
            local card = pool:Acquire()
            local col, rowIndex = (shown - 1) % 2, floor((shown - 1) / 2)
            card:SetWidth(colW)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", area.content, "TOPLEFT", snap(PAD + col * (colW + GAP)), -snap(PAD + rowIndex * (CARD_H + GAP)))
            fillCard(card, b, now)
        end
    end
    area:SetContentHeight(shown == 0 and 0 or PAD * 2 + math.ceil(shown / 2) * (CARD_H + GAP) - GAP)
    if noGuild then
        empty:SetText(L["Join a guild to use the Bounty Board."])
    elseif shown == 0 and #list > 0 then
        empty:SetText(L["No bounty matches your search."])
    else
        empty:SetText(L[EMPTY[view]])
    end
    empty:SetShown(shown == 0)
    updateClear()
end

-- Many changes in a row make one redraw.
function Board.Request()
    if dirty then return end
    dirty = true
    C.After(0.05, function() if dirty then Board.Refresh() end end)
end

-- "Clear finished": History clears every finished bounty, My Bounties the player's own.
function updateClear()
    if not clearRow then return end
    local scope = view == "history" and "history" or view == "mine" and "mine" or nil
    clearRow:SetShown(scope ~= nil)
    if not scope then return end
    local n = Data.FinishedCount(scope)
    clearRow.scope = scope
    clearRow.count = n
    local label = format(scope == "history" and L["Clear history (%d)"] or L["Clear finished (%d)"], n)
    armed(clearRow.button, "clear|" .. scope, label, L["Sure?"], function()
        Data.ClearFinished(scope)
    end)
    clearRow.button:SetAvailable(n > 0)
end
Board.UpdateClear = updateClear

function Board.SetView(name)
    view = name
    if filterRow then filterRow:SetShown(name == "board") end
    if frame then
        area:ClearAllPoints()
        local top = name == "board" and -(Theme.size.filterH + 20) or (name == "mine" or name == "history") and -40 or 0
        area:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top)
        updateClear()
        area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        area:ScrollTo(0)
    end
    Board.Request()
end

function Board.View() return view end

-- Test hook: how many cards are shown.
function Board.CardCount() return pool and #pool.active or 0 end
function Board.Cards() return pool and pool.active or {} end

-- parent: the content area of the window.
function Board.Create(parent)
    frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    filterRow = CreateFrame("Frame", nil, frame)
    filterRow:SetPoint("TOPLEFT", PAD, -10)
    filterRow:SetPoint("TOPRIGHT", -PAD, -10)
    filterRow:SetHeight(Theme.size.filterH)
    local segment = W.Segment(filterRow, {
        { value = "all", label = L["All"] },
        { value = "farm", label = L["Farm"], color = "typeFarm" },
        { value = "craft", label = L["Craft"], color = "typeCraft" },
        { value = "help", label = L["Help"], color = "typeHelp" },
        { value = "kos", label = L["Kill on Sight"], color = "typeKos" },
        { value = "guild", label = L["Guild"], color = "typeGuild" },
    }, function(value) filterType = value Board.Request() end)
    segment:SetPoint("LEFT")
    segment:Set("all")
    BB:On("SETTINGS_CHANGED", function(key) if key == "typeColors" then segment:Set(segment.value) end end)
    local search = W.EditBox(filterRow, L["Search item or player"], Theme.size.searchH)
    search:SetPoint("RIGHT")
    search:SetWidth(200)
    search:SetMaxLetters(40)
    search:HookScript("OnTextChanged", function(self)
        searchText = string.lower(self:GetText() or "")
        Board.Request()
    end)

    clearRow = CreateFrame("Frame", nil, frame)
    clearRow:SetPoint("TOPLEFT", PAD, -8)
    clearRow:SetPoint("TOPRIGHT", -PAD, -8)
    clearRow:SetHeight(26)
    clearRow.button = W.Button(clearRow, L["Clear"], "default")
    clearRow.button:SetHeight(24)
    clearRow.button:SetPoint("RIGHT")
    clearRow:Hide()

    area = W.ScrollArea(frame)
    pool = W.Pool(createCard, resetCard)
    area:HookScript("OnSizeChanged", function() Board.Request() end)

    empty = W.Text(frame, "regular", 1, "textFaint")
    empty:SetPoint("CENTER", area, "CENTER", 0, 0)
    empty:SetJustifyH("CENTER")

    frame:SetScript("OnShow", function() Board.Request() end)
    Board.SetView(view)
    return frame
end

BB:On("BOUNTIES_CHANGED", Board.Request)
BB:On("GUILD_CHANGED", Board.Request)
BB:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() if frame and frame:IsVisible() then Board.Request() end end)
BB:On("SETTINGS_CHANGED", function() Board.Request() end)
