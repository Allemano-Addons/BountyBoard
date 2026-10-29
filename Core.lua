-- Core: the addon table, events, the L table, SavedVariables, slash commands and the small helpers that differ
-- between game clients (TBC Classic today, WoW Forever later). A change for another client is a change in this file.
local addonName, BB = ...

BB.name = addonName
BB.PREFIX = "AllemanoBB" -- the addon message prefix (guild channel)

local floor, strlower, strmatch, format = math.floor, string.lower, string.match, string.format
local tinsert, tremove = table.insert, table.remove

-- Every text the player sees goes through L, so it can be translated later. A missing key is its own text.
local L = setmetatable({}, { __index = function(_, key) return key end })
BB.L = L

-- ---------------------------------------------------------------------------
-- Errors and debug output
-- ---------------------------------------------------------------------------
BB.errors = {}

-- Runs fn protected: an error is handed to the game's error handler (BugGrabber, BugSack) and kept, and the
-- other handlers of the same event still run.
function BB:Call(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        tinsert(self.errors, tostring(where) .. ": " .. tostring(err))
        if #self.errors > 20 then tremove(self.errors, 1) end
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler("AllemanoBountyBoard (" .. tostring(where) .. "): " .. tostring(err)) end
    end
    return ok
end

function BB:Print(text, ...)
    local msg = select("#", ...) > 0 and format(text, ...) or text
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd457e6Bounty Board|r " .. msg) end
end

-- /bb debug turns this on; nothing is printed otherwise.
function BB:Debug(text, ...)
    if not (self.db and self.db.settings.debug) then return end
    local msg = select("#", ...) > 0 and format(text, ...) or text
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff7c858fBB|r " .. msg) end
end

-- ---------------------------------------------------------------------------
-- Game events (one frame, several protected handlers per event) and the addon's own events
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

-- Returns false if the client does not know the event.
function BB:RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not pcall(frame.RegisterEvent, frame, event) then
            handlers[event] = nil
            return false
        end
    end
    tinsert(handlers[event], fn)
    return true
end

function BB:Dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do self:Call("event " .. event, list[i], ...) end
end
frame:SetScript("OnEvent", function(_, event, ...) BB:Dispatch(event, ...) end)

local listeners = {}

-- The addon's own events: BB:On("BOUNTIES_CHANGED", fn) and BB:Fire("BOUNTIES_CHANGED", ...).
function BB:On(name, fn)
    listeners[name] = listeners[name] or {}
    tinsert(listeners[name], fn)
end

function BB:Fire(name, ...)
    local list = listeners[name]
    if not list then return end
    for i = 1, #list do self:Call("callback " .. name, list[i], ...) end
end

-- ---------------------------------------------------------------------------
-- Compat: everything that can differ between clients lives here.
-- ---------------------------------------------------------------------------
local C = {}
BB.Compat = C

C.TRADE_SLOTS = 6 -- items a player can offer in one trade

function C.After(seconds, fn) C_Timer.After(seconds, fn) end

-- A repeating timer; returns an object with :Cancel().
function C.Ticker(seconds, fn) return C_Timer.NewTicker(seconds, fn) end

-- Server time in seconds: the same for every player, whatever their computer clock says.
function C.Now()
    if GetServerTime then return GetServerTime() end
    return os.time()
end

function C.IsSecret(value) return issecretvalue ~= nil and issecretvalue(value) end

-- "Name-Realm" and "Name" are the same player here (a guild is one realm). Other strings pass through.
function C.ShortName(name)
    if type(name) ~= "string" or C.IsSecret(name) then return nil end
    name = strmatch(name, "^%s*(.-)%s*$")
    if name == "" then return nil end
    return (strmatch(name, "^([^%-]+)%-") or name)
end

function C.SameName(a, b)
    a, b = C.ShortName(a), C.ShortName(b)
    return a ~= nil and b ~= nil and strlower(a) == strlower(b)
end

local playerName
-- The player's own name, as used in bounties.
function C.PlayerName()
    if not playerName and UnitName then playerName = C.ShortName((UnitName("player"))) end
    return playerName
end

function C.RealmName()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
end

-- The player's rank in the guild: 0 is the Guild Master, higher numbers are lower ranks (nil when unknown).
function C.GuildRank()
    if not (IsInGuild and IsInGuild()) or not GetGuildInfo then return nil end
    local _, _, index = GetGuildInfo("player")
    return tonumber(index)
end

function C.GuildName()
    if not (IsInGuild and IsInGuild()) then return nil end
    local name = GetGuildInfo and GetGuildInfo("player")
    if type(name) == "string" and name ~= "" then return name end
end

-- Classes: the token the game uses ("WARRIOR"), the player's own, and the guild's (from the roster).
local CLASS_TOKENS = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
    WARLOCK = true, DRUID = true, DEATHKNIGHT = true, MONK = true, DEMONHUNTER = true, EVOKER = true,
}

