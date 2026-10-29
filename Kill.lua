-- Kill: counts kills for the kill-on-sight jobs the player took. The game's combat log says "PARTY_KILL" when the
-- player or somebody in the group kills a player; if that player is the target of a job the kill is counted and
-- sent to the guild (the creator sees the count and confirms by hand, as with help). Read-only, like the rest.
-- The combat log is busy, so the event is only registered while there is a job to watch.
local _, BB = ...

local Kill = {}
BB.Kill = Kill

local C, Data, Comm, L = BB.Compat, BB.Data, BB.Comm, BB.L
local lower, format = string.lower, string.format

-- The flags of the combat log (the game's own constants when there are any)
local TYPE_PLAYER = _G.COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local OURS = { -- the killer is me, or in my party or raid
    _G.COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1, _G.COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2,
    _G.COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4,
}
local SAME_VICTIM = 5     -- seconds in which the same dead player is not counted twice

local frame = CreateFrame("Frame")
local registered = false
local targets = {}        -- lower-case short name -> true, for the jobs being hunted
local recent = {}         -- victim guid -> time

local function hasFlag(flags, flag)
    return type(flags) == "number" and flags % (flag * 2) >= flag
end

local function anyOf(flags, list)
    for _, flag in ipairs(list) do
        if hasFlag(flags, flag) then return true end
    end
    return false
end

-- What is hunted: the jobs the player took that are still going, and (unless switched off in the settings) every
-- open hunt of the guild, so a kill counts without having pressed Hunt first.
local function autoHunt()
    local s = BB.db and BB.db.settings
    return not s or s.autoHunt ~= false
end

local function jobs()
    local list = {}
    for _, b in pairs(Data.All()) do
        if b.type == "kos" and b.title and Data.IsActive(b) and not Data.IsMine(b) and C.Now() < b.deadline then
            local entry = Data.TakerEntry(b, Data.Me())
            if entry then
                if (entry.progress or 0) < b.quantity then list[#list + 1] = b end
            elseif autoHunt() then
                list[#list + 1] = b
            end
        end
    end
    return list
end

-- Watch the combat log only while a job needs it.
function Kill.Update()
    wipe(targets)
    for _, b in ipairs(jobs()) do
        local name = C.ShortName(b.title)
        if name then targets[lower(name)] = true end
    end
    local want = next(targets) ~= nil
    if want and not registered then
        frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        registered = true
    elseif not want and registered then
        frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        registered = false
    end
end

-- A kill of `name` was seen: count it for every job that hunts them.
function Kill.Counted(name, guid)
    local short = C.ShortName(name)
    if not short or not targets[lower(short)] then return end
    local now = GetTime and GetTime() or 0
    if guid and recent[guid] and now - recent[guid] < SAME_VICTIM then return end
    if guid then recent[guid] = now end
    for _, b in ipairs(jobs()) do
        if C.SameName(b.title, short) and C.Now() < b.deadline then
            if not Data.TakerEntry(b, Data.Me()) then
                -- a kill without Hunt pressed: the job is taken now, with this kill as its first
                local taken = Data.Take(b.id)
                if not taken then return end
                Comm.SendTake(b, taken)
                BB.Progress.Taken(b)
            end
            local entry, last = Data.AddKill(b)
            if entry then
                BB:Debug("kill of %s counted for %s: %d/%d", short, b.id, entry.progress, b.quantity)
                Comm.SendProgress(b, entry)
                BB:Fire("NOTIFY", {
                    title = last and L["HUNT DONE"] or L["KILL COUNTED"], good = last and true or false,
                    text = format(L["%s: %d of %d kills. %s"], short, entry.progress, b.quantity,
                        last and format(L["%s confirms it."], C.ShortName(b.creator)) or ""),
                })
            end
        end
    end
end

frame:SetScript("OnEvent", function()
    if not CombatLogGetCurrentEventInfo then return end
    local _, sub, _, _, _, sourceFlags, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()
    if sub ~= "PARTY_KILL" then return end
    if C.IsSecret(destName) or type(destName) ~= "string" then return end
    if not hasFlag(destFlags, TYPE_PLAYER) or not anyOf(sourceFlags, OURS) then return end
    BB:Call("kill", Kill.Counted, destName, destGUID)
end)

BB:On("BOUNTIES_CHANGED", Kill.Update)
BB:On("SETTINGS_CHANGED", function(key) if key == "autoHunt" then Kill.Update() end end)
BB:On("LOGIN", function() C.After(2, Kill.Update) end)
