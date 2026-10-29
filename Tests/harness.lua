-- A fake game for the offline tests: a world with a clock and timers, a guild channel that carries addon messages
-- between several clients, bags, money, a trade window and enough of the frame API to build the windows.
-- Every client has its own set of globals (an environment), so two players can run the addon side by side.
-- Lua 5.4 (and 5.1) compatible.
local H = {}

local ITEMS = {
    [2772] = { name = "Iron Ore", quality = 1 },
    [12359] = { name = "Thorium Bar", quality = 2 },
    [13468] = { name = "Black Lotus", quality = 4 },
}
H.ITEMS = ITEMS

local function itemLink(id)
    local item = ITEMS[id]
    return "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[" .. (item and item.name or "?") .. "]|h|r"
end
H.itemLink = itemLink

-- ---------------------------------------------------------------------------
-- The world: time, timers, the guild channel
-- ---------------------------------------------------------------------------
function H.newWorld()
    local w = { now = 1000000, timers = {}, clients = {}, seq = 0, sent = 0, oversize = 0, log = {} }

    function w:schedule(seconds, fn, interval)
        self.seq = self.seq + 1
        local t = { at = self.now + seconds, fn = fn, interval = interval, seq = self.seq }
        self.timers[#self.timers + 1] = t
        return t
    end

    -- Runs everything that is due within `seconds`, in time order.
    function w:advance(seconds)
        local target = self.now + seconds
        local guard = 0
        while true do
            local best
            for _, t in ipairs(self.timers) do
                if not t.cancelled and t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
                    best = t
                end
            end
            if not best then break end
            guard = guard + 1
            assert(guard < 200000, "timers do not stop")
            if best.at > self.now then self.now = best.at end
            if best.interval then
                best.at = best.at + best.interval
            else
                best.cancelled = true
            end
            best.fn()
        end
        self.now = target
        local live = {}
        for _, t in ipairs(self.timers) do if not t.cancelled then live[#live + 1] = t end end
        self.timers = live
    end

    -- A guild message goes to every member (the sender too, as in the game) a moment later.
    function w:deliver(from, prefix, text, channel)
        if channel ~= "GUILD" then return false end
        if #text > 255 then
            self.oversize = self.oversize + 1
            return false
        end
        if from.offline then return true end
        self.sent = self.sent + 1
        for _, to in ipairs(self.clients) do
            if to.guild == from.guild and not to.offline and not (from.dropTo and from.dropTo[to.name]) then
                self:schedule(0.05, function() to:Event("CHAT_MSG_ADDON", prefix, text, "GUILD", from.name .. "-Realm") end)
            end
        end
        return true
    end

    function w:client(name, opts)
        local c = H.newClient(self, name, opts or {})
        self.clients[#self.clients + 1] = c
        return c
    end

    -- Both players open a trade, put things in it, accept, and the trade completes.
    -- gives = { items = { [id] = n }, money = copper } for each side.
    function w:trade(a, b, aGives, bGives, opts)
        opts = opts or {}
        a:OpenTrade(b.name, aGives, bGives)
        b:OpenTrade(a.name, bGives, aGives)
        a:Event("TRADE_ACCEPT_UPDATE", 1, 0)
        b:Event("TRADE_ACCEPT_UPDATE", 0, 1)
        if not opts.noFinalAccept then -- the real game often does not send the last update
            a:Event("TRADE_ACCEPT_UPDATE", 1, 1)
            b:Event("TRADE_ACCEPT_UPDATE", 1, 1)
        end
        if opts.cancel then
            a:CloseTrade()
            b:CloseTrade()
            return
        end
        a:FinishTrade(aGives, bGives)
        b:FinishTrade(bGives, aGives)
    end

    return w
end

-- ---------------------------------------------------------------------------
-- Frames: remembers what the addon did to them, so the tests can look at it
-- ---------------------------------------------------------------------------
local Frame = {}
Frame.__index = function(_, key)
    local method = Frame[key]
    if method ~= nil then return method end
    -- every other method does nothing; a field that was never set is nil, as on a real frame
    if type(key) == "string" and key:find("^%u") then return function() end end
end

local function newFrame(client, kind, parent, name)
    local f = setmetatable({
        kind = kind, parent = parent or false, client = client, name = name or false, shown = true, scripts = {},
        hooks = {}, children = {}, points = 0, text = "", alpha = 1, events = {}, w = false, h = false, layer = false,
        scroll = false, color = false,
    }, Frame)
    client.frames[#client.frames + 1] = f
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    if name then client.env[name] = f end
    return f
end

function Frame:CreateTexture(_, layer) local t = newFrame(self.client, "Texture", self) t.layer = layer return t end
function Frame:CreateFontString(_, layer) local t = newFrame(self.client, "FontString", self) t.layer = layer return t end
function Frame:CreateLine() return newFrame(self.client, "Line", self) end
function Frame:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Frame:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale or 1 end
function Frame:GetParent() return self.parent or nil end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(on) self.shown = on and true or false end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
    if not self.shown then return false end
    if self.parent and self.parent.IsVisible then return self.parent:IsVisible() end
    return true
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth()
    if self.w then return self.w end
    if self.parent and self.parent.GetWidth then return self.parent:GetWidth() end
    return 1920
end
function Frame:GetHeight()
    if self.h then return self.h end
    if self.parent and self.parent.GetHeight then return self.parent:GetHeight() end
    return 1080
end
function Frame:GetSize() return self:GetWidth(), self:GetHeight() end
function Frame:SetPoint() self.points = self.points + 1 end
function Frame:ClearAllPoints() self.points = 0 end
function Frame:GetNumPoints() return self.points end
function Frame:GetPoint() return "CENTER", self.parent, "CENTER", 0, 0 end
function Frame:SetAllPoints() self.points = 1 end
function Frame:GetLeft() return 100 end
function Frame:GetBottom() return 300 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameLevel() return 1 end
function Frame:GetDrawLayer() return self.layer or "ARTWORK", 0 end
function Frame:GetAlpha() return self.alpha end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
end
function Frame:RunScript(name, ...)
    local fn = self.scripts[name]
    if fn then fn(self, ...) end
    for _, hook in ipairs(self.hooks[name] or {}) do hook(self, ...) end
end
function Frame:RegisterEvent(event)
    if self.client.unknownEvents[event] then error("unknown event " .. event) end
    self.events[event] = true
end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:SetText(text)
    self.text = text == nil and "" or tostring(text)
    if self.kind == "EditBox" then self:RunScript("OnTextChanged", false) end
end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #self.text * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetFont() return true end
function Frame:GetFont() return "" end
function Frame:HasFocus() return false end
function Frame:IsMouseOver() return false end
function Frame:SetTexture() end
function Frame:GetNumChildren() return #self.children end
function Frame:SetVerticalScroll(v) self.scroll = v end
function Frame:GetVerticalScroll() return self.scroll or 0 end
function Frame:IsObjectType(kind) return self.kind == kind end

-- Test helpers
function Frame:Click(button)
    assert(self:IsVisible(), "clicked a button that is not visible")
    self:RunScript("OnClick", button or "LeftButton")
end
function Frame:Type(text) -- as if the player typed into an edit box
    self.text = tostring(text)
    self:RunScript("OnTextChanged", true)
end

-- ---------------------------------------------------------------------------
-- One player's game
-- ---------------------------------------------------------------------------
local TOC_FILES

local function readToc()
    if TOC_FILES then return TOC_FILES end
    TOC_FILES = {}
    local f = assert(io.open("AllemanoBountyBoard.toc", "rb"))
    for line in f:lines() do
        line = line:gsub("\r", "")
        if line ~= "" and not line:find("^##") then TOC_FILES[#TOC_FILES + 1] = (line:gsub("\\", "/")) end
    end
    f:close()
    return TOC_FILES
end

local function loadFile(path, env)
    if setfenv then
        local fn = assert(loadfile(path))
        setfenv(fn, env)
        return fn
    end
    return assert(loadfile(path, "t", env))
end

-- opts: guild (default "Slakthuset"), ui (load the windows too), money, noLogin
function H.newClient(world, name, opts)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.unpack = unpack or table.unpack -- Lua 5.1 has it as a global, as the game does
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    local c = {
        world = world, name = name, env = env, frames = {}, bags = {}, money = opts.money or 100000, errors = {},
        guild = opts.guild == nil and "Slakthuset" or opts.guild or nil, prefixes = {}, unknownEvents = {},
        chat = {}, trade = nil, errorsSeen = {},
    }

    -- time and timers
    env.GetServerTime = function() return math.floor(world.now) end
    env.GetTime = function() return world.now end
    env.C_Timer = {
        After = function(s, fn) world:schedule(s, fn) end,
        NewTicker = function(s, fn)
            local t = world:schedule(s, fn, s)
            return { Cancel = function() t.cancelled = true end }
        end,
    }

    -- the player
    env.UnitName = function(unit)
        if unit == "player" then return name end
        if unit == "NPC" and c.trade then return c.trade.partner end
    end
    env.GetRealmName = function() return "Realm" end
    env.GetNormalizedRealmName = function() return "Realm" end
    env.IsInGuild = function() return c.guild ~= nil end
    c.rankIndex = opts.rank or 0
    env.GetGuildInfo = function() return c.guild, "Rank", c.rankIndex end
    env.GetItemCount = function(id) return c.bags[id] or 0 end
    env.GetMoney = function() return c.money end
    env.GetItemInfo = function(id)
        local item = ITEMS[id]
        if not item then return nil end
        return item.name, itemLink(id), item.quality, 1, 1, "Trade Goods", "", 20, "", "Interface\\Icons\\INV_Misc_Bag_" .. id
    end
    env.ITEM_QUALITY_COLORS = {
        [0] = { r = 0.6, g = 0.6, b = 0.6 }, [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.1, g = 1, b = 0 },
        [3] = { r = 0, g = 0.4, b = 1 }, [4] = { r = 0.6, g = 0.2, b = 0.9 }, [5] = { r = 1, g = 0.5, b = 0 },
    }
    env.LibStub = function(name) if name == "LibSharedMedia-3.0" then return c.lsm end end
    env.ERR_TRADE_COMPLETE = "Trade complete."
    c.class = opts.class or "MAGE"
    env.UnitClass = function() return c.class:sub(1, 1) .. c.class:sub(2):lower(), c.class end
    env.RAID_CLASS_COLORS = {
        MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc69b6d" },
    }
    local function roster()
        local list = {}
        for _, other in ipairs(world.clients) do
            if other.guild == c.guild then list[#list + 1] = other end
        end
        return list
    end
    env.COMBATLOG_OBJECT_TYPE_PLAYER, env.COMBATLOG_OBJECT_AFFILIATION_MINE = 0x400, 0x1
    env.COMBATLOG_OBJECT_AFFILIATION_PARTY, env.COMBATLOG_OBJECT_AFFILIATION_RAID = 0x2, 0x4
    env.CombatLogGetCurrentEventInfo = function() return (table.unpack or unpack)(c.combatEvent or {}) end
    env.GetNumGuildMembers = function() return #roster() end
    env.GetGuildRosterInfo = function(i)
        local other = roster()[i]
        if other then return other.name .. "-Realm", "", 0, 60, "", "", "", "", true, 0, other.class end
    end
    env.GetCoinTextureString = function(copper)
        return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
    end

    -- the guild channel
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix) c.prefixes[prefix] = true end,
        SendAddonMessage = function(prefix, text, channel) return world:deliver(c, prefix, text, channel) end,
    }

    -- chat: the shift-click path of the post dialog
    env.ChatEdit_GetActiveWindow = function() return c.chatBox end
    env.ChatEdit_InsertLink = function() return false end
    env.hooksecurefunc = function(a, b, fn)
        local target, key, hook = env, a, b
        if type(a) == "table" then target, key, hook = a, b, fn end
        local original = target[key]
        target[key] = function(...)
            local result = original and original(...)
            hook(...)
            return result
        end
    end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) c.chat[#c.chat + 1] = msg end }
    env.geterrorhandler = function() return function(err) c.errors[#c.errors + 1] = tostring(err) end end
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end, SetHyperlink = function() end, Show = function() end, Hide = function() end }
    env.GetCursorInfo = function()
        if c.cursor then return "item", c.cursor, itemLink(c.cursor) end
    end
    env.ClearCursor = function() c.cursor = nil end
    env.GetCursorPosition = function() return 0, 0 end
    env.IsMouseButtonDown = function() return false end

    -- frames
    env.UIParent = newFrame(c, "Frame", nil)
    env.UIParent.w, env.UIParent.h = 1920, 1080
    env.CreateFrame = function(kind, frameName, parent)
        return newFrame(c, kind, parent or env.UIParent, frameName)
    end

    -- the trade window (what each side offers)
    local function side(which)
        return c.trade and c.trade[which] or { items = {}, money = 0 }
    end
    local function slotItem(which, slot)
        local ids = {}
        for id in pairs(side(which).items) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids[slot]
    end
    env.GetTradePlayerItemInfo = function(slot)
        local id = slotItem("mine", slot)
        if id then return ITEMS[id] and ITEMS[id].name, "", side("mine").items[id] end
    end
    env.GetTradePlayerItemLink = function(slot)
        local id = slotItem("mine", slot)
        return id and itemLink(id) or nil
    end
    env.GetTradeTargetItemInfo = function(slot)
        local id = slotItem("theirs", slot)
        if id then return ITEMS[id] and ITEMS[id].name, "", side("theirs").items[id] end
    end
    env.GetTradeTargetItemLink = function(slot)
        local id = slotItem("theirs", slot)
        return id and itemLink(id) or nil
    end
    env.GetPlayerTradeMoney = function() return side("mine").money end
    env.GetTargetTradeMoney = function() return side("theirs").money end

    -- Events reach the frames that registered for them.
    function c:Event(event, ...)
        for _, f in ipairs(self.frames) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end

    function c:OpenTrade(partner, gives, gets)
        self.trade = {
            partner = partner,
            mine = { items = gives.items or {}, money = gives.money or 0 },
            theirs = { items = gets.items or {}, money = gets.money or 0 },
        }
        self:Event("TRADE_SHOW")
        self:Event("TRADE_PLAYER_ITEM_CHANGED")
        self:Event("TRADE_TARGET_ITEM_CHANGED")
        self:Event("TRADE_MONEY_CHANGED")
    end

    function c:CloseTrade()
        self:Event("TRADE_CLOSED")
        self.trade = nil
    end

    -- The trade went through: items and gold change hands, the window closes, the game says so.
    function c:FinishTrade(gives, gets)
        for id, n in pairs(gives.items or {}) do self.bags[id] = (self.bags[id] or 0) - n end
        for id, n in pairs(gets.items or {}) do self.bags[id] = (self.bags[id] or 0) + n end
        self.money = self.money - (gives.money or 0) + (gets.money or 0)
        self.trade = nil
        self:Event("TRADE_CLOSED")
        self:Event("TRADE_CLOSED") -- the game sends it twice
        self:Event("UI_INFO_MESSAGE", 0, "Trade complete.")
        self:Event("BAG_UPDATE", 0)
        self:Event("BAG_UPDATE_DELAYED")
    end

    -- The player (or somebody in the group) kills a player: a PARTY_KILL in the combat log.
    local killCount = 0
    function c:Kill(victim, opts)
        opts = opts or {}
        killCount = killCount + 1
        self.combatEvent = {
            world.now, "PARTY_KILL", false, "Player-1-" .. name, name, opts.sourceFlags or 0x511, 0,
            "Player-1-" .. victim .. killCount, victim, opts.destFlags or 0x548, 0,
        }
        self:Event("COMBAT_LOG_EVENT_UNFILTERED")
    end

    -- Give the player items (or take them) and tell the addon.
    function c:SetBag(id, n)
        self.bags[id] = n
        self:Event("BAG_UPDATE", 0)
        self:Event("BAG_UPDATE_DELAYED")
    end

    -- The first button (or other frame) with this text that is on screen.
    function c:FindButton(text)
        for _, f in ipairs(self.frames) do
            if f.kind == "FontString" and f.text == text and f.parent and f.parent.kind == "Button" and f:IsVisible() then
                return f.parent
            end
        end
    end
    function c:Texts()
        local out = {}
        for _, f in ipairs(self.frames) do
            if f.kind == "FontString" and f.text ~= "" and f:IsVisible() then out[#out + 1] = f.text end
        end
        return out
    end
    function c:HasText(needle)
        for _, t in ipairs(self:Texts()) do if t:find(needle, 1, true) then return true end end
        return false
    end

    function c:Slash(msg) return env.SlashCmdList.ALLEMANOBB(msg) end

    -- Load the addon in the order of the TOC.
    local BB = {}
    c.BB = BB
    for _, path in ipairs(readToc()) do
        if opts.ui or not path:find("^UI/") then
            loadFile(path, env)("AllemanoBountyBoard", BB)
        end
    end
    if not opts.noLogin then
        c:Event("ADDON_LOADED", "AllemanoBountyBoard")
        c:Event("PLAYER_LOGIN")
    end
    return c
end

-- ---------------------------------------------------------------------------
-- A tiny check runner
-- ---------------------------------------------------------------------------
function H.newT(name)
    local T = { name = name, ok = 0, bad = 0 }
    function T.check(ok, what)
        if ok then T.ok = T.ok + 1 else T.bad = T.bad + 1 print("FAIL " .. name .. ": " .. what) end
    end
    function T.equal(a, b, what)
        T.check(a == b, what .. " (got " .. tostring(a) .. ", wanted " .. tostring(b) .. ")")
    end
    -- No Lua error was caught by the addon's protected calls.
    function T.clean(client, what)
        T.check(#client.errors == 0 and #client.BB.errors == 0,
            (what or "no errors") .. (client.errors[1] and (": " .. client.errors[1]) or ""))
    end
    return T
end

return H
