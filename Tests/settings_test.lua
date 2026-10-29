-- The settings window and what each setting does.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    local bob = world:client("Bob", { ui = true })
    world:advance(20)
    local A, B = alice.BB, bob.BB

    -- defaults
    local s = A.db.settings
    T.check(s.toasts and s.toastTaken and s.toastDelivery and s.toastPayment and s.soundChoice == "toast", "notifications are on by default")
    T.equal(s.scale, 1, "full size by default")
    T.equal(s.defaultTab, "board", "opens on the board")
    T.equal(s.historyDays, 30, "history is kept 30 days")

    -- the window
    alice:Slash("settings")
    T.check(A.Settings.Frame() and A.Settings.Frame():IsShown(), "/bb settings opens the settings")
    T.check(alice:HasText("NOTIFICATIONS") and alice:HasText("WINDOW"), "with its two sections")
    local box = alice:FindButton("Show notifications")
    T.check(box ~= nil, "a checkbox for notifications")
    box:Click()
    T.equal(A.db.settings.toasts, false, "clicking the checkbox turns it off")
    box:Click()
    T.equal(A.db.settings.toasts, true, "and on")
    alice:Slash("settings")
    T.check(not A.Settings.Frame():IsShown(), "/bb settings again closes it")

    -- notifications
    local function bountyFor(owner, taker)
        local b = owner.BB.Data.Post({ itemID = 12359, quantity = 5, reward = 100, days = 1, note = "" })
        owner.BB.Comm.SendBounty(b, "high")
        world:advance(5)
        return b
    end
    local function takeIt(b)
        world:advance(15) -- earlier toasts fade out
        local entry = B.Data.Take(b.id)
        B.Comm.SendTake(B.Data.Get(b.id), entry)
        world:advance(5)
    end
    alice.BB.Main.Show()
    local before = 0
    takeIt(bountyFor(alice))
    T.check(A.Toast.Count() > before, "a toast shows when somebody takes the bounty")

    A.Settings.Set("toastTaken", false)
    before = 0
    takeIt(bountyFor(alice))
    T.equal(A.Toast.Count(), before, "no toast when that kind is off")
    A.Settings.Set("toastTaken", true)

    A.Settings.Set("toasts", false)
    before = 0
    takeIt(bountyFor(alice))
    T.equal(A.Toast.Count(), before, "no toast at all when notifications are off")
    A.Settings.Set("toasts", true)

    local played = 0
    alice.env.PlaySound = function() played = played + 1 end
    takeIt(bountyFor(alice))
    T.equal(played, 1, "a sound plays with a toast")
    A.Settings.Set("soundChoice", "none")
    takeIt(bountyFor(alice))
    T.equal(played, 1, "and not when the sound is off")

    -- the window
    A.Settings.Set("scale", 0.8)
    T.equal(A.Main.Frame():GetScale(), 0.8, "the size setting scales the window")
    A.Settings.Set("scale", 1)
    T.equal(A.Main.Frame():GetScale(), 1, "and back")

    A.Main.ShowTab("history")
    A.Settings.Set("defaultTab", "jobs")
    local carl = world:client("Carl", { ui = true })
    carl.BB.db.settings.defaultTab = "jobs"
    carl:Slash("")
    T.equal(carl.BB.Main.Tab(), "jobs", "the window opens on the chosen tab")
    local dora = world:client("Dora", { ui = true })
    dora.BB.db.settings.defaultTab = "last"
    dora.BB.db.settings.lastTab = "history"
    dora:Slash("")
    T.equal(dora.BB.Main.Tab(), "history", "'last used' opens on the tab used last")

    A.Main.Frame():SetPoint("CENTER")
    A.db.settings.window = { point = "TOP", relPoint = "TOP", x = 5, y = 5 }
    A.Settings.Show()
    alice:FindButton("Reset window position"):Click()
    T.check(next(A.db.settings.window) == nil, "the position is reset")

    -- fonts and text size
    local Theme = A.Theme
    T.equal(Theme.fonts.regular:find("Barlow") ~= nil, true, "Barlow is the default font")
    A.Settings.Set("font", "arialn")
    T.equal(Theme.fonts.regular, "Fonts\\ARIALN.TTF", "a game font replaces Barlow everywhere")
    T.equal(Theme.fonts.heading, "Fonts\\ARIALN.TTF", "also for headings")
    A.Settings.Set("font", "barlow")
    T.check(Theme.fonts.regular:find("Barlow") ~= nil, "and back to Barlow")
    T.equal(Theme:TextSize(0), 12, "medium text is 12")
    A.Settings.Set("textSize", "L")
    T.equal(Theme:TextSize(0), 14, "large text is 14")
    A.Settings.Set("textSize", "S")
    T.equal(Theme:TextSize(1), 12, "small text is 11, a step up is 12")
    A.Settings.Set("textSize", "M")
    A.Settings.Show()
    T.check(alice:HasText("Font") and alice:HasText("Text size"), "the settings window has the font choices")

    -- history length
    for _, b in pairs(A.Data.All()) do
        if A.Data.IsActive(b) then A.Data.Cancel(b.id) end
    end
    local old = A.Data.Post({ itemID = 2772, quantity = 1, reward = 0, days = 1, note = "" })
    A.Data.Cancel(old.id)
    old.finishedAt = world.now - 10 * 86400
    T.check(A.Data.Get(old.id) ~= nil, "a 10 day old entry is still in the history after 30 days' setting")
    A.Settings.Set("historyDays", 7)
    T.check(A.Data.Get(old.id) == nil, "a shorter history removes it at once")

    for _, c in ipairs({ alice, bob, carl, dora }) do T.clean(c, c.name .. " has no errors") end
end
