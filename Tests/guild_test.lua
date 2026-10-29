-- Guild goals: posted by the ranks the settings allow, anybody contributes, the recipient verifies each trade and pays
-- the reward for every item.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true, rank = 0, money = 1000000 })
    local bob = world:client("Bob", { ui = true, rank = 3, money = 0 })
    local carl = world:client("Carl", { ui = true, rank = 4, money = 0 })
    local dora = world:client("Dora", { ui = true, rank = 3, money = 1000000 })
    world:advance(20)
    local A, B, D = alice.BB, bob.BB, dora.BB
    local THORIUM = 12359

    -- who may post
    local _, err = B.Data.Post({ type = "guild", itemID = THORIUM, quantity = 40, reward = 100, days = 3 })
    T.check(err ~= nil, "rank 3 may not post a guild goal by default: " .. tostring(err))
    B.Settings.Set("guildPostRank", 3)
    T.check(B.Data.Post({ type = "guild", itemID = THORIUM, quantity = 1, reward = 0, days = 1 }) ~= nil, "when the setting allows rank 3 it may")
    B.Settings.Set("guildPostRank", 1)
    T.check(A.Data.CanPostGuild(), "the Guild Master may")
    A.Settings.Set("guildPostRank", 99)
    carl.BB.Settings.Set("guildPostRank", 99)
    T.check(carl.BB.Data.CanPostGuild(), "everyone, when the setting says so")
    A.Settings.Set("guildPostRank", 1)

    -- a goal
    local goal = A.Data.Post({ type = "guild", itemID = THORIUM, quantity = 40, reward = 100, days = 7, note = "For the Naxx flasks" })
    T.check(goal ~= nil, "a guild goal is posted")
    A.Comm.SendBounty(goal, "high")
    world:advance(5)
    T.equal(B.Data.Get(goal.id).type, "guild", "everybody gets it")
    T.equal(B.Data.Recipient(B.Data.Get(goal.id)), "Alice", "the creator receives unless somebody else is named")

    bob:Slash("")
    world:advance(0.5)
    T.check(bob:HasText("GUILD") and bob:HasText("0/40 delivered"), "the card shows a GUILD tag and one bar for everybody")
    T.check(bob:HasText("Contribute"), "with a Contribute button")
    T.check(bob:HasText("each"), "and the reward per item")
    bob:SetBag(THORIUM, 8)
    bob:FindButton("Contribute"):Click()
    world:advance(5)
    T.check(bob:HasText("Contributing"), "Bob is contributing")
    alice:Slash("")
    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    T.check(alice:HasText("0/40 delivered · 8 in bags"), "Alice sees what is on the way")

    -- Bob delivers 10 (he had 8 in the bags, then farmed more) and is paid 10 x 100
    bob:SetBag(THORIUM, 10)
    world:trade(alice, bob, { money = 1000 }, { items = { [THORIUM] = 10 } })
    world:advance(10)
    local onAlice = A.Data.Get(goal.id)
    T.equal(onAlice.deliveredQty, 10, "10 delivered")
    T.equal(onAlice.paidCopper, 1000, "10 x 100 paid")
    T.equal(onAlice.status, "taken", "not complete yet")
    T.equal(B.Data.Get(goal.id).deliveredQty, 10, "everybody sees 10 of 40")
    world:advance(1)
    T.check(alice:HasText("10/40 delivered"), "the bar moves")
    T.check(alice:HasText("|r  10") and alice:HasText("Most:"), "and names the biggest contributor")

    -- Carl never pressed Contribute: giving is enough
    carl:SetBag(THORIUM, 30)
    world:trade(alice, carl, { money = 3000 }, { items = { [THORIUM] = 30 } })
    world:advance(10)
    T.equal(onAlice.deliveredQty, 40, "40 of 40")
    T.equal(onAlice.status, "paid", "all delivered and paid: complete")
    T.check(A.Data.TakerEntry(onAlice, "Carl") ~= nil, "Carl became a contributor by giving")
    T.equal(carl.BB.Data.Get(goal.id).status, "paid", "Carl sees it complete")

    -- more than needed is not counted (nothing left to deliver)
    world:trade(alice, bob, { money = 0 }, { items = { [THORIUM] = 5 } })
    world:advance(5)
    T.equal(onAlice.deliveredQty, 40, "a finished goal takes nothing more")

    -- a gold-only trade does not pay what was not delivered
    local second = A.Data.Post({ type = "guild", itemID = THORIUM, quantity = 10, reward = 500, days = 3 })
    A.Comm.SendBounty(second, "high")
    world:advance(5)
    bob:SetBag(THORIUM, 4)
    world:trade(alice, bob, { money = 5000 }, { items = { [THORIUM] = 4 } })
    world:advance(10)
    T.equal(second.paidCopper, 2000, "4 items are paid 4 x 500, not what was offered")

    -- another recipient: the guild bank alt verifies, the creator follows
    local bank = A.Data.Post({ type = "guild", itemID = THORIUM, quantity = 20, reward = 50, days = 3, recipient = "Dora" })
    T.equal(bank.recipient, "Dora", "a recipient can be named")
    A.Comm.SendBounty(bank, "high")
    world:advance(5)
    T.equal(D.Data.Recipient(D.Data.Get(bank.id)), "Dora", "Dora knows she receives")
    carl:SetBag(THORIUM, 20)
    world:trade(dora, carl, { money = 1000 }, { items = { [THORIUM] = 20 } })
    world:advance(10)
    T.equal(D.Data.Get(bank.id).status, "paid", "the recipient verifies and completes it")
    T.equal(A.Data.Get(bank.id).deliveredQty, 20, "the creator sees it too")
    T.check(A.Data.Get(bank.id).status == "paid", "as complete")

    -- the dialog
    A.Main.Show()
    alice:FindButton("+ Post Bounty"):Click()
    local dialog = A.PostDialog.Frame()
    dialog.typeBox:Set("guild")
    dialog.typeBox.scripts.OnClick(dialog.typeBox, "LeftButton")
    for _, fr in ipairs(alice.frames) do
        if fr.kind == "Button" and fr.item and fr.item.text == "Guild goal" and fr:IsVisible() then fr:Click() end
    end
    T.check(dialog.recipient:IsShown() and dialog.slot:IsShown(), "the dialog asks for an item and a recipient")
    T.check(alice:HasText("Amount needed") and alice:HasText("Reward for each"), "with the right labels")

    for _, c in ipairs({ alice, bob, carl, dora }) do T.clean(c, c.name .. " has no errors") end
end
