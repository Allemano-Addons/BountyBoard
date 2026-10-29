# Allemano Bounty Board

A guild job board for WoW Classic. A guildmate posts a **bounty** ("20x Thorium Bar, 5g, within 3 days"), another
guildmate **takes the job**, brings the items, and the addon checks the trade and marks the bounty delivered and paid.
Part of the Allemano Addons family. Commands: `/bb` or `/bounty`.

Status: **0.1.2-beta, the first release.** Made for WoW Forever (Interface 16001); a TBC Classic build (Interface 20506) is included for testing.

## What it does
- **Board**: every open bounty of your guild as cards (item, quantity, reward, creator, time left, progress). Filter
  by type (only *Farm* exists so far) and search by item, creator or note.
- **Post Bounty**: shift-click an item, set quantity, reward (gold/silver/copper), deadline (1, 3 or 7 days) and a note.
  At most 5 open bounties per player.
- **Take Job**: the creator and everybody else sees who took it. Your bag count of the item is shown live
  ("10/20 in bags") and shared with the guild (at most one message per bounty every 5 seconds).
- **Trade verification**: when a creator and a taker trade, the creator's client reads the trade window and marks the
  bounty *delivered* and/or *paid*. The taker's client records its side as a claim; only the creator's client can make
  a bounty *paid*.
- **My Bounties / My Jobs / History**, toasts ("Bearhug took your bounty", "Delivery verified"), a jobs-completed
  counter.

The addon is **read-only**: it never accepts a trade, sends mail or moves an item or gold.

## How it talks
Guild addon messages with the prefix `AllemanoBB` (`docs/protocol.md`). Every client keeps its own copy; the highest
version of a bounty wins and takers are merged. At login every client sends a short list of what it knows and the
others fill the gaps.

## Files
`Core.lua` (events, client differences), `Data.lua` (model, saved data), `Comm.lua` (guild messages),
`Progress.lua` (bag counting), `Trade.lua` (trade verification), `UI/` (theme, widgets, board, post dialog, toasts, window).
Tests: `lua Tests/run.lua` (offline, a fake game with several players). Guide for testing in the game:
`docs/testing.md`.

## Other clients
Everything that differs between game clients is in `Core.lua` (`BB.Compat`) and the TOC. A WoW Forever version is a
new TOC file plus, at most, changes in that one file.

All Rights Reserved. See `CREDITS.md`.
