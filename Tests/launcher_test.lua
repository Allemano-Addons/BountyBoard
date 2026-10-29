-- The launcher button.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    world:advance(20)
    local A = alice.BB
    local button = A.Launcher.button

    T.check(button ~= nil and button:IsShown(), "the button is there after login")
    button:Click()
    T.check(A.Main.Frame() and A.Main.Frame():IsShown(), "a click opens the board")
    button:Click()
    T.check(not A.Main.Frame():IsShown(), "and the next closes it")
    button.scripts.OnClick(button, "RightButton")
    T.check(A.Settings.Frame() and A.Settings.Frame():IsShown(), "a right click opens the settings")

    alice:Slash("button")
    T.check(not button:IsShown() and A.db.settings.launcherShown == false, "/bb button hides it")
    alice:Slash("button")
    T.check(button:IsShown(), "and shows it again")
    A.Settings.Set("launcherShown", false)
    T.check(not button:IsShown(), "the setting hides it")
    A.Settings.Set("launcherShown", true)

    -- the frame lights up under the mouse
    local lines = {}
    button.border.SetColor = function(_, r, g, b) lines[#lines + 1] = { r, g, b } end
    button.scripts.OnEnter(button)
    local accent = { A.Theme:Accent() }
    T.check(lines[1] and math.abs(lines[1][1] - accent[1]) < 0.01, "the frame turns to the accent on mouse over")
    button.scripts.OnLeave(button)
    local line = { A.Theme:Color("line") }
    T.check(lines[2] and math.abs(lines[2][1] - line[1]) < 0.01, "and back when the mouse leaves")

    -- it stays where it is dropped
    button.scripts.OnDragStop(button)
    T.check(A.db.settings.button ~= nil and A.db.settings.button.point ~= nil, "the position is saved")

    T.clean(alice, "no errors")
end
