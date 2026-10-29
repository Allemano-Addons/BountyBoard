-- Kill on Sight: a target and a number of kills; the hunter's client counts PARTY_KILLs of that player, the creator
-- confirms and pays by trade.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    local bob = world:client("Bob", { ui = true })
    world:advance(20)
    local A, B = alice.BB, bob.BB

    local function watching(c)
        for _, f in ipairs(c.frames) do
            if f.events.COMBAT_LOG_EVENT_UNFILTERED then return true end
        end
        return false
    end

    -- the rules
    local _, err = A.Data.Post({ type = "kos", title = "", quantity = 2, reward = 0, days = 1 })
    T.check(err ~= nil, "a hunt needs a target: " .. tostring(err))
    _, err = A.Data.Post({ type = "kos", title = "Gankarn", quantity = 0, reward = 0, days = 1 })
    T.check(err ~= nil, "and at least one kill")
    _, err = A.Data.Post({ type = "kos", title = "Gankarn", quantity = 51, reward = 0, days = 1 })
    T.check(err ~= nil, "and at most 50")
    local b = A.Data.Post({ type = "kos", title = "Gankarn-Pyrewood", quantity = 2, reward = 1000, days = 3, note = "ganked me twice" })
    T.check(b ~= nil, "a hunt is posted")
    T.equal(b.itemID, 0, "no item")
    T.equal(A.Data.ItemName(b), "Kill Gankarn-Pyrewood", "its name says what to do")
    local wire = A.Data.ToWire(b)
    local copy = B.Data.FromWire(wire)
    T.check(copy and copy.title == "Gankarn-Pyrewood" and copy.quantity == 2, "it survives the wire")
    wire.q = "0"
    T.check(B.Data.FromWire(wire) == nil, "zero kills does not parse")
    A.Comm.SendBounty(b, "high")
    world:advance(5)

    -- the card
    bob:Slash("")
    world:advance(0.5)
    T.check(bob:HasText("Kill Gankarn-Pyrewood") and bob:HasText("KILL"), "the card has the target and a KILL tag")
    T.check(bob:HasText("Hunt"), "and a Hunt button")
    B.Settings.Set("autoHunt", false)
    T.check(not watching(bob), "the combat log is not watched without a job (automatic counting off)")
    bob:FindButton("Hunt"):Click()
    world:advance(5)
    T.check(watching(bob), "it is watched once a hunt is taken")
    T.equal(A.Data.Get(b.id).status, "taken", "Alice sees it taken")

    -- kills
    bob:Kill("Somebodyelse")
    T.equal(B.Data.TakerEntry(B.Data.Get(b.id), "Bob").progress, 0, "another player's death is not counted")
    bob:Kill("Gankarn", { sourceFlags = 0x548 })
    T.equal(B.Data.TakerEntry(B.Data.Get(b.id), "Bob").progress, 0, "a kill by a stranger is not counted")
    bob:Kill("Gankarn", { destFlags = 0x2148 })
    T.equal(B.Data.TakerEntry(B.Data.Get(b.id), "Bob").progress, 0, "a creature of that name is not counted")
    bob:Kill("Gankarn-Pyrewood")
    world:advance(5)
    T.equal(B.Data.TakerEntry(B.Data.Get(b.id), "Bob").progress, 1, "a kill of the target is counted (with realm in the name)")
    T.equal(A.Data.TakerEntry(A.Data.Get(b.id), "Bob").progress, 1, "Alice sees 1 of 2")
    A.Main.Show()
    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    T.check(alice:HasText("|r  1/2 kills"), "the card shows the kills")
    local told = false
    alice.BB:On("HELP_DONE", function() told = true end)
    bob:Kill("Gankarn", { sourceFlags = 0x512 }) -- a group member's kill
    world:advance(5)
    T.equal(B.Data.TakerEntry(B.Data.Get(b.id), "Bob").progress, 2, "a kill by a group member counts")
    T.check(told, "Alice is told when the last kill is made")
    T.check(not watching(bob), "the combat log is let go when the hunt is done")
    bob:Kill("Gankarn")
    T.equal(B.Data.TakerEntry(B.Data.Get(b.id), "Bob").progress, 2, "more kills than wanted are not counted")

    -- confirm and pay
    T.check(alice:HasText("Confirm kills"), "Alice can confirm the kills")
    alice:FindButton("Confirm kills"):Click()
    alice:FindButton("Sure?"):Click()
    world:advance(5)
    T.equal(A.Data.Get(b.id).status, "delivered", "confirmed, gold missing")
    alice.money = 5000
    world:trade(alice, bob, { money = 1000 }, {})
    world:advance(10)
    T.equal(A.Data.Get(b.id).status, "paid", "the trade pays it")
    T.equal(B.Data.Get(b.id).status, "paid", "Bob sees it complete")

    -- giving it up lets go of the combat log
    local again = A.Data.Post({ type = "kos", title = "Gankarn", quantity = 1, reward = 0, days = 1 })
    A.Comm.SendBounty(again, "high")
    world:advance(5)
    local entry = B.Data.Take(again.id)
    B.Comm.SendTake(B.Data.Get(again.id), entry)
    T.check(watching(bob), "watching again for the second hunt")
    local gone = B.Data.Abandon(again.id)
    T.check(gone ~= nil and not watching(bob), "abandoning stops the watch")

    -- automatic counting: a kill without Hunt pressed takes the job and counts
    B.Settings.Set("autoHunt", true)
    local open = A.Data.Post({ type = "kos", title = "Sneakyone", quantity = 1, reward = 300, days = 1 })
    A.Comm.SendBounty(open, "high")
    world:advance(5)
    T.check(watching(bob), "an open hunt of the guild is watched")
    T.check(B.Data.TakerEntry(B.Data.Get(open.id), "Bob") == nil, "Bob has not taken it")
    bob:Kill("Sneakyone")
    world:advance(5)
    local auto = B.Data.TakerEntry(B.Data.Get(open.id), "Bob")
    T.check(auto and auto.progress == 1, "the kill took the job and counted")
    T.check(A.Data.TakerEntry(A.Data.Get(open.id), "Bob") ~= nil, "Alice sees Bob as the hunter")
    T.check(A.Data.Get(open.id).status == "taken", "and the bounty as taken")
    -- never for your own hunts
    alice:Kill("Wolfmanx")
    local mine = A.Data.Post({ type = "kos", title = "Wolfmanx", quantity = 1, reward = 0, days = 1 })
    alice:Kill("Wolfmanx")
    T.check(A.Data.TakerEntry(mine, "Alice") == nil, "a creator's own kill of the target does not count")

    -- the dialog
    A.Main.Show()
    alice:FindButton("+ Post Bounty"):Click()
    local dialog = A.PostDialog.Frame()
    dialog.typeBox:Set("kos")
    dialog.typeBox.scripts.OnClick(dialog.typeBox, "LeftButton")
    for _, fr in ipairs(alice.frames) do
        if fr.kind == "Button" and fr.item and fr.item.text == "Kill on Sight" and fr:IsVisible() then fr:Click() end
    end
    T.check(dialog.titleBox:IsShown() and not dialog.slot:IsShown() and dialog.qty:IsShown(), "the dialog asks for a player and a number")
    T.check(alice:HasText("Kills") and alice:HasText("Reward (total)"), "with the right labels")
    dialog.titleBox:Type("Wolfman")
    dialog.qty:Type("3")
    dialog.gold:Type("1")
    alice:FindButton("Post"):Click()
    local posted
    for _, x in pairs(A.Data.All()) do
        if x.title == "Wolfman" then posted = x end
    end
    T.check(posted and posted.type == "kos" and posted.quantity == 3 and posted.reward == 10000, "the dialog posts a hunt")

    for _, c in ipairs({ alice, bob }) do T.clean(c, c.name .. " has no errors") end
end
