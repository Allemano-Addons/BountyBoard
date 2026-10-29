-- Giving a job back, taking it again, and completing a bounty by hand; through the buttons too.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    local bob = world:client("Bob", { ui = true })
    local carl = world:client("Carl")
    world:advance(20)
    local A, B = alice.BB, bob.BB

    local b = A.Data.Post({ itemID = 12359, quantity = 10, reward = 500, days = 3, note = "" })
    A.Comm.SendBounty(b, "high")
    world:advance(5)
    bob:SetBag(12359, 4)
    local entry = B.Data.Take(b.id)
    B.Comm.SendTake(B.Data.Get(b.id), entry)
    world:advance(5)
    T.equal(A.Data.Get(b.id).status, "taken", "taken")

    -- Bob gives the job back through the button
    bob:Slash("")
    bob:FindButton("My Jobs"):Click()
    world:advance(0.5)
    T.check(bob:HasText("Abandon"), "a taker sees Abandon")
    bob:FindButton("Abandon"):Click()
    T.equal(#B.Data.Jobs(), 1, "one click does not abandon")
    bob:FindButton("Sure?"):Click()
    world:advance(5)
    T.equal(#B.Data.Jobs(), 0, "the job is gone from Bob's jobs")
    T.equal(A.Data.Get(b.id).status, "open", "the bounty is open again for Alice")
    T.equal(carl.BB.Data.Get(b.id).status, "open", "and for Carl")
    T.check(A.Data.TakerEntry(A.Data.Get(b.id), "Bob") == nil, "Alice no longer lists Bob")
    T.check(B.Data.Get(b.id).status == "open", "and Bob sees it open")

    -- an old copy cannot bring Bob back
    local stale = A.Data.ToWire(A.Data.Get(b.id))
    stale.k = "Bob:4:" .. (world.now - 100) .. ":0:0"
    A.Data.ApplyRemote(A.Data.FromWire(stale), "Carl")
    T.check(A.Data.TakerEntry(A.Data.Get(b.id), "Bob") == nil, "a stale copy does not bring a taker back")

    -- the marker travels with the bounty and survives the wire
    local back = A.Data.FromWire(A.Data.ToWire(A.Data.Get(b.id)))
    T.check(back.takers.Bob and back.takers.Bob.left, "the 'left' marker is in the wire format")

    -- he can take it again
    world:advance(2)
    bob:FindButton("Board"):Click()
    world:advance(0.5)
    bob:FindButton("Take Job"):Click()
    world:advance(5)
    T.equal(#B.Data.Jobs(), 1, "taking it again works")
    T.equal(A.Data.Get(b.id).status, "taken", "Alice sees it taken again")

    -- after a delivery the job cannot be given back
    local over = B.Data.TakerEntry(B.Data.Get(b.id), "Bob")
    over.delivered = 3
    local none, why = B.Data.Abandon(b.id)
    T.check(none == nil and why, "a job with delivered items cannot be abandoned")
    over.delivered = 0

    -- a forged abandon is refused
    local text = table.concat({ "1", "A", "fake1", "1/1", A.Comm.Encode({ i = b.id, w = "Bob", t = world.now + 50 }) }, "|")
    alice.BB.Comm.OnMessage("AllemanoBB", text, "GUILD", "Carl-Realm")
    T.check(A.Data.TakerEntry(A.Data.Get(b.id), "Bob") ~= nil, "an abandon in somebody else's name is refused")

    -- Alice completes by hand (two clicks)
    alice:Slash("")
    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    T.check(alice:HasText("Complete"), "the creator sees Complete on a taken bounty")
    alice:FindButton("Complete"):Click()
    T.equal(A.Data.Get(b.id).status, "taken", "one click does not complete")
    alice:FindButton("Sure?"):Click()
    world:advance(5)
    T.equal(A.Data.Get(b.id).status, "paid", "the second click completes it")
    T.equal(B.Data.Get(b.id).status, "paid", "Bob sees it complete")
    T.equal(A.Data.Completed("Bob"), 1, "Bob's completed jobs count")

    -- no Complete on an open bounty, and nobody else can complete
    local open = A.Data.Post({ itemID = 2772, quantity = 1, reward = 0, days = 1, note = "" })
    local r, err = A.Data.Complete(open.id)
    T.check(r == nil and err, "a bounty nobody took cannot be completed")
    local r2, err2 = B.Data.Complete(b.id)
    T.check(r2 == nil and err2, "only the creator can complete")

    T.clean(alice, "Alice has no errors")
    T.clean(bob, "Bob has no errors")
    T.clean(carl, "Carl has no errors")
end
