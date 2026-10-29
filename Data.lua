-- Data: the bounty model, posting, taking, cancelling, expiry, the history and the rules for merging what other
-- players send. Nothing here talks to the network or draws anything; it changes the saved data and fires events.
--
-- A bounty: { id, creator, type, itemID, itemLink (local only), quantity, reward (copper), deadline (server time),
--   note, status, takers = { [name] = { progress, updatedAt, delivered, paid } }, version, createdAt,
--   deliveredQty, paidCopper, finishedAt (local), counted (local) }
--
-- The creator owns the bounty-level fields and raises `version` on every change; the highest version wins.
-- Takers send their own progress, so the takers table is merged entry by entry (the newer entry wins).
--
-- Events (BB:Fire): BOUNTIES_CHANGED (anything changed), BOUNTY_TAKEN (b, who), BOUNTY_STATUS (b, old, new).
local _, BB = ...

local Data = {}
BB.Data = Data

local C, L = BB.Compat, BB.L
local floor, min, max, format = math.floor, math.min, math.max, string.format
local sort = table.sort

Data.TYPES = { farm = true, help = true, kos = true, guild = true, craft = true }
Data.STATUSES = { open = true, taken = true, delivered = true, paid = true, closed = true, expired = true, cancelled = true }
Data.TERMINAL = { paid = true, closed = true, expired = true, cancelled = true }
Data.MAX_OPEN = 5                -- open bounties per player
Data.MAX_REMOTE_OPEN = 10        -- more than this from one player is refused when it arrives (spam)
Data.MAX_QUANTITY = 9999
Data.MAX_REWARD = 2147483647       -- the gold cap of the game (214,748g 36s 47c), in copper
Data.MAX_NOTE = 120
Data.MAX_TITLE = 60              -- what a help bounty asks for
Data.MAX_KILLS = 50              -- kills in a kill-on-sight bounty
Data.MAX_TARGET = 40             -- the target's name
Data.MAX_TAKERS = 40
Data.DAY = 86400
Data.DEADLINE_DAYS = { 1, 3, 7 }
Data.KEEP_DAYS = 30              -- how long a finished bounty stays in the history

local function bucket() return BB.Guild() end

-- Whole numbers on the wire and in the data: no fractions, no 1e+15.
local function int(n) return floor((tonumber(n) or 0) + 0.5) end

local function validName(name)
    name = C.ShortName(name)
    if not name or #name > 40 or name:find("[%c]") then return nil end
    return name
end

local function clean(text, limit)
    text = tostring(text or "")
    text = text:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if #text > limit then text = text:sub(1, limit) end
    return text
end
Data.CleanText = clean

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
function Data.All()
    local b = bucket()
    return b and b.bounties or {}
end

function Data.Get(id)
    return Data.All()[id]
end

function Data.IsTerminal(b) return Data.TERMINAL[b.status] == true end
function Data.IsActive(b) return not Data.TERMINAL[b.status] end

-- A taker who left the job stays in the table as a marker (`left`), so older copies cannot bring them back.
local function hasTakers(b)
    for _, entry in pairs(b.takers) do
        if not entry.left then return true end
    end
    return false
end

-- open <-> taken follows the takers; every other status is the creator's.
local function normalize(b)
    b.takers = b.takers or {}
    if b.status == "open" and hasTakers(b) then b.status = "taken"
    elseif b.status == "taken" and not hasTakers(b) then b.status = "open" end
    return b
end
Data.Normalize = normalize

function Data.Me() return C.PlayerName() end

function Data.IsMine(b) return C.SameName(b.creator, Data.Me()) end

-- The takers' name as the table key (the name as the taker sent it).
local function rawEntry(b, name)
    for who, entry in pairs(b.takers) do
        if C.SameName(who, name) then return entry, who end
    end
end

-- The entry of a player who has the job (nil for somebody who left it).
function Data.TakerEntry(b, name)
    local entry, who = rawEntry(b, name)
    if entry and not entry.left then return entry, who end
end

function Data.IAmTaker(b) return Data.TakerEntry(b, Data.Me()) ~= nil end

function Data.Remaining(b) return max(0, (b.quantity or 0) - (b.deliveredQty or 0)) end

