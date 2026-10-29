-- Fonts from LibSharedMedia, a menu that scrolls, and the colours of the filter buttons.
local H = require("harness")

return function(T)
    local world = H.newWorld()
    local alice = world:client("Alice", { ui = true })
    world:advance(20)
    local A = alice.BB

    -- without LibSharedMedia: ours and the game's
    local plain = #A.Theme:FontOptions()
    T.equal(plain, 5, "five fonts without LibSharedMedia")

    -- with it: every font it has, sorted
    local fonts = {}
    for i = 1, 40 do fonts["Font " .. string.format("%02d", i)] = "Interface/AddOns/Other/Fonts/f" .. i .. ".ttf" end
    alice.lsm = {
        List = function() local t = {} for name in pairs(fonts) do t[#t + 1] = name end return t end,
        Fetch = function(_, _, name) return fonts[name] end,
    }
    local options = A.Theme:FontOptions()
    T.equal(#options, plain + 40, "the fonts of LibSharedMedia are added")
    T.equal(options[plain + 1].label, "Font 01", "sorted by name")
    T.equal(options[plain + 1].value, "lsm:Font 01", "and kept by name")

    A.Settings.Set("font", "lsm:Font 07")
    T.equal(A.Theme.fonts.regular, fonts["Font 07"], "a chosen shared font is used for everything")
    A.Settings.Set("font", "lsm:Gone")
    T.equal(A.Theme.fonts.regular, "Fonts" .. string.char(92) .. "FRIZQT__.TTF", "a font that is gone falls back to the game's")
    A.Settings.Set("font", "barlow")

    -- a long list scrolls
    A.Settings.Show()
    local dropdown
    for _, f in ipairs(alice.frames) do
        if f.kind == "Button" and rawget(f, "Set") and f.value == "barlow" then dropdown = f end
    end
    T.check(dropdown ~= nil, "the font dropdown exists")
    dropdown:Click()
    local function shown()
        local list = {}
        for _, f in ipairs(alice.frames) do
            if f.kind == "Button" and f.item and f:IsVisible() then list[#list + 1] = f end
        end
        return list
    end
    local buttons = shown()
    T.equal(#buttons, 14, "the menu shows 14 rows, not all 45")
    local first = buttons[1].text
    local menu = buttons[1].parent
    menu:RunScript("OnMouseWheel", -1)
    local after = shown()
    T.equal(#after, 14, "still 14 rows after scrolling")
    T.check(after[1].item.text ~= buttons[1].item.text or first ~= after[1].item.text, "the wheel moves the list")
    for _ = 1, 40 do menu:RunScript("OnMouseWheel", -1) end
    local last = shown()
    T.equal(last[#last].item.text, "Font 40", "the list reaches its end")
    for _ = 1, 40 do menu:RunScript("OnMouseWheel", 1) end
    T.equal(shown()[1].item.text, "Barlow", "and back to the start")
    for _ = 1, 40 do menu:RunScript("OnMouseWheel", -1) end
    local end_ = shown()
    end_[#end_]:Click()
    T.equal(A.db.settings.font, "lsm:Font 40", "a font far down the list can be chosen")

    -- the filter buttons have the colours of the kinds
    A.Main.Show()
    world:advance(0.5)
    local function colorOf(text)
        for _, f in ipairs(alice.frames) do
            if f.kind == "FontString" and f.text == text and f.color then return f.color end
        end
    end
    local kos, kc = colorOf("Kill on Sight"), { A.Theme:Color("typeKos") }
    T.check(kos and math.abs(kos[1] - kc[1]) < 0.01 and math.abs(kos[2] - kc[2]) < 0.01, "the Kill on Sight button has the kill colour")
    local all, dim = colorOf("All"), { A.Theme:Color("text") }
    T.check(all and math.abs(all[1] - dim[1]) < 0.01, "All is the selected one")
    A.Settings.Set("typeColors", false)
    local plain2, d = colorOf("Kill on Sight"), { A.Theme:Color("textDim") }
    T.check(plain2 and math.abs(plain2[1] - d[1]) < 0.01, "plain when colours are switched off")

    T.clean(alice, "no errors")
end
