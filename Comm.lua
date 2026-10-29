-- Comm: addon messages on the guild channel. Turns bounties into text and back, cuts long messages into parts,
-- sends them slowly (a queue), puts them together again, and keeps the guild's copies in step (manifest and request).
--
-- A message:  <protocol>|<kind>|<id>|<part>/<parts>|<data>      data = key=value;key=value with %XX escapes
-- Kinds: N new bounty, U updated bounty, T take, C cancel, P progress, M manifest (what I know), R request (what I lack)
--
-- Nothing in a message is trusted: the sender of a take or a progress must be the player it names, a cancel must
-- come from the creator, and every field is checked by Data.FromWire. A bounty may be passed on by a guildmate
-- while its creator is offline; there is no signature, so the guild is trusted not to forge (see README).
local _, BB = ...

local Comm = {}
BB.Comm = Comm

local C, Data = BB.Compat, BB.Data
local floor, ceil, format, min = math.floor, math.ceil, string.format, math.min
local tinsert, tremove = table.insert, table.remove

local PROTOCOL = "1"
local CHUNK = 200             -- characters of data per message (the game allows 255 with the header and the prefix)
local MAX_PARTS = 12
local MAX_BUFFERS = 30
local BUFFER_TTL = 60         -- seconds a half-received message is kept
local SEND_INTERVAL = 0.35    -- seconds between two messages
local THROTTLE_BACKOFF = 2    -- seconds to wait when the game says "too fast"
local SUPPRESS = 30           -- seconds in which a bounty somebody else just sent is not sent again
local MAX_OFFER, MAX_WANT = 20, 30
local MANIFEST_EVERY = 600

local KIND = { NEW = "N", UPDATE = "U", TAKE = "T", CANCEL = "C", PROG = "P", MANIFEST = "M", REQ = "R", ABANDON = "A" }
Comm.KIND = KIND
local KNOWN = {}
for _, k in pairs(KIND) do KNOWN[k] = true end

Comm.Random = math.random -- replaced in the tests

-- ---------------------------------------------------------------------------
-- Text <-> table
-- ---------------------------------------------------------------------------
local function esc(value)
    if type(value) == "number" then value = format("%.0f", value) end
    return (tostring(value):gsub("[^%w _%.%-]", function(ch) return format("%%%02X", ch:byte()) end))
end

