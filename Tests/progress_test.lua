-- Live progress: the bags are counted after a short wait, a message goes out only when the number changes and at
-- most once every five seconds per bounty; the other players see the number and its age.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice")
    local bob = world:client("Bob")
    world:advance(30)

    local progressMessages = 0
    local real = bob.env.C_ChatInfo.SendAddonMessage
    bob.env.C_ChatInfo.SendAddonMessage = function(prefix, text, channel)
        if text:find("^1|P|") then progressMessages = progressMessages + 1 end
        return real(prefix, text, channel)
    end

    local b = alice.BB.Data.Post({ itemID = 12359, quantity = 20, reward = 100, days = 3, note = "" })
    alice.BB.Comm.SendBounty(b, "high")
    world:advance(5)
    bob:SetBag(12359, 3)
    local entry = bob.BB.Data.Take(b.id)
    bob.BB.Comm.SendTake(bob.BB.Data.Get(b.id), entry)
    bob.BB.Progress.Taken(bob.BB.Data.Get(b.id))
    world:advance(10)
    T.equal(bob.BB.Data.TakerEntry(bob.BB.Data.Get(b.id), "Bob").progress, 3, "taking a job counts the bags")
    T.equal(progressMessages, 0, "the take message carried the number, no progress message yet")

    -- a burst of bag events makes one count
    for i = 4, 10 do bob:SetBag(12359, i) end
    T.equal(bob.BB.Data.TakerEntry(bob.BB.Data.Get(b.id), "Bob").progress, 3, "nothing is counted until things calm down")
    world:advance(1.5)
    T.equal(bob.BB.Data.TakerEntry(bob.BB.Data.Get(b.id), "Bob").progress, 10, "the bags are counted a second later")
    world:advance(10)
    T.equal(progressMessages, 1, "one message for the whole burst")
    T.equal(alice.BB.Data.TakerEntry(alice.BB.Data.Get(b.id), "Bob").progress, 10, "Alice sees 10")

    -- no change, no message
    bob:Event("BAG_UPDATE", 0)
    world:advance(10)
    T.equal(progressMessages, 1, "the same number is not sent again")

    -- changes in quick succession are held back to one message every five seconds
    bob:SetBag(12359, 11)
    world:advance(1.2)
    bob:SetBag(12359, 12)
    world:advance(1.2)
    bob:SetBag(12359, 13)
    world:advance(1.2)
    local early = progressMessages
    T.check(early <= 2, "at most one more message within five seconds (" .. early .. ")")
    world:advance(20)
    T.equal(alice.BB.Data.TakerEntry(alice.BB.Data.Get(b.id), "Bob").progress, 13, "the last number is the one that gets through")
    T.check(progressMessages <= 3, "few messages in total (" .. progressMessages .. ")")

    -- selling items lowers the number
    bob:SetBag(12359, 2)
    world:advance(15)
    T.equal(alice.BB.Data.TakerEntry(alice.BB.Data.Get(b.id), "Bob").progress, 2, "a lower number is sent too")

    -- an old number shows its age
    local data = alice.BB.Data
    T.equal(data.AgeText(30), "just now", "30 seconds is just now")
    T.equal(data.AgeText(300), "5 min ago", "minutes")
    T.equal(data.AgeText(7200), "2 h ago", "hours")
    T.equal(data.AgeText(3 * 86400), "3 days ago", "days")

    -- an older number never overwrites a newer one
    local mineEntry = alice.BB.Data.TakerEntry(alice.BB.Data.Get(b.id), "Bob")
    local stamp = mineEntry.updatedAt
    alice.BB.Data.ApplyProgress(b.id, "Bob", 99, stamp - 1000, 0, 0)
    T.equal(mineEntry.progress, 2, "a stale progress message is ignored")

    -- a player who is not a taker cannot report progress
    T.check(alice.BB.Data.ApplyProgress(b.id, "Mallory", 5, world.now, 0, 0) == nil, "only takers report progress")

    -- the job ends: no more counting for it
    alice.BB.Data.Cancel(b.id)
    alice.BB.Comm.SendCancel(b)
    world:advance(5)
    local messages = progressMessages
    bob:SetBag(12359, 20)
    world:advance(20)
    T.equal(progressMessages, messages, "a cancelled job is not counted any more")

    T.clean(alice, "Alice has no errors")
    T.clean(bob, "Bob has no errors")
end
