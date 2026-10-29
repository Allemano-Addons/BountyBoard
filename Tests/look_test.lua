-- Class colours of names, "completed 2 min ago" on finished cards, the magenta accent.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true, class = "WARRIOR" })
    local bob = world:client("Bob", { ui = true })
    world:advance(20)
    local A, B = alice.BB, bob.BB

    T.equal(A.db.settings.accent, "D457E6", "the accent is magenta")
    local r, g, b = A.Theme:Accent()
    T.check(math.abs(r - 0xD4 / 255) < 0.01 and math.abs(g - 0x57 / 255) < 0.01 and math.abs(b - 0xE6 / 255) < 0.01, "and Theme gives magenta")
    local hr, hg, hb = A.Theme:AccentHover()
    T.check(hr > r and hg > g and hb > b, "hover is lighter")
    local pr, pg, pb = A.Theme:AccentPressed()
    T.check(pr < r and pg < g and pb < b, "pressed is darker")

    -- the creator's class travels with the bounty
    local bounty = A.Data.Post({ itemID = 12359, quantity = 5, reward = 100, days = 1, note = "" })
    T.equal(bounty.class, "WARRIOR", "a bounty carries the class of its creator")
    A.Comm.SendBounty(bounty, "high")
    world:advance(5)
    T.equal(B.Data.Get(bounty.id).class, "WARRIOR", "Bob gets it")
    local bad = A.Data.ToWire(bounty)
    bad.cl = "NOTACLASS"
    T.check(B.Data.FromWire(bad).class == nil, "an unknown class is dropped")

    bob:Slash("")
    world:advance(0.5)
    local colored = false
    for _, text in ipairs(bob:Texts()) do
        if text:find("|cffc69b6dAlice|r", 1, true) then colored = true end
    end
    T.check(colored, "the creator's name is in the class colour on the card")

    -- a name without a known class falls back to the guild roster
    T.equal(B.Compat.ClassColored("Alice-Realm"), "|cffc69b6dAlice|r", "the roster knows Alice's class")
    T.equal(B.Compat.ClassColored("Nobody"), "Nobody", "an unknown player stays plain")

    -- finished cards say what happened and when it ended
    local entry = B.Data.Take(bounty.id)
    B.Comm.SendTake(B.Data.Get(bounty.id), entry)
    world:advance(5)
    A.Data.Cancel(bounty.id)
    A.Comm.SendCancel(bounty)
    local endedAt = bounty.finishedAt
    world:advance(300)
    bob:FindButton("History"):Click()
    world:advance(1)
    local said = false
    for _, text in ipairs(bob:Texts()) do
        if text:find("cancelled 5 min ago", 1, true) then said = true end
    end
    T.check(said, "a cancelled card says 'cancelled 5 min ago'")
    T.check(not bob:HasText("updated"), "and shows no stale progress age")

    -- the finish time is the creator's, also for somebody who hears of it late
    local late = world:client("Late", { ui = true })
    world:advance(60)
    local copy = late.BB.Data.Get(bounty.id)
    T.check(copy ~= nil, "a late joiner gets the finished bounty")
    T.equal(copy and copy.finishedAt, endedAt, "with the time the creator finished it, not the time it arrived")

    for _, c in ipairs({ alice, bob, late }) do T.clean(c, c.name .. " has no errors") end
end
