-- Several clients in one guild: a bounty is posted, taken, cancelled; a late joiner and a player who missed messages
-- catch up; forged messages are refused; two guilds stay apart.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice")
    local bob = world:client("Bob")
    local carl = world:client("Carl")
    world:advance(20) -- the logins settle

    local function post(c, extra)
        local o = { itemID = 12359, quantity = 20, reward = 50000, days = 3, note = "" }
        for k, v in pairs(extra or {}) do o[k] = v end
        local b = c.BB.Data.Post(o)
        c.BB.Comm.SendBounty(b, "high")
        return b
    end

    -- a new bounty reaches everybody
    local b = post(alice)
    world:advance(5)
    for _, c in ipairs({ bob, carl }) do
        local copy = c.BB.Data.Get(b.id)
        T.check(copy ~= nil, c.name .. " sees the new bounty")
        T.equal(copy and copy.reward, 50000, c.name .. " sees the reward")
        T.equal(copy and copy.status, "open", c.name .. " sees it open")
    end

    -- Bob takes it: Alice is told, everybody sees Bob as a taker
    local tookEvents = {}
    alice.BB:On("BOUNTY_TAKEN", function(bounty, who) tookEvents[#tookEvents + 1] = who end)
    bob:SetBag(12359, 7)
    local entry = bob.BB.Data.Take(b.id)
    bob.BB.Comm.SendTake(bob.BB.Data.Get(b.id), entry)
    world:advance(5)
    local onAlice = alice.BB.Data.Get(b.id)
    T.check(alice.BB.Data.TakerEntry(onAlice, "Bob") ~= nil, "Alice sees Bob as a taker")
    T.equal(onAlice.status, "taken", "the bounty is taken on Alice's side")
    T.equal(alice.BB.Data.TakerEntry(onAlice, "Bob").progress, 7, "the take carries Bob's count")
    T.equal(tookEvents[1], "Bob", "Alice is told that Bob took it")
    T.check(carl.BB.Data.TakerEntry(carl.BB.Data.Get(b.id), "Bob") ~= nil, "Carl sees Bob as a taker")

    -- a forged take (the sender is not the player it names) is refused
    local text = table.concat({ "1", "T", "fake1", "1/1", carl.BB.Comm.Encode({ i = b.id, w = "Dora", t = world.now, p = 99 }) }, "|")
    alice.BB.Comm.OnMessage("AllemanoBB", text, "GUILD", "Bob-Realm")
    T.check(alice.BB.Data.TakerEntry(onAlice, "Dora") == nil, "a take in somebody else's name is refused")

    -- a forged cancel (not the creator) is refused
    text = table.concat({ "1", "C", "fake2", "1/1", carl.BB.Comm.Encode({ i = b.id, v = onAlice.version + 1 }) }, "|")
    alice.BB.Comm.OnMessage("AllemanoBB", text, "GUILD", "Bob-Realm")
    T.equal(onAlice.status, "taken", "a cancel from somebody else changes nothing")

    -- a forged bounty update from somebody else is refused
    local forged = alice.BB.Data.ToWire(onAlice)
    forged.v = onAlice.version + 5
    forged.r = 1
    forged.c = "Bob" -- claims another creator for the same id
    text = table.concat({ "1", "U", "fake3", "1/1", carl.BB.Comm.Encode(forged) }, "|")
    alice.BB.Comm.OnMessage("AllemanoBB", text, "GUILD", "Bob-Realm")
    T.equal(onAlice.reward, 50000, "a bounty cannot be taken over by a new creator")

    -- the creator cancels: everybody follows
    alice.BB.Data.Cancel(b.id)
    alice.BB.Comm.SendCancel(onAlice)
    world:advance(5)
    T.equal(bob.BB.Data.Get(b.id).status, "cancelled", "Bob sees the cancel")
    T.equal(carl.BB.Data.Get(b.id).status, "cancelled", "Carl sees the cancel")

    -- a late joiner gets what is open
    local b2 = post(alice, { itemID = 2772, quantity = 40, reward = 1000 })
    local b3 = post(bob, { itemID = 13468, quantity = 1, reward = 1000000 })
    world:advance(10)
    local dora = world:client("Dora")
    world:advance(60)
    T.check(dora.BB.Data.Get(b2.id) ~= nil, "a late joiner gets Alice's bounty")
    T.check(dora.BB.Data.Get(b3.id) ~= nil, "a late joiner gets Bob's bounty")
    T.equal(dora.BB.Data.Get(b3.id) and dora.BB.Data.Get(b3.id).reward, 1000000, "and the details are right")
    T.check(dora.BB.Comm.SyncAge() ~= nil, "the late joiner knows when it last heard from the guild")

    -- somebody who missed a message (dropped on the way) is repaired by the manifest
    alice.dropTo = { Carl = true }
    local b4 = post(alice, { itemID = 2772, quantity = 3, reward = 5 })
    world:advance(5)
    alice.dropTo = nil
    T.check(carl.BB.Data.Get(b4.id) == nil, "Carl missed the bounty (the message was lost)")
    world:advance(700) -- a manifest goes out within ten minutes
    T.check(carl.BB.Data.Get(b4.id) ~= nil, "the manifest repairs the gap")

    -- a changed bounty (new version) also repairs
    local old = bob.BB.Data.Get(b2.id)
    T.equal(old.version, 1, "Bob has version 1")
    alice.dropTo = { Bob = true }
    b2.version = b2.version + 1
    b2.note = "now with a note"
    alice.BB.Comm.SendBounty(b2, "high")
    world:advance(5)
    alice.dropTo = nil
    T.equal(bob.BB.Data.Get(b2.id).note, "", "Bob missed the update")
    world:advance(700)
    T.equal(bob.BB.Data.Get(b2.id).note, "now with a note", "the manifest brings the newer version")

    -- the creator is offline: a guildmate passes the bounty on
    alice.offline = true
    local erin = world:client("Erin")
    world:advance(60)
    T.check(erin.BB.Data.Get(b2.id) ~= nil, "a bounty is passed on while its creator is offline")
    alice.offline = false

    -- a guild of its own: nothing leaks between guilds
    local other = world:client("Zed", { guild = "Other Guild" })
    world:advance(60)
    T.check(other.BB.Data.Get(b2.id) == nil, "another guild does not see our bounties")
    local zb = other.BB.Data.Post({ itemID = 2772, quantity = 1, reward = 1, days = 1, note = "" })
    other.BB.Comm.SendBounty(zb, "high")
    world:advance(30)
    T.check(alice.BB.Data.Get(zb.id) == nil, "we do not see theirs")

    -- the same player on two realms' guilds keeps separate data
    local keys = 0
    for _ in pairs(alice.BB.db.guilds) do keys = keys + 1 end
    T.equal(keys, 1, "the data is kept per guild")

    for _, c in ipairs(world.clients) do T.clean(c, c.name .. " has no errors") end
end
