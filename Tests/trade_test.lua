-- Trade verification: a finished trade between a creator and a taker marks the bounty delivered and paid; the
-- creator's client is the one that makes it "paid"; the addon never moves items or gold itself.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { money = 1000000 })
    local bob = world:client("Bob", { money = 500 })
    local carl = world:client("Carl")
    world:advance(30)
    local THORIUM = 12359

    -- nothing in the addon may call a function that moves things (checked at run time too)
    for _, c in ipairs({ alice, bob, carl }) do
        for _, name in ipairs({ "AcceptTrade", "SendMail", "PickupPlayerMoney", "AddTradeMoney", "ClickTradeButton", "UseContainerItem" }) do
            c.env[name] = function() error(name .. " must never be called") end
        end
    end

    local function post(creator, quantity, reward, extra)
        local o = { itemID = THORIUM, quantity = quantity, reward = reward, days = 3, note = "" }
        for k, v in pairs(extra or {}) do o[k] = v end
        local b = creator.BB.Data.Post(o)
        creator.BB.Comm.SendBounty(b, "high")
        world:advance(5)
        return b
    end
    local function take(taker, id)
        local b = taker.BB.Data.Get(id)
        local entry = taker.BB.Data.Take(id)
        taker.BB.Comm.SendTake(b, entry)
        world:advance(5)
    end

    -- the pure matching
    do
        local Trade, Data = alice.BB.Trade, alice.BB.Data
        local b1 = post(alice, 10, 1000)
        local b2 = post(alice, 10, 2000)
        take(bob, b1.id)
        take(bob, b2.id)
        local snap = { partner = "Bob", t = world.now, mine = { items = {}, money = 2500 }, theirs = { items = { [THORIUM] = 15 }, money = 0 } }
        local result = Trade.Match(snap, "Alice", Data.All())
        T.equal(#result, 2, "two bounties match one trade")
        local byId = {}
        for _, r in ipairs(result) do byId[r.bounty.id] = r end
        T.equal(byId[b1.id].items, 10, "the oldest bounty is filled first")
        T.equal(byId[b2.id].items, 5, "the rest goes to the next")
        T.equal(byId[b1.id].copper, 1000, "the first is paid in full")
        T.equal(byId[b2.id].copper, 1500, "the second gets what is left")
        T.equal(#Trade.Match({ partner = "Carl", mine = { items = {}, money = 5 }, theirs = { items = { [THORIUM] = 5 }, money = 0 } }, "Alice", Data.All()), 0, "a stranger matches nothing")
        T.equal(#Trade.Match({ partner = nil, mine = { items = {}, money = 0 }, theirs = { items = {}, money = 0 } }, "Alice", Data.All()), 0, "no partner, no match")
        Data.Cancel(b1.id)
        Data.Cancel(b2.id)
        alice.BB.Comm.SendCancel(b1)
        alice.BB.Comm.SendCancel(b2)
        world:advance(5)
    end

    -- the whole flow: items one way, gold the other, both marked
    local events = {}
    alice.BB:On("NOTIFY", function(note) events[#events + 1] = note.title end)
    local b = post(alice, 20, 5000)
    take(bob, b.id)
    bob:SetBag(THORIUM, 20)
    world:advance(10)
    world:trade(alice, bob, { money = 5000 }, { items = { [THORIUM] = 20 } })
    world:advance(10)
    local onAlice, onBob = alice.BB.Data.Get(b.id), bob.BB.Data.Get(b.id)
    T.equal(onAlice.status, "paid", "Alice's client marks it paid")
    T.equal(onAlice.deliveredQty, 20, "20 delivered")
    T.equal(onAlice.paidCopper, 5000, "5000 copper paid")
    T.equal(onBob.status, "paid", "Bob sees it paid, confirmed by the creator")
    T.equal(alice.money, 1000000 - 5000, "Alice's gold moved (the game did it, not the addon)")
    T.equal(bob.bags[THORIUM], 0, "Bob's items moved")
    T.equal(carl.BB.Data.Get(b.id).status, "paid", "Carl sees it paid too")
    T.equal(alice.BB.Data.Completed("Bob"), 1, "Bob has one completed job on Alice's side")
    T.equal(bob.BB.Data.Completed("Bob"), 1, "and on his own")
    local inHistory = false
    for _, h in ipairs(alice.BB.Data.History()) do if h.id == b.id then inHistory = true end end
    T.check(inHistory, "it is in the history")
    local sawDelivery, sawPayment = false, false
    for _, title in ipairs(events) do
        if title == "DELIVERY VERIFIED" then sawDelivery = true end
        if title == "PAYMENT VERIFIED" then sawPayment = true end
    end
    T.check(sawDelivery and sawPayment, "Alice gets a delivery and a payment notice")

    -- in parts: items twice, the gold at the end
    local p = post(alice, 20, 3000)
    take(bob, p.id)
    bob:SetBag(THORIUM, 12)
    world:trade(alice, bob, {}, { items = { [THORIUM] = 12 } })
    world:advance(10)
    local part = alice.BB.Data.Get(p.id)
    T.equal(part.deliveredQty, 12, "12 of 20 delivered")
    T.equal(part.status, "taken", "still taken, not delivered")
    bob:SetBag(THORIUM, 8)
    world:trade(alice, bob, {}, { items = { [THORIUM] = 8 } })
    world:advance(10)
    T.equal(part.status, "delivered", "all 20 delivered, not paid yet")
    T.equal(bob.BB.Data.Get(p.id).status, "delivered", "Bob sees delivered")
    bob.money = 0
    world:trade(alice, bob, { money = 1000 }, {})
    world:advance(10)
    T.equal(part.status, "delivered", "part of the gold is not enough")
    world:trade(alice, bob, { money = 2000 }, {})
    world:advance(10)
    T.equal(part.status, "paid", "the rest of the gold makes it paid")
    T.equal(part.paidCopper, 3000, "exactly 3000 paid")
    T.equal(alice.BB.Data.Completed("Bob"), 2, "two completed jobs now")

    -- too many items: only what the bounty needs counts
    local over = post(alice, 5, 0)
    take(bob, over.id)
    bob:SetBag(THORIUM, 9)
    world:trade(alice, bob, {}, { items = { [THORIUM] = 9 } })
    world:advance(10)
    T.equal(alice.BB.Data.Get(over.id).deliveredQty, 5, "extra items are not counted")
    T.equal(alice.BB.Data.Get(over.id).status, "paid", "no reward: delivered is paid")

    -- a trade that is cancelled records nothing
    local c1 = post(alice, 5, 100)
    take(bob, c1.id)
    bob:SetBag(THORIUM, 5)
    world:trade(alice, bob, { money = 100 }, { items = { [THORIUM] = 5 } }, { cancel = true })
    world:advance(10)
    T.equal(alice.BB.Data.Get(c1.id).deliveredQty or 0, 0, "a cancelled trade records nothing")
    T.equal(alice.BB.Data.Get(c1.id).status, "taken", "the bounty is unchanged")

    -- a trade with somebody who did not take the job records nothing
    world:trade(alice, carl, { money = 100 }, { items = { [THORIUM] = 5 } })
    world:advance(10)
    T.equal(alice.BB.Data.Get(c1.id).deliveredQty or 0, 0, "a trade with a stranger records nothing")

    -- the taker cannot make a bounty paid by himself: the claim shows, the status does not change
    local claimBounty = post(alice, 5, 100)
    take(bob, claimBounty.id)
    local entry = bob.BB.Data.TakerEntry(bob.BB.Data.Get(claimBounty.id), "Bob")
    bob.BB.Data.RecordClaim(bob.BB.Data.Get(claimBounty.id), 5, 100)
    bob.BB.Comm.SendProgress(bob.BB.Data.Get(claimBounty.id), entry)
    world:advance(10)
    T.equal(alice.BB.Data.Get(claimBounty.id).status, "taken", "a claim alone does not make it paid")
    T.equal(alice.BB.Data.TakerEntry(alice.BB.Data.Get(claimBounty.id), "Bob").delivered, 5, "but others see the claim")

    -- the trade message is "secret" (WoW Forever): nothing breaks
    alice.env.issecretvalue = function(v) return v == "secret" end
    alice:Event("UI_INFO_MESSAGE", 0, "secret")
    alice:Event("CHAT_MSG_SYSTEM", "secret")
    alice.env.issecretvalue = nil

    -- a trade without the message is noticed from the bags (the older open bounties are out of the way first)
    for _, old in ipairs({ c1, claimBounty }) do
        alice.BB.Data.Cancel(old.id)
        alice.BB.Comm.SendCancel(old)
    end
    world:advance(5)
    local noMsg = post(alice, 5, 0)
    take(bob, noMsg.id)
    bob:SetBag(THORIUM, 5)
    alice:OpenTrade("Bob", {}, { items = { [THORIUM] = 5 } })
    bob:OpenTrade("Alice", { items = { [THORIUM] = 5 } }, {})
    alice:Event("TRADE_ACCEPT_UPDATE", 1, 1)
    bob:Event("TRADE_ACCEPT_UPDATE", 1, 1)
    alice.bags[THORIUM] = (alice.bags[THORIUM] or 0) + 5 -- the game moved the items, but said nothing
    alice.trade = nil
    alice:Event("TRADE_CLOSED")
    world:advance(5)
    T.equal(alice.BB.Data.Get(noMsg.id).deliveredQty, 5, "a trade is also noticed from the bags when the message is missing")

    -- as the real game does it: no "both accepted" update, and the window empties before the message
    local real = post(alice, 5, 700)
    take(bob, real.id)
    bob:SetBag(THORIUM, 5)
    world:trade(alice, bob, { money = 700 }, { items = { [THORIUM] = 5 } }, { noFinalAccept = true })
    world:advance(10)
    T.equal(alice.BB.Data.Get(real.id).status, "paid", "a trade is found even without the final accept update")
    T.equal(bob.BB.Data.Get(real.id).status, "paid", "and Bob sees it complete")

    -- a one-sided accept that is then cancelled records nothing
    local cancelled = post(alice, 5, 0)
    take(bob, cancelled.id)
    bob:SetBag(THORIUM, 5)
    alice:OpenTrade("Bob", {}, { items = { [THORIUM] = 5 } })
    alice:Event("TRADE_ACCEPT_UPDATE", 0, 1)
    alice:CloseTrade()
    alice:Event("TRADE_CLOSED")
    world:advance(10)
    T.equal(alice.BB.Data.Get(cancelled.id).deliveredQty or 0, 0, "a cancelled trade after a one-sided accept records nothing")

    for _, c in ipairs({ alice, bob, carl }) do T.clean(c, c.name .. " has no errors") end
end
