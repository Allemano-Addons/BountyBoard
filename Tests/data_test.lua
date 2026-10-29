-- The bounty model: posting, taking, cancelling, expiry, the wire format and merging remote copies.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local a = world:client("Alice")
    local BB = a.BB
    local Data, Comm = BB.Data, BB.Comm

    local function opts(extra)
        local o = { itemID = 12359, quantity = 20, reward = 50000, days = 3, note = "for the forge" }
        for k, v in pairs(extra or {}) do o[k] = v end
        return o
    end

    -- posting
    local b = Data.Post(opts())
    T.check(b ~= nil, "a valid bounty is posted")
    T.equal(b.status, "open", "a new bounty is open")
    T.equal(b.creator, "Alice", "the creator is the player")
    T.equal(b.deadline, b.createdAt + 3 * 86400, "the deadline follows the choice of days")
    T.check(b.id:find("^Alice%-1%-"), "the id is creator, counter and time")
    local b2 = Data.Post(opts())
    T.check(b2.id ~= b.id, "two bounties get two ids")

    local _, err = Data.Post(opts({ itemID = 0 }))
    T.check(err ~= nil, "no item is refused: " .. tostring(err))
    _, err = Data.Post(opts({ quantity = 0 }))
    T.check(err ~= nil, "quantity 0 is refused")
    _, err = Data.Post(opts({ quantity = 10000 }))
    T.check(err ~= nil, "quantity above the maximum is refused")
    _, err = Data.Post(opts({ reward = -1 }))
    T.check(err ~= nil, "a negative reward is refused")
    _, err = Data.Post(opts({ reward = 2147483648 }))
    T.check(err ~= nil, "a reward above the gold cap is refused")
    _, err = Data.Post(opts({ days = 2 }))
    T.check(err ~= nil, "a deadline that is not offered is refused")
    _, err = Data.Post(opts({ type = "weird" }))
    T.check(err ~= nil, "an unknown type is refused")
    T.check(Data.Post(opts({ reward = 0 })) ~= nil, "a bounty without a reward is allowed")

    -- the limit of open bounties
    T.equal(Data.OpenCount(), 3, "three open bounties so far")
    Data.Post(opts())
    Data.Post(opts())
    T.equal(Data.OpenCount(), 5, "five open bounties")
    _, err = Data.Post(opts())
    T.check(err ~= nil, "a sixth open bounty is refused")
    Data.Cancel(b2.id)
    T.check(Data.Post(opts()) ~= nil, "after a cancel there is room again")

    -- the note is cleaned and cut
    local long = Data.Post(opts({ note = string.rep("x", 300) }))
    T.check(long == nil, "still full (5 open)") -- 5 open again
    Data.Cancel(b.id)
    long = Data.Post(opts({ note = string.rep("x", 300) }))
    T.check(long and #long.note <= Data.MAX_NOTE, "a long note is cut to the maximum")

    -- taking
    local bob = world:client("Bob")
    local Bd = bob.BB.Data
    Data.Cancel(long.id)
    local mine = Data.Post(opts())
    T.check(mine ~= nil, "room for one more")
    -- Bob receives Alice's bounty by hand (the wire is tested in sync_test)
    local wire = Data.ToWire(mine)
    local copy = Bd.FromWire(wire)
    T.check(copy ~= nil, "a bounty survives the trip over the wire")
    T.equal(Bd.ApplyRemote(copy, "Alice"), "new", "Bob accepts it as new")
    local entry = Bd.Take(copy.id)
    T.check(entry ~= nil, "Bob takes the job")
    T.equal(Bd.Get(copy.id).status, "taken", "a bounty with a taker is taken")
    local again, why = Bd.Take(copy.id)
    T.check(again == nil and why, "taking twice is refused")
    local own, why2 = Data.Take(mine.id)
    T.check(own == nil and why2, "taking your own bounty is refused")

    -- the creator cancels: the version goes up
    local before = mine.version
    Data.Cancel(mine.id)
    T.equal(mine.status, "cancelled", "the creator cancels")
    T.equal(mine.version, before + 1, "a cancel raises the version")
    local nope, why3 = Bd.Cancel(copy.id)
    T.check(nope == nil and why3, "somebody else cannot cancel")

    -- expiry
    local x = Data.Post(opts({ days = 1 }))
    world:advance(86400 + 5)
    Data.Expire()
    T.equal(x.status, "expired", "a bounty past its deadline expires")
    T.check(not Data.IsActive(x), "an expired bounty is not active")
    local late, why4 = Bd.Take(copy.id)
    T.check(late == nil and why4, "a closed bounty cannot be taken")

    -- merging remote copies: the highest version wins, takers are merged
    local c = world:client("Carl")
    local Cd = c.BB.Data
    local base = Data.Post(opts({ days = 7 }))
    local v1 = Cd.FromWire(Data.ToWire(base))
    T.equal(Cd.ApplyRemote(v1, "Alice"), "new", "Carl gets version 1")
    Cd.Take(v1.id)
    local older = Cd.FromWire(Data.ToWire(base))
    T.equal(Cd.ApplyRemote(older, "Alice"), "ignored", "the same version again changes nothing")
    T.check(Cd.TakerEntry(Cd.Get(v1.id), "Carl") ~= nil, "Carl's own take survives an equal version")
    base.version = base.version + 1
    base.note = "changed"
    local newer = Cd.FromWire(Data.ToWire(base))
    T.equal(Cd.ApplyRemote(newer, "Alice"), "updated", "a higher version updates")
    T.equal(Cd.Get(v1.id).note, "changed", "the creator's fields win")
    T.check(Cd.TakerEntry(Cd.Get(v1.id), "Carl") ~= nil, "an update keeps the takers it already knew")
    base.version = 1
    base.note = "old"
    T.equal(Cd.ApplyRemote(Cd.FromWire(Data.ToWire(base)), "Alice"), "ignored", "a lower version does not overwrite")
    T.equal(Cd.Get(v1.id).note, "changed", "the note stays")

    -- hostile or broken input
    local bad = Data.ToWire(base)
    bad.q = "-5"
    T.check(Cd.FromWire(bad) == nil, "a negative quantity does not parse")
    bad = Data.ToWire(base)
    bad.r = "99999999999"
    T.check(Cd.FromWire(bad) == nil, "a reward above the cap does not parse")
    bad = Data.ToWire(base)
    bad.y = "weird"
    T.check(Cd.FromWire(bad) == nil, "an unknown type does not parse")
    T.check(Cd.FromWire({}) == nil, "an empty message does not parse")
    T.check(Cd.FromWire("text") == nil, "a non-table does not parse")

    T.clean(a, "Alice has no errors")
    T.clean(bob, "Bob has no errors")
    T.clean(c, "Carl has no errors")
    T.check(Comm.Encode({ a = "x y", b = 5 }) == "a=x y;b=5", "encode is stable")
end