-- What is still owed. A guild goal pays its reward for every item delivered (`extra`: items about to be delivered).
function Data.Unpaid(b, extra)
    if b.type == "guild" then
        return max(0, (b.reward or 0) * ((b.deliveredQty or 0) + (extra or 0)) - (b.paidCopper or 0))
    end
    return max(0, (b.reward or 0) - (b.paidCopper or 0))
end

-- Who receives the items of a guild goal (the creator unless somebody else was named).
function Data.Recipient(b) return b.recipient or b.creator end

-- Guild goals can be posted by the ranks the settings allow (0 is the Guild Master).
function Data.CanPostGuild()
    local limit = BB.db and BB.db.settings.guildPostRank
    if limit == nil then limit = 1 end
    if limit >= 99 then return true end
    local rank = C.GuildRank()
    return rank ~= nil and rank <= limit
end

-- ---------------------------------------------------------------------------
-- Status changes (the one place a status is set, so the events and the counters are always right)
-- ---------------------------------------------------------------------------
local function countCompleted(b)
    if b.counted then return end
    b.counted = true
    local stats = bucket() and bucket().stats
    if not stats then return end
    for who, entry in pairs(b.takers) do
        if not entry.left and ((entry.delivered or 0) > 0 or (entry.progress or 0) >= (b.quantity or 0)) then
            local key = C.ShortName(who) or who
            stats[key] = stats[key] or { completed = 0 }
            stats[key].completed = (stats[key].completed or 0) + 1
        end
    end
end

local function setStatus(b, status, now)
    local old = b.status
    if old == status then return false end
    b.status = status
    if Data.TERMINAL[status] then
        b.finishedAt = b.finishedAt or now or C.Now()
        if status == "paid" then countCompleted(b) end
    end
    BB:Fire("BOUNTY_STATUS", b, old, status)
    return true
end

-- How many completed jobs a player has (as a taker) in this guild.
function Data.Completed(name)
    local stats = bucket() and bucket().stats
    local entry = stats and stats[C.ShortName(name) or name]
    return entry and entry.completed or 0
end

-- ---------------------------------------------------------------------------
-- Posting, taking, cancelling
-- ---------------------------------------------------------------------------
local function newID(guild, me)
    guild.counter = (guild.counter or 0) + 1
    return format("%s-%.0f-%.0f", (me:gsub("%s", "_")), guild.counter, C.Now())
end

function Data.OpenCount(name)
    local n = 0
    for _, b in pairs(Data.All()) do
        if Data.IsActive(b) and C.SameName(b.creator, name or Data.Me()) then n = n + 1 end
    end
    return n
end

-- Posts a bounty of the player's own. opts: { itemID, itemLink, quantity, reward, days, note, type }.
-- Returns the bounty, or nil and a message for the player.
function Data.Post(opts)
    local guild, me = bucket(), Data.Me()
    if not guild or not me then return nil, L["Join a guild to post bounties."] end
    local kind = opts.type or "farm"
    if not Data.TYPES[kind] then return nil, L["That kind of bounty is not available yet."] end
    if kind == "guild" and not Data.CanPostGuild() then return nil, L["Your guild rank cannot post guild goals."] end
    local itemID, quantity, title = int(opts.itemID), int(opts.quantity), nil
    if kind == "help" then
        -- no item: a few words about what is needed, confirmed by hand by both
        title = clean(opts.title, Data.MAX_TITLE)
        if #title < 3 then return nil, L["Write what you need help with."] end
        itemID, quantity = 0, 1
    elseif kind == "kos" then
        -- no item: the name of a player and how many times to kill them
        title = clean(opts.title, Data.MAX_TARGET)
        if #title < 2 then return nil, L["Write the name of the player to hunt."] end
        if quantity < 1 or quantity > Data.MAX_KILLS then
            return nil, format(L["The number of kills must be between 1 and %d."], Data.MAX_KILLS)
        end
        itemID = 0
    else
        if itemID <= 0 then return nil, L["Shift-click an item link to choose what you want."] end
        if quantity < 1 or quantity > Data.MAX_QUANTITY then
            return nil, format(L["The quantity must be between 1 and %d."], Data.MAX_QUANTITY)
        end
    end
    local reward = int(opts.reward)
    if reward < 0 or reward > Data.MAX_REWARD then return nil, L["That reward is not possible."] end
    local days = int(opts.days)
    local allowed = false
    for _, d in ipairs(Data.DEADLINE_DAYS) do if d == days then allowed = true end end
    if not allowed then return nil, L["Choose a deadline."] end
    if Data.OpenCount() >= Data.MAX_OPEN then
        return nil, format(L["You can have %d open bounties at a time."], Data.MAX_OPEN)
    end
    local now = C.Now()
    local b = normalize({
        id = newID(guild, me), creator = me, type = kind, itemID = itemID, itemLink = opts.itemLink,
        quantity = quantity, reward = reward, deadline = now + days * Data.DAY, note = clean(opts.note, Data.MAX_NOTE), title = title,
        recipient = kind == "guild" and validName(opts.recipient) or nil,
        mats = kind == "craft" and (opts.mats == "creator" and "creator" or "crafter") or nil,
        status = "open", takers = {}, version = 1, createdAt = now, deliveredQty = 0, paidCopper = 0, class = C.PlayerClass(),
    })
    guild.bounties[b.id] = b
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- The player takes a job. Returns the taker entry, or nil and a message.
function Data.Take(id)
    local b, me = Data.Get(id), Data.Me()
    if not b then return nil, L["That bounty is gone."] end
    if not Data.IsActive(b) then return nil, L["That bounty is closed."] end
    if Data.IsMine(b) then return nil, L["You cannot take your own bounty."] end
    if Data.IAmTaker(b) then return nil, L["You have already taken this job."] end
    if C.Now() >= b.deadline then return nil, L["That bounty has run out."] end
    local now = C.Now()
    local entry = { progress = b.itemID > 0 and C.ItemCount(b.itemID) or 0, updatedAt = now, delivered = 0, paid = 0 }
    local old, oldKey = rawEntry(b, me)
    if old then entry.updatedAt = max(now, (old.updatedAt or 0) + 1) end -- taking it again beats the old "left"
    b.takers[oldKey or me] = entry
    normalize(b)
    BB:Fire("BOUNTIES_CHANGED")
    return entry