function C.IsClassToken(token) return type(token) == "string" and CLASS_TOKENS[token] == true end

function C.PlayerClass()
    local token = UnitClass and select(2, UnitClass("player"))
    if C.IsClassToken(token) then return token end
end

local rosterClass, rosterAt, rosterAsked = {}, -1000, -1000
-- The class of a guildmate from the guild roster (the game fills it a moment after login).
function C.GuildClass(name)
    local short = C.ShortName(name)
    if not short or not GetNumGuildMembers then return nil end
    local now = GetTime and GetTime() or 0
    if now - rosterAt > 60 then
        rosterAt = now
        wipe(rosterClass)
        for i = 1, GetNumGuildMembers() do
            local member, _, _, _, _, _, _, _, _, _, token = GetGuildRosterInfo(i)
            member = C.ShortName(member)
            if member and C.IsClassToken(token) then rosterClass[strlower(member)] = token end
        end
        if next(rosterClass) == nil and now - rosterAsked > 120 then
            rosterAsked = now
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
            elseif _G.GuildRoster then _G.GuildRoster() end
        end
    end
    return rosterClass[strlower(short)]
end

-- A name in its class colour (token known from the bounty, else from the roster, else plain).
function C.ClassColored(name, token)
    local short = C.ShortName(name) or "?"
    token = C.IsClassToken(token) and token or C.GuildClass(name)
    local color = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if not color then return short end
    local hex = color.colorStr and color.colorStr:sub(-6) or format("%02x%02x%02x", floor(color.r * 255 + 0.5), floor(color.g * 255 + 0.5), floor(color.b * 255 + 0.5))
    return "|cff" .. hex .. short .. "|r"
end

-- How many of an item are in the bags (the bank is not counted).
function C.ItemCount(itemID)
    return (GetItemCount and GetItemCount(itemID)) or 0
end

function C.ItemIDFromLink(link)
    if type(link) ~= "string" or C.IsSecret(link) then return nil end
    return tonumber(strmatch(link, "item:(%d+)"))
end

-- name, link, quality, icon of an item; the icon is known at once, the rest once the game has the item.
function C.ItemInfo(itemID)
    local name, link, quality, icon
    if GetItemInfo then
        local n, l, q, _, _, _, _, _, _, tex = GetItemInfo(itemID)
        name, link, quality, icon = n, l, q, tex
    end
    if not icon then
        local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
        if instant then
            local _, _, _, _, tex = instant(itemID)
            icon = tex
        end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return name, link, quality, icon
end

