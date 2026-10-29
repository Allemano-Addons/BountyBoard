-- What the tests cannot see by running: the game runs Lua 5.1, so a function may use at most 60 outside variables
-- (upvalues) and 200 locals (checked with luac when it is next to the Lua that runs the tests), the code may not use
-- newer syntax, and the addon may never call a function that moves items or gold.
return function(T)
    local files = {}
    for line in io.lines("AllemanoBountyBoard.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    T.check(#files >= 10, "the TOC lists the files")

    local function read(path)
        local f = assert(io.open(path, "rb"))
        local text = f:read("a")
        f:close()
        return text
    end

    -- every .lua file of the addon is in the TOC (a forgotten file is silently missing in the game)
    local listed = {}
    for _, f in ipairs(files) do listed[f] = true end
    local pipe = io.popen(package.config:sub(1, 1) == "\\" and 'dir /b /s *.lua 2>nul' or 'find . -name "*.lua"')
    local cwd = (io.popen(package.config:sub(1, 1) == "\\" and "cd" or "pwd"):read("l") or ""):gsub("\\", "/")
    for path in pipe:lines() do
        path = path:gsub("\\", "/"):gsub("^%./", "")
        local rel = path:sub(1, #cwd + 1) == cwd .. "/" and path:sub(#cwd + 2) or path
        if not rel:find("^Tests/") and not rel:find("^%.") then
            T.check(listed[rel], rel .. " is listed in the TOC")
        end
    end
    pipe:close()

    for _, file in ipairs(files) do
        local source = read(file)
        local code = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "") -- without comments
        code = code:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")           -- and without strings

        T.check(not code:find("%f[%w_]goto%f[%W]"), file .. ": no goto (Lua 5.1)")
        T.check(not code:find("<const>") and not code:find("<close>"), file .. ": no attributes (Lua 5.1)")
        T.check(not code:find("%s//%s"), file .. ": no integer division (Lua 5.1)")
        T.check(not code:find("table%.unpack") and not code:find("math%.pow"), file .. ": 5.1 table and math functions")
        T.check(not code:find("%f[%w_]print%("), file .. ": no print (use BB:Debug)")

        -- the addon only reads: nothing that accepts a trade, sends mail or moves items or gold
        for _, name in ipairs({
            "AcceptTrade", "SendMail", "PickupPlayerMoney", "AddTradeMoney", "ClickTradeButton", "PickupTradeMoney",
            "UseContainerItem", "PickupContainerItem", "SplitContainerItem", "TakeInboxMoney", "TakeInboxItem",
            "InitiateTrade", "SetTradeMoney", "DepositGuildBankMoney", "SendChatMessage",
        }) do
            T.check(not code:find("%f[%w_]" .. name .. "%f[%W]"), file .. ": never calls " .. name)
        end
    end

    -- Lua 5.1 limits, when luac is at hand
    local interpreter = (arg and arg[-1]) or "lua"
    local dir = interpreter:match("^(.*)[/\\]")
    local luac = dir and (dir .. "/luac") or "luac"
    local windows = package.config:sub(1, 1) == "\\"
    local probe = io.open(luac .. ".exe", "rb") or io.open(luac, "rb")
    if not probe then
        local p = io.popen("luac -v 2>&1")
        local out = p and p:read("l") or ""
        if p then p:close() end
        if out:match("^Lua") then probe = { close = function() end } end
    end
    if not probe then
        print("(upvalue limits skipped: no luac next to " .. interpreter .. ")")
        return
    end
    probe:close()

    local worst = 0
    for _, file in ipairs(files) do
        local program = windows and luac:gsub("/", "\\") or luac
        local command = windows and ('""' .. program .. '" -l -l -p "' .. file .. '" 2>&1"') or ('"' .. program .. '" -l -l -p "' .. file .. '" 2>&1')
        local p = io.popen(command)
        local listing = p:read("a")
        p:close()
        local name, broken = nil, {}
        for text in listing:gmatch("[^\r\n]+") do
            local header = text:match("^function (<[^>]*>)") or text:match("^main (<[^>]*>)")
            if header then
                name = header
            elseif name then
                local upvalues, locals = tonumber(text:match("(%d+) upvalues")), tonumber(text:match("(%d+) locals"))
                if upvalues then
                    worst = math.max(worst, upvalues)
                    if upvalues > 60 then broken[#broken + 1] = name .. " uses " .. upvalues .. " upvalues" end
                    if locals and locals > 200 then broken[#broken + 1] = name .. " has " .. locals .. " locals" end
                    name = nil
                end
            end
        end
        T.check(#broken == 0, file .. " stays within the limits of Lua 5.1" .. (broken[1] and (": " .. table.concat(broken, "; ")) or ""))
    end
    T.check(worst > 0, "luac listed the functions (most outside variables: " .. worst .. ")")
end
