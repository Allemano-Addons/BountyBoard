# Allemano Bounty Board — CurseForge description

## Summary (the short one, for the "Summary" field; max 200 characters)

A job board for your guild: post a bounty with a reward, a guildmate takes it, and the addon reads the trade to check that the items and the gold really changed hands. Farm, Craft, Help, Kill on Sight, Guild goals.

## Description (the long one)

**Post a bounty. Someone takes it. Everyone gets paid.**

Allemano Bounty Board is a job board for your guild. Ask for 20 Thorium Bars, a Lionheart Helm, a tank for Scholomance, or a price on the head of a ganker, with a reward attached. Guildmates see it on the board, take the job and deliver by trade. The addon **reads the trade window** and marks the bounty delivered and paid when the items and the gold have really changed hands.

> **Early build (0.1.0).** Everything below works in testing. Mail verification, a leaderboard and a crafter lookup with CraftBoard are planned, not built.

### Five kinds of bounty

Each kind has its own colour on the board.

- **Farm.** An item and a quantity, and a reward. Hunters see how much you still need. You can take it in parts, from several players.
- **Craft.** An item to craft. You choose whether the crafter uses their own materials (the default) or you supply them. The finished items are traded for the gold.
- **Help.** No item, just a few words: a carry, an elite quest, a summon, a tank. The helper says "I helped", you confirm, and the reward is paid by trade.
- **Kill on Sight.** A player name and a number of kills. The hunter's addon counts kills of that player by the hunter or the group. You see the count and confirm. If you like, kills of open hunts are counted without having to press Hunt first (it can be switched off).
- **Guild goal.** A shared goal set by an officer: "40 Greater Fire Protection Potion for Molten Core". Everybody contributes by trade to the recipient, one progress bar shows how far the guild has come, and the reward is paid for every item. You choose which guild ranks may post them.

### How a bounty goes

1. **Post it.** Shift-click an item (or write a few words), set the reward in gold, silver and copper, and a deadline of 1, 3 or 7 days. You can have five open bounties at a time.
2. **Someone takes it.** The board shows who, and how far they have come: "10/20 in bags", updated live as their bags change.
3. **Trade.** The hunter trades you the items, you trade the gold. The addon reads the trade window and marks the bounty **delivered** and **paid**. Only the creator's client can mark a bounty paid, so a hunter cannot pay themselves.
4. **Done.** It moves to your history, and the hunter's completed-jobs counter goes up.

**The addon only reads.** It never accepts a trade, sends mail or moves an item or any gold for you. You trade as usual.

### On the screen

- **Board, My Bounties, My Jobs and History** tabs, with filters by kind and a search box.
- **Notifications** at the top of the screen when someone takes your bounty or a delivery or payment is verified, with a sound of your choice.
- **A launcher button**, like the other Allemano addons, that you can place anywhere.
- **Settings** (`/bb settings`): which notifications, the sound, window size, which tab opens first, how long the history is kept, which guild ranks may post guild goals, and the font and text size. Fonts from LibSharedMedia show up in the list if you have it.
- Names in the class colours of your guild.

### In the guild

Everything is peer to peer over the guild addon channel. There is no server, no website account and nothing to set up. When you log in the addon catches up with what the guild has. A bounty that its creator posted while you were offline is waiting for you, and your own bounties are kept between sessions.

### Commands

- `/bb` or `/bounty` opens the board.
- `/bb settings` opens the settings. `/bb button` shows or hides the launcher button.
- `/bb sync` asks the guild for bounties again. `/bb debug` turns debug lines on and off, `/bb errors` lists Lua errors the addon caught.

### Good to know

- Made for **WoW Forever** (interface 16001). Everybody who should see bounties needs the addon. A development build for the TBC Classic client is included.
- It is built on trust within the guild: messages are not signed, so a guildmate who modifies the addon could send false ones. It is meant for guilds that know each other.
- No data leaves the game. The addon sends nothing to any website.
- Designed, directed and tested by Allemano, with AI assistance (Claude) for much of the code. See `CREDITS.md`.

Part of **Allemano Addons**. Source code and issues: https://github.com/Allemano-Addons/BountyBoard · Guides and changelog: https://allemano.org · Discord: https://discord.gg/BvFrTKUAst

*World of Warcraft is a trademark of Blizzard Entertainment, Inc. Not affiliated with or endorsed by Blizzard Entertainment.*
