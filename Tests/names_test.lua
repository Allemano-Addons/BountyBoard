-- On WoW Forever a character has a first and a last name ("Ragnar Ironfist"): everything that carries a name has to
-- cope with the space (ids, the wire, takers, recipients, kill targets, trades).
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Anna Berg", { ui = true, money = 100000 })
    local bob = world:client("Bo Builder", { ui = true, money = 0 })
    local carl = world:client("Carl Jonsson", { ui = true, money = 1000000 })
    world:advance(20)
    local A, B, C = alice.BB, bob.BB, carl.BB
    local THORIUM = 12359

    local b = A.Data.Post({ itemID = THORIUM, quantity = 10, reward = 1000, days = 3 })
    T.check(b.id:find("^Anna_Berg%-"), "the id has no space: " .. b.id)
    T.equal(b.creator, "Anna Berg", "the creator keeps the full name")
    A.Comm.SendBounty(b, "high")
    world:advance(5)
    T.equal(B.Data.Get(b.id) and B.Data.Get(b.id).creator, "Anna Berg", "the name survives the wire")

    -- take, progress
    bob:SetBag(THORIUM, 4)
    local entry = B.Data.Take(b.id)
    B.Comm.SendTake(B.Data.Get(b.id), entry)
    world:advance(5)
    local onAlice = A.Data.Get(b.id)
    T.check(A.Data.TakerEntry(onAlice, "Bo Builder") ~= nil, "Anna sees Bo Builder as the taker")
    T.equal(A.Data.TakerEntry(onAlice, "Bo Builder").progress, 4, "with the count")
    bob:SetBag(THORIUM, 10)
    world:advance(10)
    T.equal(A.Data.TakerEntry(onAlice, "Bo Builder").progress, 10, "progress messages find the taker")

    -- a late joiner and a manifest
    local dora = world:client("Dora Dane", { ui = true })
    world:advance(60)
    local copy = dora.BB.Data.Get(b.id)
    T.check(copy and dora.BB.Data.TakerEntry(copy, "Bo Builder"), "a late joiner gets the bounty and its takers")

    -- the trade
    world:trade(alice, bob, { money = 1000 }, { items = { [THORIUM] = 10 } })
    world:advance(10)
    T.equal(onAlice.status, "paid", "a trade between two full names is verified")
    T.equal(B.Data.Get(b.id).status, "paid", "and seen by the taker")
    T.equal(A.Data.Completed("Bo Builder"), 1, "the completed job counts for the full name")

    -- forged names are still refused
    local text = table.concat({ "1", "T", "fake1", "1/1", A.Comm.Encode({ i = b.id, w = "Carl Jonsson", t = world.now, p = 1 }) }, "|")
    A.Comm.OnMessage("AllemanoBB", text, "GUILD", "Bo Builder-Realm")
    T.check(A.Data.TakerEntry(onAlice, "Carl Jonsson") == nil, "a take in somebody else's full name is refused")

    -- guild goal with a recipient, and a hunt with a target
    local goal = A.Data.Post({ type = "guild", itemID = THORIUM, quantity = 5, reward = 100, days = 3, recipient = "Carl Jonsson" })
    T.equal(goal.recipient, "Carl Jonsson", "a recipient with a first and a last name")
    A.Comm.SendBounty(goal, "high")
    world:advance(5)
    bob:SetBag(THORIUM, 5)
    world:trade(carl, bob, { money = 500 }, { items = { [THORIUM] = 5 } })
    world:advance(10)
    T.equal(C.Data.Get(goal.id).status, "paid", "the recipient verifies a goal")

    local hunt = A.Data.Post({ type = "kos", title = "Gor Ravenclaw", quantity = 1, reward = 0, days = 3 })
    A.Comm.SendBounty(hunt, "high")
    world:advance(5)
    local took = B.Data.Take(hunt.id)
    B.Comm.SendTake(B.Data.Get(hunt.id), took)
    world:advance(5)
    bob:Kill("Gor Ravenclaw")
    world:advance(5)
    T.equal(B.Data.TakerEntry(B.Data.Get(hunt.id), "Bo Builder").progress, 1, "a kill of a target with a full name counts")
    bob:Kill("Gor Ravenclaw-Realm")
    T.equal(B.Data.TakerEntry(B.Data.Get(hunt.id), "Bo Builder").progress, 1, "(and not more than wanted)")

    -- the dialog allows long names
    A.Main.Show()
    alice:FindButton("+ Post Bounty"):Click()
    T.check(A.PostDialog.Frame().recipient.maxLetters == nil or A.PostDialog.Frame().recipient.maxLetters >= 30, "the recipient box takes a full name")

    for _, c in ipairs({ alice, bob, carl, dora }) do T.clean(c, c.name .. " has no errors") end
end