end

-- The creator cancels an active bounty; the version goes up so every client follows.
function Data.Cancel(id)
    local b = Data.Get(id)
    if not b or not Data.IsMine(b) then return nil, L["Only the creator can cancel a bounty."] end
    if not Data.IsActive(b) then return nil, L["That bounty is closed."] end
    b.version = b.version + 1
    setStatus(b, "cancelled")
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- A taker gives the job back (only while nothing was delivered). Returns the entry (marked left) or nil and a message.
function Data.Abandon(id)
    local b, me = Data.Get(id), Data.Me()
    if not b or not Data.IsActive(b) then return nil, L["That bounty is closed."] end
    local entry = Data.TakerEntry(b, me)
    if not entry then return nil, L["You have not taken this job."] end
    if (entry.delivered or 0) > 0 then return nil, L["You have already delivered items for this job."] end
    entry.left, entry.progress, entry.updatedAt = true, 0, max(C.Now(), (entry.updatedAt or 0) + 1)
    normalize(b)
    BB:Fire("BOUNTIES_CHANGED")
    return entry
end

-- The creator marks a taken bounty complete by hand (the trade was not seen, or it was paid some other way).
function Data.Complete(id)
    local b = Data.Get(id)
    if not b or not Data.IsMine(b) then return nil, L["Only the creator can complete a bounty."] end
    if not Data.IsActive(b) then return nil, L["That bounty is closed."] end
    if not hasTakers(b) then return nil, L["Nobody has taken this bounty."] end
    b.deliveredQty = b.quantity
    b.paidCopper = b.type == "guild" and b.reward * b.quantity or b.reward
    -- every hunter on the job counts as having delivered (this is what the others and the job counter see)
    for _, entry in pairs(b.takers) do
        if not entry.left then entry.delivered = max(entry.delivered or 0, 1) end
    end
    b.version = b.version + 1
    setStatus(b, "paid")
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- A kill of the target was seen (a kill-on-sight job of the player). Returns the entry, and true when that was the last
-- kill (the creator is then asked to confirm, as with help).
function Data.AddKill(b)
    local entry = Data.TakerEntry(b, Data.Me())
    if not entry or b.type ~= "kos" or not Data.IsActive(b) then return nil end
    if (entry.progress or 0) >= b.quantity then return nil end
    entry.progress = (entry.progress or 0) + 1
    entry.updatedAt = max(C.Now(), (entry.updatedAt or 0) + 1)
    local last = entry.progress >= b.quantity
    if last then entry.delivered = max(entry.delivered or 0, 1) end
    BB:Fire("BOUNTIES_CHANGED")
    return entry, last
