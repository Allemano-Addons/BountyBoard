-- Help bounties: no item, a few words instead; the helper says it is done, the creator confirms, gold by trade.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    local bob = world:client("Bob", { ui = true })
    world:advance(20)
    local A, B = alice.BB, bob.BB

    -- the rules
    local _, err = A.Data.Post({ type = "help", title = "", reward = 0, days = 1 })
    T.check(err ~= nil, "a help bounty needs words: " .. tostring(err))
    _, err = A.Data.Post({ type = "help", title = "hi", reward = 0, days = 1 })
    T.check(err ~= nil, "two letters are not enough")
    local b = A.Data.Post({ type = "help", title = "Scholomance run, need a tank", reward = 500, days = 3, note = "Saturday 20:00" })
    T.check(b ~= nil, "a help bounty is posted")
    T.equal(b.itemID, 0, "no item")
    T.equal(b.quantity, 1, "quantity 1")
    T.equal(A.Data.ItemName(b), "Scholomance run, need a tank", "its name is the title")
    local f = A.Data.ToWire(b)
    local copy = B.Data.FromWire(f)
    T.check(copy and copy.title == b.title and copy.itemID == 0, "it survives the wire")
    f.ti = ""
    T.check(B.Data.FromWire(f) == nil, "a help bounty without a title does not parse")
    local farm = A.Data.ToWire(b)
    farm.y = "farm"
    T.check(B.Data.FromWire(farm) == nil, "a farm bounty still needs an item")
    A.Comm.SendBounty(b, "high")
    world:advance(5)

    -- Bob sees it and offers help
    bob:Slash("")
    world:advance(0.5)
    T.check(bob:HasText("Scholomance run, need a tank"), "the card shows the title")
    T.check(bob:HasText("HELP"), "with a HELP tag")
    T.check(bob:HasText("Offer Help"), "and an Offer Help button")
    T.check(bob:HasText("Nobody has offered") or bob:HasText("Saturday 20:00"), "the note is shown")
    bob:SetBag(12359, 5)
    bob:FindButton("Offer Help"):Click()
    world:advance(5)
    T.equal(A.Data.Get(b.id).status, "taken", "Alice sees it taken")
    T.equal(#B.Data.Jobs(), 1, "Bob has a job")
    bob:SetBag(12359, 9)
    world:advance(20)
    T.equal(A.Data.TakerEntry(A.Data.Get(b.id), "Bob").progress, 0, "bags are not counted for help")

    -- Bob says it is done; Alice is told and confirms
    local told = false
    alice.BB:On("HELP_DONE", function() told = true end)
    bob:FindButton("My Jobs"):Click()
    world:advance(0.5)
    T.check(bob:HasText("I helped"), "the helper has an I helped button")
    bob:FindButton("I helped"):Click()
    bob:FindButton("Sure?"):Click()
    world:advance(5)
    T.check(told, "Alice is told that Bob says it is done")
    T.check(bob:HasText("Waiting for confirmation"), "Bob sees that it waits for the creator")
    alice:Slash("")
    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    T.check(alice:HasText("says it is done"), "Alice sees the claim on the card")
    alice:FindButton("Confirm help"):Click()
    A.Board.Request() -- a redraw while the Sure? is waiting must not reset it
    world:advance(1)
    T.check(alice:HasText("Sure?") and not alice:HasText("Confirm help"), "a redraw keeps the Sure? waiting")
    world:advance(3)
    T.check(alice:HasText("Confirm help"), "and it goes back after three seconds")
    alice:FindButton("Confirm help"):Click()
    alice:FindButton("Sure?"):Click()
    world:advance(5)
    local onAlice = A.Data.Get(b.id)
    T.equal(onAlice.status, "delivered", "confirmed, but the reward is not paid yet")
    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    T.check(not alice:HasText("Confirm help"), "Confirm help is gone once confirmed")
    T.check(alice:HasText("Awaiting payment"), "the creator sees that payment is missing")
    bob:FindButton("My Jobs"):Click()
    world:advance(0.5)
    T.check(bob:HasText("Confirmed, awaiting payment") and not bob:HasText("Waiting for confirmation"), "the helper sees it is confirmed")

    -- the gold arrives by trade
    alice.money = 10000
    world:trade(alice, bob, { money = 500 }, {})
    world:advance(10)
    T.equal(onAlice.status, "paid", "the trade pays it: complete")
    T.equal(B.Data.Get(b.id).status, "paid", "Bob sees it complete")
    T.equal(B.Data.Completed("Bob"), 1, "Bob's job counter went up")

    -- a help bounty without a reward is complete at the confirmation
    local free = A.Data.Post({ type = "help", title = "Summon to Ironforge", reward = 0, days = 1 })
    A.Comm.SendBounty(free, "high")
    world:advance(5)
    local entry = B.Data.Take(free.id)
    B.Comm.SendTake(B.Data.Get(free.id), entry)
    world:advance(5)
    local done = A.Data.ConfirmHelp(free.id)
    T.check(done and done.status == "paid", "no reward: confirming completes it")
    local nobody = A.Data.Post({ type = "help", title = "Nobody comes", reward = 0, days = 1 })
    local r, why = A.Data.ConfirmHelp(nobody.id)
    T.check(r == nil and why, "nobody took it: nothing to confirm")
    local r2, why2 = B.Data.ConfirmHelp(free.id)
    T.check(r2 == nil and why2, "only the creator confirms")

    -- the dialog
    A.Main.Show()
    alice:FindButton("+ Post Bounty"):Click()
    local dialog = A.PostDialog.Frame()
    dialog.typeBox:Set("help")
    dialog.typeBox.scripts.OnClick(dialog.typeBox, "LeftButton") -- opens the menu
    T.check(alice:HasText("Help"), "Help is a choice in the type list")
    for _, fr in ipairs(alice.frames) do
        if fr.kind == "Button" and fr.item and fr.item.text == "Help" and fr:IsVisible() then fr:Click() end
    end
    T.check(dialog.titleBox:IsShown() and not dialog.slot:IsShown(), "choosing Help swaps the item for words")
    T.check(not dialog.qty:IsShown(), "and hides the quantity")
    dialog.titleBox:Type("Escort me to the Dark Portal")
    dialog.gold:Type("2")
    alice:FindButton("Post"):Click()
    local posted
    for _, x in pairs(A.Data.All()) do
        if x.title == "Escort me to the Dark Portal" then posted = x end
    end
    T.check(posted ~= nil and posted.type == "help" and posted.reward == 20000, "the dialog posts a help bounty")

    -- the filter
    bob:FindButton("Board"):Click()
    world:advance(1)
    T.check(bob:HasText("Help"), "Help is a filter on the board")

    for _, c in ipairs({ alice, bob }) do T.clean(c, c.name .. " has no errors") end
end
