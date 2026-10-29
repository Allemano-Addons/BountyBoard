-- Progress: for every job the player took, count the item in the bags and tell the guild when the number changes.
-- Only informative: the trade (Trade.lua) decides what was really delivered. The number can go down again when
-- the player sells or uses the items.
local _, BB = ...

local Progress = {}
BB.Progress = Progress

local C, Data, Comm = BB.Compat, BB.Data, BB.Comm

local DEBOUNCE = 1       -- bag events come in bursts: count one second after the last one
local MIN_INTERVAL = 5   -- seconds between two messages about the same bounty

local lastSent = {}      -- bounty id -> server time of the last message
local waiting = {}       -- bounty id -> true while a message is scheduled
local counting = false

local function send(b)
    local entry = Data.TakerEntry(b, Data.Me())
    if not entry then return end
    lastSent[b.id] = C.Now()
    Comm.SendProgress(b, entry)
end

-- A changed number goes out now, or as soon as MIN_INTERVAL allows (with the number it has by then).
local function announce(b)
    local wait = (lastSent[b.id] or 0) + MIN_INTERVAL - C.Now()
    if wait <= 0 then
        send(b)
    elseif not waiting[b.id] then
        waiting[b.id] = true
        C.After(wait, function()
            waiting[b.id] = nil
            local current = Data.Get(b.id)
            if current and Data.IsActive(current) then send(current) end
        end)
    end
end

-- Counts the bags for every active job of the player.
function Progress.Check()
    for _, b in ipairs(Data.Jobs()) do
        local entry = (b.type == "farm" or b.type == "guild" or b.type == "craft") and Data.SetProgress(b, C.ItemCount(b.itemID))
        if entry then
            BB:Debug("progress %s: %d/%d", b.id, entry.progress, b.quantity)
            announce(b)
        end
    end
end

-- The bags changed: count once things have calmed down.
function Progress.Touch()
    if counting then return end
    counting = true
    C.After(DEBOUNCE, function()
        counting = false
        Progress.Check()
    end)
end

-- A job was just taken: the take message carries the number, so the next one may wait.
function Progress.Taken(b)
    lastSent[b.id] = C.Now()
end

BB:RegisterEvent("BAG_UPDATE", Progress.Touch)
BB:RegisterEvent("BAG_UPDATE_DELAYED", Progress.Touch)
BB:On("LOGIN", function() C.After(6, Progress.Check) end)
BB:On("GUILD_CHANGED", function() C.After(2, Progress.Check) end)