function C.QualityColor(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

-- Money as text with coin icons ("5g 20s"), from copper.
function C.CoinString(copper)
    copper = floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
    return table.concat(out, " ")
end

function C.GetPhysicalScreenSize()
    if GetPhysicalScreenSize then
        local w, h = GetPhysicalScreenSize()
        if w and h and h > 0 then return w, h end
    end
    return 1920, 1080
end

-- Addon messages (guild channel). Returns true when the game took the message.
function C.RegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(BB.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(BB.PREFIX)
    end
end

-- false: the game refused (throttled), so the caller sends it again later.
function C.SendGuildMessage(text)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not send then return true end
    local result = send(BB.PREFIX, text, "GUILD")
    if result == false then return false end
    local enum = _G.Enum and _G.Enum.SendAddonMessageResult
    if enum and type(result) == "number" and result == enum.AddonMessageThrottle then return false end
    return true
end

-- The player on the other side of an open trade.
function C.TradePartner()
    local name = UnitName and UnitName("NPC")
    if not name and TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
        name = TradeFrameRecipientNameText:GetText()
    end
    return C.ShortName(name)
end

function C.AddOnVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(addonName, "Version") or "?"
end

-- ---------------------------------------------------------------------------
-- SavedVariables: read at ADDON_LOADED, never at file load. Everything about bounties is kept per
-- realm and guild (db.guilds["Realm|Guild"]).
-- ---------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
    debug = false, accent = "D457E6", window = {},
    toasts = true, toastTaken = true, toastDelivery = true, toastPayment = true, soundChoice = "toast", typeColors = true,
    launcherShown = true, autoHunt = true, guildPostRank = 1, font = "barlow", textSize = "M", scale = 1, defaultTab = "board", lastTab = "board", historyDays = 30,
}

local function fill(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and {} or value
        end
        if type(value) == "table" and type(target[key]) == "table" then fill(target[key], value) end
    end
end

local function initDB()
    if type(AllemanoBountyBoardDB) ~= "table" then AllemanoBountyBoardDB = {} end
    local db = AllemanoBountyBoardDB
    db.schema = db.schema or 1
    db.settings = type(db.settings) == "table" and db.settings or {}
    db.guilds = type(db.guilds) == "table" and db.guilds or {}
    if db.settings.sound == false then db.settings.soundChoice = "none" end -- the old on/off switch
    db.settings.sound = nil
    -- the first builds were cyan, then silver, then another magenta; the accent is the brand library's magenta now
    if db.settings.accent == "3FD0E0" or db.settings.accent == "9AA0A8" or db.settings.accent == "E040A0" then db.settings.accent = nil end
    fill(db.settings, DEFAULT_SETTINGS)
    BB.db = db
end

-- The saved data of the player's guild, created when needed; nil while the player has no guild (or the game has
-- not told the name yet).
function BB.Guild()
    if not BB.db then return nil end
    local guild = C.GuildName()
    if not guild then return nil end
    local key = C.RealmName() .. "|" .. guild
    local bucket = BB.db.guilds[key]
    if not bucket then
        bucket = { name = guild, bounties = {}, stats = {}, counter = 0, lastSync = 0, cleared = {} }
        BB.db.guilds[key] = bucket
    end
    bucket.bounties = bucket.bounties or {}
    bucket.stats = bucket.stats or {}
    bucket.counter = bucket.counter or 0
    bucket.cleared = bucket.cleared or {}
    BB.guildKey = key
    return bucket
end

-- The guild name or the "no guild yet" state changed: windows redraw, the sync starts.
local lastGuildName
local function checkGuild()
    local name = C.GuildName()
    if name ~= lastGuildName then
        lastGuildName = name
        BB:Fire("GUILD_CHANGED", name)
    end
end

BB:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    initDB()
    BB.version = C.AddOnVersion()
    BB:Fire("DB_READY")
end)

BB:RegisterEvent("PLAYER_LOGIN", function()
    BB.ready = true
    C.RegisterPrefix()
    checkGuild()
    -- The guild name arrives a moment after login.
    C.After(3, checkGuild)
    C.After(10, checkGuild)
    BB:Fire("LOGIN")
end)
BB:RegisterEvent("PLAYER_GUILD_UPDATE", checkGuild)
BB:RegisterEvent("GUILD_ROSTER_UPDATE", checkGuild)

-- ---------------------------------------------------------------------------
-- Slash commands: /bb and /bounty
-- ---------------------------------------------------------------------------
local function help()
    BB:Print(L["/bb opens the board. /bb settings opens the settings. /bb button shows or hides the launcher button. /bb sync asks the guild for bounties again. /bb debug turns debug output on or off."])
end

SLASH_ALLEMANOBB1 = "/bb"
SLASH_ALLEMANOBB2 = "/bounty"
SlashCmdList["ALLEMANOBB"] = function(msg)
    local cmd = strlower(strmatch(msg or "", "^%s*(%S*)"))
    if cmd == "" then
        if BB.Main then BB.Main.Toggle() end
    elseif cmd == "debug" then
        if not BB.db then return end
        BB.db.settings.debug = not BB.db.settings.debug
        BB:Print(BB.db.settings.debug and L["Debug output is on."] or L["Debug output is off."])
    elseif cmd == "sync" then
        if BB.Comm then
            BB.Comm.SendManifest()
            BB:Print(L["Asked the guild for bounties."])
        end
    elseif cmd == "settings" or cmd == "options" then
        if BB.Settings then BB.Settings.Toggle() end
    elseif cmd == "button" or cmd == "minimap" then
        if BB.Launcher then BB.Launcher.Toggle() end
    elseif cmd == "errors" then
        BB:Print("%d errors", #BB.errors)
        for _, err in ipairs(BB.errors) do BB:Print("%s", err) end
    elseif cmd == "version" then
        BB:Print("v" .. tostring(BB.version))
    else
        help()
    end
end
