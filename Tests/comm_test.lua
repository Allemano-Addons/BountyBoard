-- The wire: encoding, cutting long messages into parts, putting them together, garbage, throttling.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local a = world:client("Alice")
    local b = world:client("Bob")
    local Comm, Data = a.BB.Comm, a.BB.Data

    -- text <-> table
    local nasty = { n = "50% off; a=b | \"quoted\" é ü 日本", i = "x-1", q = 20 }
    local back = Comm.Decode(Comm.Encode(nasty))
    T.equal(back.n, nasty.n, "special characters survive encode and decode")
    T.equal(back.q, "20", "numbers come back as text")
    T.equal(Comm.Encode({ b = 1, a = 2 }), "a=2;b=1", "keys are sorted")
    T.check(type(Comm.Decode("")) == "table", "decoding nothing gives a table")
    local many = {}
    for i = 1, 100 do many[#many + 1] = "k" .. i .. "=v" end
    local n = 0
    for _ in pairs(Comm.Decode(table.concat(many, ";"))) do n = n + 1 end
    T.check(n <= 40, "at most 40 fields are read")

    -- a long bounty is sent in parts of at most 255 bytes and arrives whole
    local note = string.rep("%;=|é", 24) -- 120 characters that all need escaping
    local bounty = Data.Post({ itemID = 12359, quantity = 20, reward = 12345, days = 7, note = note })
    local takers = {}
    for i = 1, 8 do
        bounty.takers["Hunter" .. i] = { progress = i, updatedAt = world.now - 100, delivered = 0, paid = 0 }
    end
    Comm.SendBounty(bounty, "high")
    world:advance(30)
    T.equal(world.oversize, 0, "no message is longer than 255 bytes")
    local got = b.BB.Data.Get(bounty.id)
    T.check(got ~= nil, "Bob received the long bounty")
    T.equal(got and got.note, bounty.note, "the note arrived intact")
    local count = 0
    for _ in pairs(got and got.takers or {}) do count = count + 1 end
    T.equal(count, 8, "all takers arrived")
    T.check(world.sent > 1, "it needed more than one message (" .. world.sent .. ")")

    -- parts that come in the wrong order, twice, or from a stranger
    local c = world:client("Carl")
    local C2 = c.BB.Comm
    local sent = {}
    local original = a.env.C_ChatInfo.SendAddonMessage
    a.env.C_ChatInfo.SendAddonMessage = function(prefix, text, channel) sent[#sent + 1] = text return true end
    Comm.SendBounty(bounty, "high")
    Comm.Flush()
    a.env.C_ChatInfo.SendAddonMessage = original
    T.check(#sent >= 2, "the bounty is cut into parts (" .. #sent .. ")")
    for i = #sent, 1, -1 do C2.OnMessage("AllemanoBB", sent[i], "GUILD", "Alice-Realm") end
    T.check(c.BB.Data.Get(bounty.id) ~= nil, "parts in reverse order are put together")

    local d = world:client("Dora")
    for i = 1, #sent do
        d.BB.Comm.OnMessage("AllemanoBB", sent[i], "GUILD", "Alice-Realm")
        d.BB.Comm.OnMessage("AllemanoBB", sent[i], "GUILD", "Alice-Realm") -- the same part twice
    end
    T.check(d.BB.Data.Get(bounty.id) ~= nil, "a part that comes twice does no harm")

    local e = world:client("Eve")
    for i = 1, #sent - 1 do e.BB.Comm.OnMessage("AllemanoBB", sent[i], "GUILD", "Alice-Realm") end
    T.check(e.BB.Data.Get(bounty.id) == nil, "a message with a part missing is not used")

    -- garbage does nothing (and does not raise errors)
    local f = world:client("Fay")
    local F = f.BB.Comm
    local junk = {
        "", "hello", "1|X|abc|1/1|i=1", "2|N|abc|1/1|i=1", "1|N|abc|0/1|i=1", "1|N|abc|5/2|i=1", "1|N|abc|1/99|i=1",
        "1|N|abc|1/1|", "1|N|abc|1/1|i=1;c=;m=abc", "1|T|abc|1/1|i=nope;w=Nobody", "1|C|abc|1/1|i=x;v=zzz",
        "1|M|abc|1/1|e=:::,,,,1:2", "1|R|abc|1/1|e=" .. string.rep("a,", 500), "|||||", string.rep("x", 5000),
    }
    for _, text in ipairs(junk) do F.OnMessage("AllemanoBB", text, "GUILD", "Alice-Realm") end
    F.OnMessage("Other", "1|N|abc|1/1|i=1", "GUILD", "Alice-Realm")
    F.OnMessage("AllemanoBB", "1|N|abc|1/1|i=1", "WHISPER", "Alice-Realm")
    F.OnMessage("AllemanoBB", nil, "GUILD", "Alice-Realm")
    F.OnMessage("AllemanoBB", "1|N|abc|1/1|i=1", "GUILD", nil)
    T.clean(f, "garbage causes no errors")
    local bountiesOfFay = 0
    for _ in pairs(f.BB.Data.All()) do bountiesOfFay = bountiesOfFay + 1 end
    T.equal(bountiesOfFay, 0, "garbage creates no bounty")

    -- a message from yourself is ignored
    local before = 0
    for _ in pairs(a.BB.Data.All()) do before = before + 1 end
    Comm.OnMessage("AllemanoBB", sent[1], "GUILD", "Alice-Realm")
    local after = 0
    for _ in pairs(a.BB.Data.All()) do after = after + 1 end
    T.equal(before, after, "own messages change nothing")

    -- a player outside any guild sends nothing
    local loner = world:client("Loner", { guild = false })
    T.check(loner.BB.Comm.Send("M", { e = "" }) == false, "no guild: nothing is sent")

    -- a refused send (the game says "too fast") is tried again, nothing is lost
    local g = world:client("Gus")
    local h = world:client("Hal")
    local refuse = 3
    local realSend = g.env.C_ChatInfo.SendAddonMessage
    g.env.C_ChatInfo.SendAddonMessage = function(...)
        if refuse > 0 then refuse = refuse - 1 return false end
        return realSend(...)
    end
    local gb = g.BB.Data.Post({ itemID = 2772, quantity = 5, reward = 100, days = 1, note = "ore" })
    g.BB.Comm.SendBounty(gb, "high")
    world:advance(30)
    T.check(h.BB.Data.Get(gb.id) ~= nil, "a refused message is sent again and arrives")
    T.equal(refuse, 0, "the refusals were really used")

    for _, client in ipairs({ a, b, c, d, e, f, g, h }) do T.clean(client, client.name .. " has no errors") end
end
