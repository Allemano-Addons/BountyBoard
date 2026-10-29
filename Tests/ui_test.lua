-- The windows, built on a fake frame API: opening, posting with a shift-click, the cards, filters, taking, cancelling,
-- the toasts. Only the logic is tested here: how it looks has to be seen in the game.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    local bob = world:client("Bob", { ui = true })
    world:advance(20)
    local A, B = alice.BB, bob.BB
    local link = H.itemLink(12359)

    -- /bb opens and closes the window
    T.check(A.Main.Frame() == nil, "no window before it is asked for")
    alice:Slash("")
    T.check(A.Main.Frame() and A.Main.Frame():IsShown(), "/bb opens the window")
    T.check(alice.env.UISpecialFrames[1] == "AllemanoBountyBoardFrame", "Esc closes it")
    T.check(alice:HasText("Allemano Bounty Board"), "the title is shown")
    T.check(alice:HasText("Slakthuset"), "the guild is shown")
    for _, tab in ipairs({ "Board", "My Bounties", "My Jobs", "History" }) do
        T.check(alice:FindButton(tab) ~= nil, "tab " .. tab)
    end
    world:advance(0.5)
    T.check(alice:HasText("No open bounties yet"), "an empty board says so")
    T.check(alice:HasText("Not synced yet") or alice:HasText("Synced"), "the sync state is shown")
    alice:Slash("")
    T.check(not A.Main.Frame():IsShown(), "/bb closes it again")
    alice:Slash("")
    T.check(A.Main.Frame():IsShown(), "and opens it again")

    -- posting
    alice:FindButton("+ Post Bounty"):Click()
    local dialog = A.PostDialog.Frame()
    T.check(dialog and dialog:IsShown(), "+ Post Bounty opens the dialog")
    alice:FindButton("Post"):Click()
    T.check(dialog.error:GetText():find("Shift%-click"), "posting without an item says what is missing")
    T.equal(A.Data.OpenCount(), 0, "nothing was posted")

    T.equal(alice.bags[12359], nil, "the item is not in Alice's bags")
    alice.env.ChatEdit_InsertLink(link) -- a link of an item she does not have
    T.check(alice:HasText("[Thorium Bar]"), "a linked item shows in the slot, in the bags or not")
    dialog.qty:Type("20")
    dialog.gold:Type("1")
    dialog.silver:Type("50")
    dialog.note:Type("for my forge")
    alice:FindButton("Post"):Click()
    T.equal(A.Data.OpenCount(), 1, "the bounty is posted")
    local b
    for _, x in pairs(A.Data.All()) do b = x end
    T.equal(b.quantity, 20, "quantity")
    T.equal(b.reward, 15000, "1g 50s is 15000 copper")
    T.equal(b.note, "for my forge", "note")
    T.equal(b.itemID, 12359, "item")
    T.check(not dialog:IsShown(), "the dialog closes")
    world:advance(0.5)
    T.equal(A.Main.Tab(), "mine", "My Bounties is shown")
    T.equal(A.Board.CardCount(), 1, "one card")
    T.check(alice:HasText("20x Thorium Bar"), "the card shows quantity and name")
    T.check(alice:HasText("Cancel"), "the creator can cancel")

    -- a shift-click while chatting still goes to the chat
    alice:FindButton("+ Post Bounty"):Click()
    alice.chatBox = { GetText = function() return "hi" end }
    alice.env.ChatEdit_InsertLink(H.itemLink(2772))
    T.check(not alice:HasText("[Iron Ore]"), "a link meant for the chat box is not taken")
    alice.chatBox = nil
    A.PostDialog.Close()

    -- an item dropped from the cursor works too
    alice:FindButton("+ Post Bounty"):Click()
    alice:SetBag(2772, 3)
    alice.cursor = 2772
    dialog.slot:RunScript("OnReceiveDrag")
    T.check(alice:HasText("[Iron Ore]"), "an item dropped on the slot is taken")
    A.PostDialog.Close()

    -- the limit of five
    for _ = 1, 4 do A.Data.Post({ itemID = 2772, quantity = 1, reward = 1, days = 1, note = "" }) end
    T.check(A.Main.Frame().postButton.unavailable, "+ Post Bounty is switched off at five open bounties")
    T.check(A.Main.Frame().postButton.disabledTip:find("5 open"), "and says why when pointed at")
    A.PostDialog.Open()
    T.check(dialog.postButton.unavailable, "so is Post in the dialog")
    dialog.postButton:Click()
    T.equal(A.Data.OpenCount(), 5, "a switched-off Post does nothing")
    A.PostDialog.Close()
    -- (clean up: cancel the four fillers)
    for _, x in pairs(A.Data.All()) do
        if x.itemID == 2772 then A.Data.Cancel(x.id) end
    end

    -- Bob sees it on the board and takes it
    world:advance(5)
    bob:Slash("")
    T.equal(B.Main.Tab(), "board", "Bob starts on the board")
    world:advance(0.5)
    T.equal(B.Board.CardCount(), 1, "Bob sees one card")
    T.check(bob:HasText("Take Job"), "there is a Take Job button")
    T.check(bob:HasText("1g 50s 0c") or bob:HasText("0g 1s 50c") or bob:HasText("1g"), "the reward is shown")
    bob:SetBag(12359, 4)
    bob:FindButton("Take Job"):Click()
    world:advance(6)
    T.equal(#B.Data.Jobs(), 1, "Bob has a job")
    T.check(bob:HasText("Taken by you"), "the card says taken by you")
    T.check(not bob:HasText("Take Job"), "the button is gone")
    T.equal(B.Main.Frame().jobsBadge.text:GetText(), "1", "the My Jobs badge counts one")
    T.equal(B.Toast.Count() >= 1, true, "Bob gets a toast for taking the job")

    -- Alice is told
    T.check(A.Toast.Count() >= 1, "Alice gets a toast: Bob took the bounty")
    local told = false
    for _, text in ipairs(alice:Texts()) do if text:find("Bob took your bounty") then told = true end end
    T.check(told, "the toast says who")
    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    T.check(alice:HasText("|r  4/20 in bags"), "the card shows Bob's progress: " .. table.concat(alice:Texts(), " | "):sub(1, 400))

    -- My Jobs on Bob's side, progress shown
    bob:FindButton("My Jobs"):Click()
    world:advance(0.5)
    T.equal(B.Board.CardCount(), 1, "My Jobs has the card")
    T.check(bob:HasText("|r  4/20 in bags"), "Bob's own progress is shown")

    -- the board filter and search (only on the Board tab)
    bob:FindButton("Board"):Click()
    local search
    for _, f in ipairs(bob.frames) do
        if f.kind == "FontString" and f.text == "Search item or player" then search = f.parent end
    end
    T.check(search ~= nil, "there is a search box")
    search:Type("zzz")
    world:advance(0.5)
    T.equal(B.Board.CardCount(), 0, "a search with no match shows nothing")
    T.check(bob:HasText("No bounty matches"), "and says so")
    search:Type("thor")
    world:advance(0.5)
    T.equal(B.Board.CardCount(), 1, "a search for part of the name finds it")
    search:Type("alice")
    world:advance(0.5)
    T.equal(B.Board.CardCount(), 1, "a search for the creator finds it")
    search:Type("")
    world:advance(0.5)

    -- cancelling takes two clicks
    alice:FindButton("My Bounties"):Click()
    world:advance(0.5)
    alice:FindButton("Cancel"):Click()
    T.equal(b.status, "taken", "one click does not cancel")
    T.check(alice:HasText("Sure?"), "it asks again")
    alice:FindButton("Sure?"):Click()
    T.equal(b.status, "cancelled", "the second click cancels")
    world:advance(5)
    T.equal(B.Data.Get(b.id).status, "cancelled", "Bob sees the cancel")
    local cancelToast = false
    for _, text in ipairs(bob:Texts()) do if text:find("cancelled the bounty") then cancelToast = true end end
    T.check(cancelToast, "Bob gets a toast about the cancel")

    -- the history
    alice:FindButton("History"):Click()
    world:advance(0.5)
    T.equal(A.Board.CardCount(), 5, "the history has the bounty and the four cancelled fillers")
    T.check(alice:HasText("CANCELLED"), "with its outcome")
    T.check(not alice:HasText("Take Job"), "and no action buttons")

    -- the position is remembered
    A.Main.Frame():Hide()
    T.check(not A.Main.Frame():IsShown(), "the close button hides the window")

    -- slash commands
    alice:Slash("debug")
    T.equal(A.db.settings.debug, true, "/bb debug turns debug on")
    alice:Slash("debug")
    T.equal(A.db.settings.debug, false, "and off")
    alice:Slash("sync")
    alice:Slash("version")
    alice:Slash("help")
    T.clean(alice, "Alice has no errors")
    T.clean(bob, "Bob has no errors")
end
