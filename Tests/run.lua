-- Runs every offline test. From the addon folder:  lua Tests/run.lua
package.path = "./Tests/?.lua;" .. package.path
local H = require("harness")

local FILES = { "data_test", "comm_test", "sync_test", "progress_test", "trade_test", "ui_test", "leave_test", "settings_test", "look_test", "help_test", "kos_test", "guild_test", "craft_test", "tidy_test", "fonts_test", "launcher_test", "names_test", "limits_test" }

local ok, bad = 0, 0
for _, name in ipairs(FILES) do
    local T = H.newT(name)
    local loaded, err = pcall(function() require(name)(T) end)
    if not loaded then
        T.bad = T.bad + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
    print(string.format("%-16s %4d ok, %d failed", name, T.ok, T.bad))
    ok, bad = ok + T.ok, bad + T.bad
end

print(string.format("%d checks, %d failed", ok + bad, bad))
os.exit(bad == 0 and 0 or 1)
