std = "lua51"
max_line_length = false
self = false
exclude_files = { "Media/**", "Tests/**" }

-- The only globals Bounty Board may write.
globals = {
    "AllemanoBountyBoardDB",
    "SLASH_ALLEMANOBB1", "SLASH_ALLEMANOBB2",
    "SlashCmdList",
}

-- WoW API used by Bounty Board (read-only). Extend as new APIs are used.
read_globals = {
    "issecretvalue", "UISpecialFrames",
    "strlower", "tinsert", "tremove", "strjoin", "tostringall", "wipe", "format", "geterrorhandler", "hooksecurefunc",

    -- Frames and UI
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "GameTooltip", "PlaySound", "GetCursorPosition", "GetCursorInfo", "ClearCursor",
    "IsMouseButtonDown", "ChatEdit_InsertLink", "ChatEdit_GetActiveWindow", "ChatFrameUtil", "HandleModifiedItemClick", "ITEM_QUALITY_COLORS",
    "TradeFrameRecipientNameText", "ERR_TRADE_COMPLETE",

    -- Game info
    "GetTime", "GetServerTime", "GetAddOnMetadata", "C_AddOns", "C_Timer", "C_ChatInfo", "C_Item", "C_Container",
    "GetPhysicalScreenSize", "UnitName", "GetRealmName", "GetNormalizedRealmName", "GetGuildInfo", "IsInGuild",
    "GetItemInfo", "GetItemCount", "Minimap", "LibStub", "SOUNDKIT", "CombatLogGetCurrentEventInfo", "UnitClass", "GetNumGuildMembers", "GetGuildRosterInfo", "C_GuildInfo", "RAID_CLASS_COLORS", "GetCoinTextureString", "GetMoney",
    "SendAddonMessage", "RegisterAddonMessagePrefix",

    -- Trade (read only)
    "GetTradePlayerItemInfo", "GetTradePlayerItemLink", "GetTradeTargetItemInfo", "GetTradeTargetItemLink",
    "GetPlayerTradeMoney", "GetTargetTradeMoney",
}
