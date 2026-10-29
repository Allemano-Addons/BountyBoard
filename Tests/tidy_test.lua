-- Colours by bounty type, the sound choice, and clearing finished bounties.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    local bob = world:client("Bob", { ui = true })
    world:advance(20)
    local A, B = alice.BB, bob.BB

    local function post(c, extra)
        local o = { itemID = 12359, quantity = 1, reward = 0, days = 3, note = "" }
        for k, v in pairs(extra or {}) do o[k] = v end
        local b = c.BB.Data.Post(o)
        c.BB.Comm.SendBounty(b, "high")
        world:advance(3)
        return b
    end

    -- colours
    local kos = post(alice, { type = "kos", title = "Wolfman", quantity = 1 })
    local farm = post(alice)
    alice:Slash("")
    world:advance(0.5)
    local function tagColor(text)
        for _, f in ipairs(alice.frames) do
            if f.kind == "FontString" and f.text == text and f.color and f:IsVisible() then return f.color end
        end
    end
    local red, gold = tagColor("KILL"), tagColor("FARM")
    local kc, fc = { A.Theme:Color("typeKos") }, { A.Theme:Color("typeFarm") }
    T.check(red and math.abs(red[1] - kc[1]) < 0.01 and math.abs(red[2] - kc[2]) < 0.01, "the KILL tag has the kill colour")
    T.check(gold and math.abs(gold[1] - fc[1]) < 0.01 and math.abs(gold[2] - fc[2]) < 0.01, "the FARM tag has the farm colour")
    T.check(red[1] ~= gold[1], "and they differ")
    A.Settings.Set("typeColors", false)
    world:advance(0.5)
    local plain = tagColor("KILL")
    local dim = { A.Theme:Color("textDim") }
    T.check(plain and math.abs(plain[1] - dim[1]) < 0.01, "with the setting off the tags are plain")
    A.Settings.Set("typeColors", true)

    -- sounds
    T.check(#A.Toast.SoundOptions() >= 7, "there are sounds to choose from")
    local played = {}
    alice.env.PlaySound = function(id) played[#played + 1] = id end
    A.Settings.Set("soundChoice", "ready")
    T.equal(played[1], 8960, "choosing a sound plays it as a preview")
    A.Toast.Show({ title = "x", text = "y" })
    T.equal(played[2], 8960, "and the toasts use it")
    A.Settings.Set("soundChoice", "none")
    A.Toast.Show({ title = "x", text = "y" })
    T.equal(#played, 2, "Off is silent")
    A.Settings.Set("soundChoice", "toast")

    -- clearing
    A.Data.Cancel(farm.id)
    A.Comm.SendCancel(farm)
    local other = post(bob)
    B.Data.Cancel(other.id)
    B.Comm.SendCancel(other)
    world:advance(5)
    T.equal(A.Data.FinishedCount("history"), 2, "two finished bounties in the history")
    T.equal(A.Data.FinishedCount("mine"), 1, "one of them is Alice's")

    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    T.check(alice:HasText("Clear finished (1)"), "My Bounties offers to clear what is finished")
    alice:FindButton("Clear finished (1)"):Click()
    T.equal(A.Data.FinishedCount("mine"), 1, "one click does not clear")
    alice:FindButton("Sure?"):Click()
    world:advance(0.5)
    T.equal(A.Data.FinishedCount("mine"), 0, "the second clears Alice's finished ones")
    T.check(A.Data.Get(kos.id) ~= nil, "an open bounty stays")
    T.equal(A.Data.FinishedCount("history"), 1, "Bob's finished one is still in the history")

    alice:FindButton("History"):Click()
    world:advance(0.5)
    T.check(alice:HasText("Clear history (1)"), "History offers to clear everything finished")
    alice:FindButton("Clear history (1)"):Click()
    alice:FindButton("Sure?"):Click()
    world:advance(0.5)
    T.equal(A.Data.FinishedCount("history"), 0, "the history is empty")
    T.check(alice:HasText("Nothing has finished yet."), "and says so")

    -- the guild does not bring them back
    world:advance(700)
    T.check(A.Data.Get(farm.id) == nil and A.Data.Get(other.id) == nil, "cleared bounties are not fetched again from the guild")
    T.check(B.Data.Get(farm.id) ~= nil, "(Bob still has his copy)")

    for _, c in ipairs({ alice, bob }) do T.clean(c, c.name .. " has no errors") end
end