local function unesc(text)
    return (text:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- A flat table of strings and numbers to "k=v;k=v" (keys sorted, so the same table is always the same text).
function Comm.Encode(fields)
    local keys = {}
    for k in pairs(fields) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. esc(fields[k]) end
    return table.concat(out, ";")
end

-- The other way round; at most 40 fields, short lower-case keys only. Always returns a table.
function Comm.Decode(text)
    local out, count = {}, 0
    for pair in tostring(text or ""):gmatch("[^;]+") do
        local k, v = pair:match("^(%l%l?)=(.*)$")
        if k then
            count = count + 1
            if count > 40 then break end
            out[k] = unesc(v)
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Sending: a queue and a ticker
-- ---------------------------------------------------------------------------
local queue = { high = {}, low = {} }
local ticker, blockedUntil = nil, 0
Comm.queue = queue

local function randomID()
    local chars, id = "abcdefghijklmnopqrstuvwxyz0123456789", {}
    for i = 1, 6 do
        local n = Comm.Random(1, #chars)
        id[i] = chars:sub(n, n)
    end
    return table.concat(id)
end

local function pump()
    if C.Now() < blockedUntil then return end
    local list = queue.high[1] and queue.high or queue.low
    local text = list[1]
    if not text then
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    if C.SendGuildMessage(text) then
        tremove(list, 1)
    else
        blockedUntil = C.Now() + THROTTLE_BACKOFF -- the game said "too fast": the same message again a little later
        BB:Debug("send throttled")
    end
end

-- Sends everything now (the tests, and a logout).
function Comm.Flush()
    local guard = 0
    while (queue.high[1] or queue.low[1]) and guard < 1000 do
        guard = guard + 1
        blockedUntil = 0
        pump()
    end
end

-- Queues a message of `kind` with `fields`. priority: "high" for what a player is waiting for, else "low".
function Comm.Send(kind, fields, priority)
    if not C.GuildName() then return false end
    local data = Comm.Encode(fields)
    local parts = math.max(1, ceil(#data / CHUNK))
    if parts > MAX_PARTS then
        BB:Debug("message too long (%d parts), not sent", parts)
        return false
    end
    local id = randomID()
    local list = priority == "high" and queue.high or queue.low
    for i = 1, parts do
        tinsert(list, table.concat({ PROTOCOL, kind, id, i .. "/" .. parts, data:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "|"))
    end
    if not ticker then ticker = C.Ticker(SEND_INTERVAL, pump) end
    return true
end

-- ---------------------------------------------------------------------------
-- What others have already sent (so a guild of fifty does not answer a login fifty times)
-- ---------------------------------------------------------------------------
local seen = {}

local function markSeen(id, version) seen[id .. "@" .. version] = C.Now() end

local function recentlySeen(id, version)
    local at = seen[id .. "@" .. version]
    return at ~= nil and C.Now() - at < SUPPRESS
end

-- ---------------------------------------------------------------------------
-- Messages this player sends
-- ---------------------------------------------------------------------------
-- A bounty: new (first version) or updated.
function Comm.SendBounty(b, priority, relay)
    local fields = Data.ToWire(b)
    if relay then fields.rl = "1" end
    markSeen(b.id, b.version)
    return Comm.Send((b.version == 1 and not relay) and KIND.NEW or KIND.UPDATE, fields, priority or "high")
end

function Comm.SendTake(b, entry)
    return Comm.Send(KIND.TAKE, { i = b.id, w = C.PlayerName(), t = entry.updatedAt, p = entry.progress }, "high")
end

function Comm.SendAbandon(b, entry)
    return Comm.Send(KIND.ABANDON, { i = b.id, w = C.PlayerName(), t = entry.updatedAt }, "high")
end

function Comm.SendCancel(b)
    markSeen(b.id, b.version)
    return Comm.Send(KIND.CANCEL, { i = b.id, v = b.version }, "high")
end

function Comm.SendProgress(b, entry)
    return Comm.Send(KIND.PROG, {
        i = b.id, w = C.PlayerName(), p = entry.progress, t = entry.updatedAt, dl = entry.delivered or 0, pd = entry.paid or 0,
    }, "low")
end

local function entryList(list) return table.concat(list, ",") end

-- What this player knows: id:version for every active bounty and what ended recently.
function Comm.SendManifest()
    local items = {}
    for i, m in ipairs(Data.Manifest(80)) do items[i] = esc(m.id) .. ":" .. m.version end
    BB:Debug("manifest: %d bounties", #items)
    return Comm.Send(KIND.MANIFEST, { e = entryList(items) }, "low")
end

function Comm.SendRequest(ids)
    local items = {}
    for i = 1, min(#ids, MAX_WANT) do items[i] = esc(ids[i]) end
    if #items == 0 then return false end
    return Comm.Send(KIND.REQ, { e = entryList(items) }, "low")
end

-- Sends a bounty after a short random wait, unless somebody else sends the same version first.
local function scheduleOffer(b)
    local id, version = b.id, b.version
    -- somebody asked just now: an older send does not count, only one that happens during the wait
    seen[id .. "@" .. version] = nil
    C.After(Comm.Random(10, 40) / 10, function()
        local current = Data.Get(id)
        if not current or current.version < version or recentlySeen(id, current.version) then return end
        Comm.SendBounty(current, "low", not Data.IsMine(current))
    end)
end

-- ---------------------------------------------------------------------------
-- Messages that arrive
-- ---------------------------------------------------------------------------
Comm.lastSyncAt = nil -- server time of the last valid message from the guild ("Synced 12s ago")

local function parseList(text)
    local out = {}
    for entry in tostring(text or ""):gmatch("[^,]+") do out[#out + 1] = entry end
    return out
end

local function onBounty(sender, fields)
    local b, why = Data.FromWire(fields)
    if not b then BB:Debug("bad bounty from %s: %s", tostring(sender), tostring(why)) return end
    markSeen(b.id, b.version)
    local result = Data.ApplyRemote(b, sender)
    BB:Debug("bounty %s v%d from %s: %s", b.id, b.version, sender, result)
end

local function onTake(sender, fields)
    local id = fields.i
    if not id or not C.SameName(fields.w, sender) then return end
    local b, why = Data.ApplyTake(id, sender, tonumber(fields.t) or C.Now(), tonumber(fields.p) or 0)
    if not b and why == "unknown bounty" then Comm.SendRequest({ id }) end
end

local function onCancel(sender, fields)
    local id, version = fields.i, tonumber(fields.v)
    if not id or not version then return end
    markSeen(id, version)
    Data.ApplyCancel(id, sender, floor(version))
end

local function onAbandon(sender, fields)
    local id = fields.i
    if not id or not C.SameName(fields.w, sender) then return end
    Data.ApplyAbandon(id, sender, tonumber(fields.t) or C.Now())
end

local function onProgress(sender, fields)
    local id = fields.i
    if not id or not C.SameName(fields.w, sender) then return end
    Data.ApplyProgress(id, sender, tonumber(fields.p) or 0, tonumber(fields.t) or C.Now(), tonumber(fields.dl) or 0, tonumber(fields.pd) or 0)
end

local function onManifest(_, fields)
    local theirs, wanted = {}, {}
    local count = 0
    for _, entry in ipairs(parseList(fields.e)) do
        local id, version = entry:match("^(.-):(%d+)$")
        if id then
            count = count + 1
            if count > 120 then break end
            id, version = unesc(id), tonumber(version)
            theirs[id] = version
            local mine = Data.Get(id)
            if (not mine or mine.version < version) and not Data.IsCleared(id) then wanted[#wanted + 1] = id end
        end
    end
    -- ask for what is missing here, after a little wait (several manifests may arrive together)
    if #wanted > 0 then
        C.After(Comm.Random(10, 30) / 10, function()
            local still = {}
            for _, id in ipairs(wanted) do
                local mine = Data.Get(id)
                if not mine or mine.version < theirs[id] then still[#still + 1] = id end
            end
            Comm.SendRequest(still)
        end)
    end
    -- offer what the sender lacks
    local offered = 0
    for _, b in ipairs(Data.Manifest(80)) do
        local v = theirs[b.id]
        if (not v or v < b.version) and offered < MAX_OFFER then
            offered = offered + 1
            scheduleOffer(Data.Get(b.id))
        end
    end
end

local function onRequest(_, fields)
    local count = 0
    for _, entry in ipairs(parseList(fields.e)) do
        count = count + 1
        if count > MAX_WANT then break end
        local b = Data.Get(unesc(entry))
        if b then scheduleOffer(b) end
    end
end

local HANDLERS = {
    [KIND.NEW] = onBounty, [KIND.UPDATE] = onBounty, [KIND.TAKE] = onTake, [KIND.CANCEL] = onCancel,
    [KIND.PROG] = onProgress, [KIND.ABANDON] = onAbandon, [KIND.MANIFEST] = onManifest, [KIND.REQ] = onRequest,
}

-- Half-received messages, by sender and message id.
local buffers, bufferCount = {}, 0

local function dropOldBuffers()
    local now = C.Now()
    for key, buf in pairs(buffers) do
        if now - buf.at > BUFFER_TTL then
            buffers[key] = nil
            bufferCount = bufferCount - 1
        end
    end
end

local function handle(sender, kind, data)
    if not BB.Guild() then return end
    Comm.lastSyncAt = C.Now()
    local fields = Comm.Decode(data)
    local fn = HANDLERS[kind]
    if fn then fn(sender, fields) end
end

-- CHAT_MSG_ADDON arrives here: prefix, text, channel, sender.
function Comm.OnMessage(prefix, text, channel, sender)
    if prefix ~= BB.PREFIX or channel ~= "GUILD" or type(text) ~= "string" or C.IsSecret(text) then return end
    sender = C.ShortName(sender)
    if not sender or C.SameName(sender, C.PlayerName()) then return end
    local proto, kind, id, part, parts, data = text:match("^(%d+)|(%a)|(%w+)|(%d+)/(%d+)|(.*)$")
    if proto ~= PROTOCOL or not KNOWN[kind] then return end
    part, parts = tonumber(part), tonumber(parts)
    if not part or not parts or parts < 1 or parts > MAX_PARTS or part < 1 or part > parts then return end
    if parts == 1 then
        handle(sender, kind, data)
        return
    end
    local key = sender .. "|" .. id
    local buf = buffers[key]
    if not buf then
        dropOldBuffers()
        if bufferCount >= MAX_BUFFERS then return end
        buf = { kind = kind, parts = parts, got = 0, data = {}, at = C.Now() }
        buffers[key] = buf
        bufferCount = bufferCount + 1
    end
    if buf.kind ~= kind or buf.parts ~= parts or buf.data[part] then return end
    buf.data[part] = data
    buf.got = buf.got + 1
    if buf.got == parts then
        buffers[key] = nil
        bufferCount = bufferCount - 1
        handle(sender, kind, table.concat(buf.data))
    end
end

BB:RegisterEvent("CHAT_MSG_ADDON", Comm.OnMessage)

-- ---------------------------------------------------------------------------
-- Staying in step: a manifest after login (with a random wait, so the guild is not asked all at once), and
-- another every ten minutes in case a message was lost.
-- ---------------------------------------------------------------------------
local started = false

BB:On("GUILD_CHANGED", function(name)
    if not name or started then return end
    started = true
    C.After(Comm.Random(60, 140) / 10, function() Comm.SendManifest() end)
    C.Ticker(MANIFEST_EVERY, function()
        C.After(Comm.Random(0, 300) / 10, function() Comm.SendManifest() end)
    end)
end)

-- Seconds since the last message from the guild, or nil.
function Comm.SyncAge()
    if not Comm.lastSyncAt then return nil end
    return math.max(0, C.Now() - Comm.lastSyncAt)
end