end

-- A helper says the help is done (a help bounty; the creator confirms). Returns the entry or nil and a message.
function Data.ClaimHelp(id)
    local b = Data.Get(id)
    if not b or b.type ~= "help" or not Data.IsActive(b) then return nil, L["That bounty is closed."] end
    local entry = Data.TakerEntry(b, Data.Me())
    if not entry then return nil, L["You have not taken this job."] end
    entry.delivered, entry.updatedAt = max(entry.delivered or 0, 1), max(C.Now(), (entry.updatedAt or 0) + 1)
    BB:Fire("BOUNTIES_CHANGED")
    return entry
end

-- The creator confirms that the help was given. With a reward still unpaid it is "delivered" until the gold has
-- been traded (Trade.lua sees that); without one it is complete at once.
function Data.ConfirmHelp(id)
    local b = Data.Get(id)
    if not b or not Data.IsMine(b) or (b.type ~= "help" and b.type ~= "kos") then return nil, L["Only the creator can confirm help."] end
    if not Data.IsActive(b) then return nil, L["That bounty is closed."] end
    if not hasTakers(b) then return nil, L["Nobody has taken this bounty."] end
    b.deliveredQty = b.quantity
    for _, entry in pairs(b.takers) do
        if not entry.left then entry.delivered = max(entry.delivered or 0, 1) end
    end
    b.version = b.version + 1
    setStatus(b, Data.Unpaid(b) == 0 and "paid" or "delivered")
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- The creator closes a bounty that was delivered (paid some other way).
function Data.Close(id)
    local b = Data.Get(id)
    if not b or not Data.IsMine(b) then return nil, L["Only the creator can close a bounty."] end
    if b.status ~= "delivered" then return nil, L["Only a delivered bounty can be closed."] end
    b.version = b.version + 1
    setStatus(b, "closed")
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- ---------------------------------------------------------------------------
-- Verified trades (see Trade.lua)
-- ---------------------------------------------------------------------------
-- The creator saw `items` of the item arrive and paid `copper` in a trade with the taker `who`. Returns the bounty.
function Data.RecordTrade(b, who, items, copper)
    b.deliveredQty = (b.deliveredQty or 0) + max(0, items or 0)
    b.paidCopper = (b.paidCopper or 0) + max(0, copper or 0)
    local entry = Data.TakerEntry(b, who)
    if not entry and b.type == "guild" then
        -- anybody may give to a guild goal: the first delivery makes them a contributor
        entry = { progress = 0, updatedAt = C.Now(), delivered = 0, paid = 0 }
        b.takers[who] = entry
    end
    if entry then
        entry.delivered = (entry.delivered or 0) + max(0, items or 0)
        entry.paid = (entry.paid or 0) + max(0, copper or 0)
    end
    b.version = b.version + 1
    local delivered = b.deliveredQty >= b.quantity
    local paid = b.paidCopper >= (b.type == "guild" and b.reward * b.deliveredQty or b.reward)
    if delivered and paid then setStatus(b, "paid")
    elseif delivered then setStatus(b, "delivered") end
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- The taker's own side of the same trade (a claim; the creator's version is the one that counts).
function Data.RecordClaim(b, items, copper)
    local entry, who = Data.TakerEntry(b, Data.Me())
    if not entry and b.type == "guild" then
        who = Data.Me()
        entry = { progress = C.ItemCount(b.itemID), updatedAt = C.Now(), delivered = 0, paid = 0 }
        b.takers[who] = entry
        normalize(b)
    end
    if not entry then return nil end
    entry.delivered = (entry.delivered or 0) + max(0, items or 0)
    entry.paid = (entry.paid or 0) + max(0, copper or 0)
    entry.updatedAt = C.Now()
    BB:Fire("BOUNTIES_CHANGED")
    return entry, who
end

-- A new number of the item in the player's bags. Returns the entry when it changed.
function Data.SetProgress(b, count)
    local entry = Data.TakerEntry(b, Data.Me())
    if not entry or entry.progress == count then return nil end
    entry.progress = count
    entry.updatedAt = C.Now()
    BB:Fire("BOUNTIES_CHANGED")
    return entry
end

