-- Trade: reads the trade window and matches a finished trade against the bounties between the two players.
-- The addon only READS: it never accepts a trade, sends mail or moves an item or any gold.
--
-- While a trade is open the window is read after every change. When the game says "Trade complete." the last
-- state both players agreed to is matched against the active bounties between them:
--   the creator of a bounty sees the taker's items arrive and the reward leave: delivered and/or paid
--     (the creator's client is the one that makes a bounty "paid": the version goes up and everybody follows);
--   the taker sees the same trade from the other side and sends a claim, which the others show as unconfirmed.
local _, BB = ...

local Trade = {}
BB.Trade = Trade

local C, Data, Comm, L = BB.Compat, BB.Data, BB.Comm, BB.L
local min, format = math.min, string.format
local tsort = table.sort

local KEEP = 20          -- seconds a closed trade is remembered, as the "complete" message can come after the window closes
local CHECK_AFTER = 1.5  -- seconds after the window closed before the bags are asked (when no message came)

local snapshot           -- the open trade: { partner, mine = { items, money }, theirs = { items, money }, t }
local agreed             -- a copy of the snapshot at the moment both sides accepted, with the bags as they were
local closed             -- the same, kept after the window closed
local pending            -- a copy at the last moment one side had accepted: the game does not always send the final "both" update

local function describe(snap)
    local function side(s)
        local parts = {}
        for id, n in pairs(s.items) do parts[#parts + 1] = n .. "x" .. id end
        return (#parts > 0 and table.concat(parts, ",") or "no items") .. ", " .. (s.money or 0) .. "c"
    end
    return format("partner %s, I give [%s], they give [%s]", tostring(snap.partner), side(snap.mine), side(snap.theirs))
end

local function isOn(value) return value == 1 or value == true end

local function copySide(side)
    local items = {}
    for id, n in pairs(side.items) do items[id] = n end
    return { items = items, money = side.money }
end

local function copy(snap)
    return {
        partner = snap.partner, t = snap.t, mine = copySide(snap.mine), theirs = copySide(snap.theirs),
        bags = snap.bags, moneyBefore = snap.moneyBefore,
    }
end

-- ---------------------------------------------------------------------------
-- Reading the window
-- ---------------------------------------------------------------------------
local function readItems(infoFn, linkFn)
    local items = {}
    if not (infoFn and linkFn) then return items end
    for slot = 1, C.TRADE_SLOTS do
        local id = C.ItemIDFromLink(linkFn(slot))
        if id then
            local _, _, count = infoFn(slot)
            items[id] = (items[id] or 0) + (tonumber(count) or 1)
        end
    end
    return items
end

-- What is in the trade window right now.
function Trade.Read()
    return {
        partner = C.TradePartner(), t = C.Now(),
        mine = { items = readItems(GetTradePlayerItemInfo, GetTradePlayerItemLink), money = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0 },
        theirs = { items = readItems(GetTradeTargetItemInfo, GetTradeTargetItemLink), money = GetTargetTradeMoney and GetTargetTradeMoney() or 0 },
    }
end

local function refresh()
    local fresh = Trade.Read()
    if snapshot and not fresh.partner then fresh.partner = snapshot.partner end
    snapshot = fresh
    -- `agreed` stays: a change makes the game send TRADE_ACCEPT_UPDATE (0, 0), which clears it, and the window
    -- emptying itself when the trade completes must not erase what was agreed
end

-- ---------------------------------------------------------------------------
-- Matching a trade against the bounties
-- ---------------------------------------------------------------------------
-- Pure: returns what each bounty between the two players gets from this trade.
--   { { bounty, role = "creator" | "taker", items = n, copper = c }, ... }
-- Items go to the oldest bounty first, up to what it still needs; the gold pays the bounties that got items first,
-- up to what they still owe, then any other bounty between the two.
function Trade.Match(snap, me, bounties)
    local partner = snap.partner
    if not partner or not me then return {} end
    local cands = {}
    for _, b in pairs(bounties) do
        if Data.IsActive(b) and Data.TYPES[b.type] then
            if b.type == "guild" then
                -- anybody gives to the recipient, who pays the reward for each item
                local recipient = Data.Recipient(b)
                if C.SameName(recipient, me) and not C.SameName(partner, me) then
                    cands[#cands + 1] = { bounty = b, role = "creator" }
                elseif C.SameName(recipient, partner) and not C.SameName(partner, me) then
                    cands[#cands + 1] = { bounty = b, role = "taker" }
                end
            elseif C.SameName(b.creator, me) and Data.TakerEntry(b, partner) then
                cands[#cands + 1] = { bounty = b, role = "creator" }
            elseif C.SameName(b.creator, partner) and Data.TakerEntry(b, me) then
                cands[#cands + 1] = { bounty = b, role = "taker" }
            end
        end
    end
    tsort(cands, function(a, b)
        if a.bounty.createdAt ~= b.bounty.createdAt then return a.bounty.createdAt < b.bounty.createdAt end
        return a.bounty.id < b.bounty.id
    end)

    -- the items and the gold that go from the taker to the creator and back, for each role
    local pools = {
        creator = { items = {}, money = snap.mine.money or 0 },   -- I am the creator: they give items, I give gold
        taker = { items = {}, money = snap.theirs.money or 0 },   -- I am the taker: I give items, they give gold
    }
    for id, n in pairs(snap.theirs.items) do pools.creator.items[id] = n end
    for id, n in pairs(snap.mine.items) do pools.taker.items[id] = n end

    for _, cand in ipairs(cands) do
        local pool, b = pools[cand.role], cand.bounty
        local n = min(pool.items[b.itemID] or 0, Data.Remaining(b))
        cand.items, cand.copper = n, 0
        pool.items[b.itemID] = (pool.items[b.itemID] or 0) - n
    end
    for pass = 1, 2 do
        for _, cand in ipairs(cands) do
            local pool = pools[cand.role]
            local wanted = (pass == 1) == (cand.items > 0)
            if wanted and pool.money > 0 then
                local pay = min(pool.money, Data.Unpaid(cand.bounty, cand.items) - cand.copper)
                if pay > 0 then
                    cand.copper = cand.copper + pay
                    pool.money = pool.money - pay
                end
            end
        end
    end

    local out = {}
    for _, cand in ipairs(cands) do
        if cand.items > 0 or cand.copper > 0 then
            out[#out + 1] = { bounty = cand.bounty, role = cand.role, items = cand.items, copper = cand.copper }
        end
    end
    return out
end

-- Applies what Match found: the creator verifies and publishes, the taker records a claim.
function Trade.Apply(snap)
    local me = Data.Me()
    local actions = Trade.Match(snap, me, Data.All())
    BB:Debug("trade matched %d bounties (%s)", #actions, describe(snap))
    for _, a in ipairs(actions) do
        local b = a.bounty
        local name = Data.ItemName(b)
        if a.role == "creator" then
            Data.RecordTrade(b, snap.partner, a.items, a.copper)
            Comm.SendBounty(b, "high")
            if a.items > 0 then
                BB:Fire("NOTIFY", { kind = "delivery", title = L["DELIVERY VERIFIED"], text = format(L["%dx %s received via trade"], a.items, name), itemID = b.itemID, good = true })
            end
            if a.copper > 0 then
                BB:Fire("NOTIFY", { kind = "payment", title = L["PAYMENT VERIFIED"], text = format(L["%s paid to %s"], C.CoinString(a.copper), snap.partner), itemID = b.itemID, good = true })
            end
        else
            local entry = Data.RecordClaim(b, a.items, a.copper)
            if entry then
                Comm.SendProgress(b, entry)
                if a.items > 0 then
                    BB:Fire("NOTIFY", { kind = "delivery", title = L["DELIVERY RECORDED"], text = format(L["%dx %s given to %s. %s confirms it."], a.items, name, snap.partner, snap.partner), itemID = b.itemID })
                end
                if a.copper > 0 then
                    BB:Fire("NOTIFY", { kind = "payment", title = L["PAYMENT RECORDED"], text = format(L["%s received from %s"], C.CoinString(a.copper), snap.partner), itemID = b.itemID })
                end
            end
        end
    end
    if #actions > 0 then BB.Progress.Check() end
    return actions
end

-- ---------------------------------------------------------------------------
-- The end of a trade
-- ---------------------------------------------------------------------------
-- The game said "Trade complete.": match the last state both sides agreed to (else the last state seen).
function Trade.Complete()
    local snap = agreed or closed or snapshot
    agreed, closed, snapshot = nil, nil, nil
    if not snap or not snap.partner then return nil end
    BB:Debug("trade with %s complete", snap.partner)
    return Trade.Apply(snap)
end

local function bagCountFor(snap)
    local counts = {}
    for id in pairs(snap.mine.items) do counts[id] = C.ItemCount(id) end
    for id in pairs(snap.theirs.items) do counts[id] = C.ItemCount(id) end
    return counts
end

-- No message came: did the bags and the purse change the way the agreed trade says?
local function wentThrough(snap)
    if not snap.bags then return false end
    for id, n in pairs(snap.mine.items) do
        if C.ItemCount(id) <= (snap.bags[id] or 0) - min(n, snap.bags[id] or 0) and (snap.bags[id] or 0) > 0 then return true end
    end
    for id in pairs(snap.theirs.items) do
        if C.ItemCount(id) > (snap.bags[id] or 0) then return true end
    end
    if GetMoney and snap.moneyBefore then
        local delta = (snap.theirs.money or 0) - (snap.mine.money or 0)
        if delta ~= 0 and GetMoney() - snap.moneyBefore == delta then return true end
    end
    return false
end

local function onClosed()
    local source = agreed or pending
    BB:Debug("trade window closed (%s)", agreed and "both had accepted" or pending and "one side had accepted" or "nobody had accepted")
    local snap = snapshot
    snapshot, agreed, pending = nil, nil, nil
    -- the game sends TRADE_CLOSED twice: the second one finds nothing and leaves the first one's copy alone
    if not source then return end
    closed = copy(source)
    local mine = closed
    C.After(CHECK_AFTER, function()
        if closed ~= mine then return end -- the message came and was handled, or a new trade began
        if wentThrough(mine) then
            BB:Debug("no message, but the bags changed: the trade went through")
            Trade.Complete()
        end
    end)
    C.After(KEEP, function() if closed == mine then closed = nil end end)
    return snap
end

-- A system message can be a "secret" string on WoW Forever; it cannot be compared then, so it is "not this message".
local function isTradeComplete(message)
    if type(message) ~= "string" or C.IsSecret(message) then return false end
    if message:find("rade") then BB:Debug("trade message: %s", message) end
    return message == (ERR_TRADE_COMPLETE or "Trade complete.")
end

-- Debug only: which trade events the client sends.
for _, event in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE", "TRADE_REQUEST_CANCEL" }) do
    BB:RegisterEvent(event, function(...) BB:Debug("event %s %s", event, strjoin and strjoin(" ", tostringall(...)) or "") end)
end

BB:RegisterEvent("TRADE_SHOW", function()
    closed, pending = nil, nil
    snapshot = Trade.Read()
    agreed = nil
end)
BB:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED", refresh)
BB:RegisterEvent("TRADE_TARGET_ITEM_CHANGED", refresh)
BB:RegisterEvent("TRADE_MONEY_CHANGED", refresh)
BB:RegisterEvent("TRADE_ACCEPT_UPDATE", function(player, target)
    if not snapshot then snapshot = Trade.Read() end
    local fresh = Trade.Read()
    if not fresh.partner then fresh.partner = snapshot.partner end
    snapshot = fresh
    local function stamped()
        local snap = copy(snapshot)
        snap.bags = bagCountFor(snapshot)
        snap.moneyBefore = GetMoney and GetMoney() or nil
        return snap
    end
    if isOn(player) and isOn(target) then
        agreed = stamped()
        pending = nil
        BB:Debug("both accepted: %s", describe(snapshot))
    elseif isOn(player) or isOn(target) then
        agreed, pending = nil, stamped()
    else
        agreed, pending = nil, nil
    end
end)
BB:RegisterEvent("TRADE_CLOSED", onClosed)
BB:RegisterEvent("UI_INFO_MESSAGE", function(_, message)
    if isTradeComplete(message) then Trade.Complete() end
end)
BB:RegisterEvent("CHAT_MSG_SYSTEM", function(message)
    if isTradeComplete(message) then Trade.Complete() end
end)

-- For the tests: the state of the open trade.
function Trade.State() return snapshot, agreed, closed end
