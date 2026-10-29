-- Craft bounties: like farm (the crafter trades the finished items for gold), plus who brings the materials.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true, money = 100000 })
    local bob = world:client("Bob", { ui = true, money = 0 })
    world:advance(20)
    local A, B = alice.BB, bob.BB
    local HELM = 13468

    local b = A.Data.Post({ type = "craft", itemID = HELM, quantity = 1, reward = 20000, days = 3, note = "Any enchant", mats = "creator" })
    T.check(b ~= nil, "a craft bounty is posted")
    T.equal(b.mats, "creator", "the creator brings the materials")
    local d = A.Data.Post({ type = "craft", itemID = HELM, quantity = 1, reward = 0, days = 3 })
    T.equal(d.mats, "crafter", "the crafter's own materials are the default")
    A.Data.Cancel(d.id)
    local _, err = A.Data.Post({ type = "craft", itemID = 0, quantity = 1, reward = 0, days = 1 })
    T.check(err ~= nil, "a craft bounty needs an item")
    local wire = A.Data.ToWire(b)
    T.equal(B.Data.FromWire(wire).mats, "creator", "the choice survives the wire")
    A.Comm.SendBounty(b, "high")
    world:advance(5)

    bob:Slash("")
    world:advance(0.5)
    T.check(bob:HasText("CRAFT") and bob:HasText("mats supplied"), "the card says CRAFT and who brings the mats")
    T.check(bob:HasText("Craft"), "and has a Craft button")
    for _, fr in ipairs(bob.frames) do -- the card's button, not the "Craft" filter
        if fr.kind == "FontString" and fr.text == "Craft" and fr.parent.kind == "Button" and not fr.parent.value and fr:IsVisible() then
            fr.parent:Click()
        end
    end
    world:advance(5)
    T.equal(A.Data.Get(b.id).status, "taken", "taken")

    -- the finished item for the gold
    bob:SetBag(HELM, 1)
    world:advance(10)
    T.equal(A.Data.TakerEntry(A.Data.Get(b.id), "Bob").progress, 1, "the finished item is counted in the bags")
    world:trade(alice, bob, { money = 20000 }, { items = { [HELM] = 1 } })
    world:advance(10)
    T.equal(A.Data.Get(b.id).status, "paid", "the trade completes it")
    T.equal(B.Data.Get(b.id).status, "paid", "Bob sees it complete")

    -- materials handed over in a trade are not mistaken for the result
    local c = A.Data.Post({ type = "craft", itemID = HELM, quantity = 1, reward = 100, days = 3, mats = "creator" })
    A.Comm.SendBounty(c, "high")
    world:advance(5)
    local entry = B.Data.Take(c.id)
    B.Comm.SendTake(B.Data.Get(c.id), entry)
    world:advance(5)
    alice:SetBag(2772, 10)
    world:trade(alice, bob, { items = { [2772] = 10 } }, {})
    world:advance(10)
    T.equal(A.Data.Get(c.id).deliveredQty or 0, 0, "giving the crafter materials delivers nothing")

    -- the dialog
    A.Main.Show()
    alice:FindButton("+ Post Bounty"):Click()
    local dialog = A.PostDialog.Frame()
    dialog.typeBox:Set("craft")
    dialog.typeBox.scripts.OnClick(dialog.typeBox, "LeftButton")
    for _, fr in ipairs(alice.frames) do
        if fr.kind == "Button" and fr.item and fr.item.text == "Craft" and fr:IsVisible() then fr:Click() end
    end
    T.check(dialog.matsButton:IsShown() and dialog.slot:IsShown(), "the dialog asks for an item and who brings the materials")
    T.check(alice:HasText("Item to craft") and alice:HasText("The crafter uses their own materials"), "with the right texts")
    dialog.matsButton:Click()
    alice.env.ChatEdit_InsertLink(H.itemLink(HELM))
    dialog.gold:Type("2")
    alice:FindButton("Post"):Click()
    local posted
    for _, x in pairs(A.Data.All()) do
        if x.type == "craft" and x.reward == 20000 and x.id ~= b.id and x.id ~= c.id and x.mats then posted = x end
    end
    T.check(posted and posted.mats == "creator", "unticking the box means the creator brings the materials")

    for _, cl in ipairs({ alice, bob }) do T.clean(cl, cl.name .. " has no errors") end
end