-- ---------------------------------------------------------------------------
-- Expiry and tidying
-- ---------------------------------------------------------------------------
-- Every client closes a bounty at its deadline by itself (same server time everywhere), so nothing is sent.
function Data.Expire(now)
    now = now or C.Now()
    local changed = {}
    for _, b in pairs(Data.All()) do
        if Data.IsActive(b) and now >= b.deadline then
            setStatus(b, "expired", b.deadline)
            changed[#changed + 1] = b
        end
    end
    if #changed > 0 then BB:Fire("BOUNTIES_CHANGED") end
    return changed
end

-- Finished bounties older than KEEP_DAYS leave the history (the completed-jobs counters stay).
-- Finished bounties the player cleared from the lists: remembered by id, so the guild's manifests do not bring them back.
function Data.IsCleared(id)
    local guild = bucket()
    return guild ~= nil and guild.cleared ~= nil and guild.cleared[id] ~= nil
end

-- How many finished bounties a clear would remove. scope: "history" (all) or "mine" (the player's own).
function Data.FinishedCount(scope)
    local n = 0
    for _, b in pairs(Data.All()) do
        if Data.IsTerminal(b) and (scope ~= "mine" or Data.IsMine(b)) then n = n + 1 end
    end
    return n
end

function Data.ClearFinished(scope)
    local guild = bucket()
    if not guild then return 0 end
    guild.cleared = guild.cleared or {}
    local n = 0
    for id, b in pairs(guild.bounties) do
        if Data.IsTerminal(b) and (scope ~= "mine" or Data.IsMine(b)) then
            guild.bounties[id] = nil
            guild.cleared[id] = C.Now()
            n = n + 1
        end
    end
    if n > 0 then BB:Fire("BOUNTIES_CHANGED") end
    return n
end

function Data.Prune(now)
    now = now or C.Now()
    local bounties = Data.All()
    local removed = 0
    local guild = bucket()
    if guild and guild.cleared then
        for id, at in pairs(guild.cleared) do
            if now - at > Data.KEEP_DAYS * Data.DAY then guild.cleared[id] = nil end
        end
    end
    for id, b in pairs(bounties) do
        if Data.IsTerminal(b) and now - (b.finishedAt or b.deadline or 0) > ((BB.db and BB.db.settings.historyDays) or Data.KEEP_DAYS) * Data.DAY then
            bounties[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- ---------------------------------------------------------------------------
-- The wire format: a flat table of short keys (Comm turns it into text)
-- ---------------------------------------------------------------------------
local function escTok(s) return (s:gsub("[%%:,]", function(ch) return format("%%%02X", ch:byte()) end)) end
local function unescTok(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function encodeTakers(takers)
    local out = {}
    for who, e in pairs(takers) do
        out[#out + 1] = format("%s:%.0f:%.0f:%.0f:%.0f", escTok(who), int(e.progress), int(e.updatedAt), int(e.delivered), int(e.paid)) .. (e.left and ":1" or "")
    end
    sort(out)
    return table.concat(out, ",")
end


local function decodeTakers(text)
    local takers, count = {}, 0
    for entry in tostring(text or ""):gmatch("[^,]+") do
        local who, progress, updatedAt, delivered, paid, left = entry:match("^([^:]+):(%d+):(%d+):(%d+):(%d+):?(%d*)$")
        who = who and validName(unescTok(who))
        if who then
            count = count + 1
            if count > Data.MAX_TAKERS then break end
            takers[who] = { progress = tonumber(progress), updatedAt = tonumber(updatedAt), delivered = tonumber(delivered), paid = tonumber(paid), left = left == "1" or nil }
        end
    end
    return takers
end

function Data.ToWire(b)
    return {
        i = b.id, c = b.creator, y = b.type, m = b.itemID, q = b.quantity, r = b.reward, d = b.deadline,
        n = b.note or "", s = b.status, v = b.version, t = b.createdAt, dq = b.deliveredQty or 0, pc = b.paidCopper or 0,
        cl = b.class or "", fa = b.finishedAt or 0, ti = b.title or "", rc = b.recipient or "", mt = b.mats or "",
        k = encodeTakers(b.takers),
    }
end

-- Takes a table of strings from the network and makes a clean bounty of it, or returns nil and the reason.
-- Nothing from the network is trusted: every field is checked and cut to size.
function Data.FromWire(t)
    if type(t) ~= "table" then return nil, "not a table" end
    local id = tostring(t.i or "")
    if id == "" or #id > 80 or id:find("[%c]") then return nil, "bad id" end
    local creator = validName(t.c)
    if not creator then return nil, "bad creator" end
    local kind = tostring(t.y or "")
    if not Data.TYPES[kind] then return nil, "unknown type" end
    local itemID, quantity, reward = tonumber(t.m), tonumber(t.q), tonumber(t.r)
    local title = clean(t.ti, Data.MAX_TITLE)
    if kind == "help" then
        if #title < 3 then return nil, "bad title" end
        itemID, quantity = 0, 1
    elseif kind == "kos" then
        if #title < 2 or #title > Data.MAX_TARGET then return nil, "bad target" end
        itemID = 0
        if not quantity or quantity < 1 or quantity > Data.MAX_KILLS or quantity ~= floor(quantity) then return nil, "bad kills" end
    else
        title = ""
        if not itemID or itemID < 1 or itemID > 9999999 or itemID ~= floor(itemID) then return nil, "bad item" end
        if not quantity or quantity < 1 or quantity > Data.MAX_QUANTITY or quantity ~= floor(quantity) then return nil, "bad quantity" end
    end
    if not reward or reward < 0 or reward > Data.MAX_REWARD or reward ~= floor(reward) then return nil, "bad reward" end
    local deadline, createdAt, version = tonumber(t.d), tonumber(t.t), tonumber(t.v)
    if not deadline or not createdAt or not version or version < 1 or version > 1000000 then return nil, "bad times" end
    if deadline < createdAt or deadline - createdAt > 31 * Data.DAY then return nil, "bad deadline" end
    if createdAt > C.Now() + 3600 then return nil, "from the future" end
    local status = tostring(t.s or "")
    if not Data.STATUSES[status] then return nil, "bad status" end
    return normalize({
        id = id, creator = creator, type = kind, itemID = itemID, quantity = quantity, reward = reward,
        deadline = deadline, createdAt = createdAt, version = floor(version), status = status,
        note = clean(t.n, Data.MAX_NOTE), takers = decodeTakers(t.k),
        deliveredQty = max(0, floor(tonumber(t.dq) or 0)), paidCopper = max(0, floor(tonumber(t.pc) or 0)),
        class = C.IsClassToken(t.cl) and t.cl or nil, title = title ~= "" and title or nil,
        recipient = kind == "guild" and validName(t.rc) or nil,
        mats = kind == "craft" and (t.mt == "creator" and "creator" or "crafter") or nil,
        finishedAt = (tonumber(t.fa) or 0) >= createdAt and tonumber(t.fa) <= C.Now() + 3600 and floor(tonumber(t.fa)) or nil,
    })
end

-- ---------------------------------------------------------------------------
-- Merging what other players send
-- ---------------------------------------------------------------------------
-- A taker's entry: the newer one wins, but a claim of delivered items or paid gold never goes down.
local function mergeTaker(mine, theirs)
    if not mine then return { progress = theirs.progress, updatedAt = theirs.updatedAt, delivered = theirs.delivered, paid = theirs.paid, left = theirs.left }, true end
    local changed = false
    if (theirs.updatedAt or 0) > (mine.updatedAt or 0) then
        mine.progress, mine.updatedAt, mine.left = theirs.progress, theirs.updatedAt, theirs.left
        changed = true
    end
    if (theirs.delivered or 0) > (mine.delivered or 0) then mine.delivered, changed = theirs.delivered, true end
    if (theirs.paid or 0) > (mine.paid or 0) then mine.paid, changed = theirs.paid, true end
    return mine, changed
end

local function mergeTakers(b, remoteTakers, me)
    local changed = false
    for who, entry in pairs(remoteTakers) do
        -- the player's own entry is written here and nowhere else: others' copies never overwrite it
        if not C.SameName(who, me) then
            local existing, key = rawEntry(b, who)
            local merged, did = mergeTaker(existing, entry)
            b.takers[key or who] = merged
            changed = changed or did
        end
    end
    return changed
end

-- A bounty (already through FromWire) arrived from `sender`. Returns "new", "updated", "merged" or "ignored"
-- with the bounty, and a reason when it is ignored.
function Data.ApplyRemote(remote, _)
    local guild = bucket()
    if not guild then return "ignored", nil, "no guild" end
    if guild.cleared and guild.cleared[remote.id] then return "ignored", nil, "cleared" end
    local me = Data.Me()
    local current = guild.bounties[remote.id]
    if not current then
        -- a creator cannot have more than a few active bounties: more is spam (or a sync that lost updates)
        local active = 0
        for _, other in pairs(guild.bounties) do
            if Data.IsActive(other) and C.SameName(other.creator, remote.creator) then active = active + 1 end
        end
        if Data.IsActive(remote) and active >= Data.MAX_REMOTE_OPEN then return "ignored", nil, "too many bounties" end
        local status = remote.status
        remote.status = status == "taken" and "open" or status
        normalize(remote)
        guild.bounties[remote.id] = remote
        if Data.TERMINAL[status] then
            remote.finishedAt = remote.finishedAt or C.Now()
            if status == "paid" then countCompleted(remote) end
        end
        BB:Fire("BOUNTIES_CHANGED")
        return "new", remote
    end
    if not C.SameName(current.creator, remote.creator) then return "ignored", current, "different creator" end
    if remote.version > current.version then
        current.type, current.itemID, current.quantity = remote.type, remote.itemID, remote.quantity
        current.reward, current.deadline, current.note = remote.reward, remote.deadline, remote.note
        current.createdAt, current.version = remote.createdAt, remote.version
        current.deliveredQty, current.paidCopper = remote.deliveredQty, remote.paidCopper
        current.class = remote.class or current.class
        current.title = remote.title or current.title
        current.recipient = remote.recipient or current.recipient
        mergeTakers(current, remote.takers, me)
        -- open and taken follow the takers; any other status is the creator's word
        local target = remote.status
        if target == "open" or target == "taken" then target = hasTakers(current) and "taken" or "open" end
        setStatus(current, target, remote.finishedAt)
        BB:Fire("BOUNTIES_CHANGED")
        return "updated", current
    end
    if mergeTakers(current, remote.takers, me) then
        normalize(current)
        BB:Fire("BOUNTIES_CHANGED")
        return "merged", current
    end
    return "ignored", current, "not newer"
end

-- Somebody took a job (a TAKE message). The sender is the taker.
function Data.ApplyTake(id, who, updatedAt, progress)
    local b = Data.Get(id)
    if not b then return nil, "unknown bounty" end
    if not Data.IsActive(b) then return nil, "closed" end
    if C.SameName(b.creator, who) then return nil, "creator" end
    if Data.TakerEntry(b, who) then return b, "known" end
    if C.SameName(who, Data.Me()) then return nil, "self" end
    local takers = 0
    for _, entry in pairs(b.takers) do if not entry.left then takers = takers + 1 end end
    if takers >= Data.MAX_TAKERS then return nil, "full" end
    local old, oldKey = rawEntry(b, who)
    if old and int(updatedAt) <= (old.updatedAt or 0) then return nil, "left" end -- an old take after leaving
    b.takers[oldKey or who] = { progress = max(0, int(progress)), updatedAt = int(updatedAt), delivered = 0, paid = 0 }
    normalize(b)
    BB:Fire("BOUNTIES_CHANGED")
    if Data.IsMine(b) then BB:Fire("BOUNTY_TAKEN", b, who) end
    return b
end

-- A taker's progress or claim (a PROG message). Returns the bounty when something changed.
function Data.ApplyProgress(id, who, progress, updatedAt, delivered, paid)
    local b = Data.Get(id)
    if not b then return nil, "unknown bounty" end
    if C.SameName(who, Data.Me()) then return nil, "self" end
    local entry, key = Data.TakerEntry(b, who)
    if not entry then return nil, "not a taker" end
    local wasDone = entry.delivered or 0
    local _, changed = mergeTaker(entry, {
        progress = max(0, int(progress)), updatedAt = int(updatedAt), delivered = max(0, int(delivered)), paid = max(0, int(paid)),
    })
    b.takers[key] = entry
    if changed then
        BB:Fire("BOUNTIES_CHANGED")
        if (b.type == "help" or b.type == "kos") and Data.IsMine(b) and (entry.delivered or 0) > 0 and wasDone == 0 then
            BB:Fire("HELP_DONE", b, key)
        end
    end
    return b, changed
end

-- A taker gave the job back (an ABANDON message; the sender is the taker).
function Data.ApplyAbandon(id, who, updatedAt)
    local b = Data.Get(id)
    if not b then return nil, "unknown bounty" end
    local entry = Data.TakerEntry(b, who)
    if not entry or (entry.delivered or 0) > 0 or int(updatedAt) < (entry.updatedAt or 0) then return nil, "no change" end
    entry.left, entry.progress, entry.updatedAt = true, 0, int(updatedAt)
    if Data.IsActive(b) then normalize(b) end
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- The creator cancelled (a CANCEL message, newer than what is known).
function Data.ApplyCancel(id, who, version)
    local b = Data.Get(id)
    if not b then return nil, "unknown bounty" end
    if not C.SameName(b.creator, who) then return nil, "not the creator" end
    if not Data.IsActive(b) or version <= b.version then return nil, "old" end
    b.version = version
    setStatus(b, "cancelled")
    BB:Fire("BOUNTIES_CHANGED")
    return b
end

-- ---------------------------------------------------------------------------
-- Lists for the windows
-- ---------------------------------------------------------------------------
local function sorted(list, key, descending)
    sort(list, function(a, b)
        local x, y = a[key] or 0, b[key] or 0
        if x == y then return a.id < b.id end
        if descending then return x > y end
        return x < y
    end)
    return list
end

local function collect(pred)
    local list = {}
    for _, b in pairs(Data.All()) do if pred(b) then list[#list + 1] = b end end
    return list
end

-- Every active bounty of the guild, newest first.
function Data.Board() return sorted(collect(Data.IsActive), "createdAt", true) end

-- The player's own bounties: the active ones, and the ones that finished in the last two days.
function Data.Mine()
    local cutoff = C.Now() - 2 * Data.DAY
    return sorted(collect(function(b)
        return Data.IsMine(b) and (Data.IsActive(b) or (b.finishedAt or 0) >= cutoff)
    end), "createdAt", true)
end

-- The jobs the player took that are still active.
function Data.Jobs() return sorted(collect(function(b) return Data.IsActive(b) and Data.IAmTaker(b) end), "deadline", false) end

-- Finished bounties, newest first.
function Data.History() return sorted(collect(Data.IsTerminal), "finishedAt", true) end

function Data.ActiveCount()
    local n = 0
    for _, b in pairs(Data.All()) do if Data.IsActive(b) then n = n + 1 end end
    return n
end

-- id and version of what the player knows, for the manifest (active bounties, and what ended in the last two days).
function Data.Manifest(limit)
    local cutoff = C.Now() - 2 * Data.DAY
    local list = sorted(collect(function(b) return Data.IsActive(b) or (b.finishedAt or 0) >= cutoff end), "createdAt", true)
    local out = {}
    for i = 1, min(#list, limit or 80) do out[i] = { id = list[i].id, version = list[i].version } end
    return out
end

-- Seconds left to the deadline (0 when it has passed).
function Data.TimeLeft(b, now)
    return max(0, (b.deadline or 0) - (now or C.Now()))
end

-- "2 days left", "5 h left", "12 min left".
function Data.TimeLeftText(b, now)
    local s = Data.TimeLeft(b, now)
    if s >= 2 * Data.DAY then return format(L["%d days left"], floor(s / Data.DAY)) end
    if s >= 3600 then return format(L["%d h left"], floor(s / 3600)) end
    return format(L["%d min left"], max(1, floor(s / 60)))
end

-- "just now", "5 min ago", "2 h ago", "3 days ago".
function Data.AgeText(seconds)
    if seconds < 60 then return L["just now"] end
    if seconds < 3600 then return format(L["%d min ago"], floor(seconds / 60)) end
    if seconds < Data.DAY then return format(L["%d h ago"], floor(seconds / 3600)) end
    return format(L["%d days ago"], floor(seconds / Data.DAY))
end

-- The link of a bounty's item, when the game knows it; otherwise a plain name.
function Data.ItemName(b)
    if b.type == "help" then return b.title or L["Help"] end
    if b.type == "kos" then return format(L["Kill %s"], b.title or "?") end
    local name, link = C.ItemInfo(b.itemID)
    if link then b.itemLink = link end
    return name or (b.itemLink and b.itemLink:match("%[(.-)%]")) or format(L["Item %d"], b.itemID)
end

-- ---------------------------------------------------------------------------
-- Upkeep: old bounties leave, and every half minute the ones past their deadline close
-- ---------------------------------------------------------------------------
BB:On("LOGIN", function()
    Data.Prune()
    Data.Expire()
    C.Ticker(30, function() Data.Expire() end)
end)
