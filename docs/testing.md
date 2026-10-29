# Testing Bounty Board in the game (two characters)

You need two characters **in the same guild**, logged in at the same time (two accounts/computers, or you and a
guildmate). Call them **Poster** and **Hunter**. Install with `deploy.ps1 BountyBoard -Tbc` (TBC client, Interface 20506).

Both characters should log in once with the addon enabled. The login sync starts 6–14 seconds after login.

## 1. Window and post
1. Poster: type `/bb`. The window opens with the tabs Board, My Bounties, My Jobs, History. Drag the title bar, close
   with the × or Esc, reopen with `/bb`: the position is remembered.
2. Poster: click **+ Post Bounty**. Shift-click an item in your bags (for example 20 Copper Bar). Set quantity 20,
   reward 1g 50s, deadline 3 days, a note. Click **Post**. You land on **My Bounties** and see the card.
3. Hunter: wait a few seconds, `/bb`. The card is on the **Board**.

## 2. Take the job and live progress
4. Hunter: click **Take Job**. The card now says "Taken by you"; **My Jobs** shows a badge (1) and the card with
   "Hunter  N/20 in bags".
5. Poster: a toast "Hunter took your bounty" appears at the top of the screen; the card shows Hunter's progress bar.
6. Hunter: pick up or drop a few of the items (loot, buy from the auction house, move to the bank). About a second
   later the number changes on Hunter's card, and on Poster's card within a few seconds. Poster sees a time like
   "· 5 min ago" next to numbers that are older than two minutes.

## 3. Trade verification
7. Hunter: trade Poster. Put the items in the trade (Hunter) and the gold (Poster, the reward), both accept.
   Do it in parts too (10 items first, then 10 items and the gold).
8. Poster: toasts "DELIVERY VERIFIED" and "PAYMENT VERIFIED"; the card turns to the **History** tab with PAID.
   Hunter: sees the same a moment later (confirmed by Poster's client); the bottom bar shows "1 jobs completed" for Hunter.
9. Cancel the trade at the last step once: nothing may be recorded.
10. Trade with a third guildmate who did not take the job: nothing may be recorded.

## 4. Cancel, expiry, sync
11. Poster: post another bounty, click **Cancel** (it asks "Sure?", click again). Hunter sees it cancelled
    (toast if Hunter had taken it).
12. Hunter: `/reload`, `/bb`. Everything is still there. Poster logs out, Hunter logs in: Hunter still sees Poster's
    bounties (stored locally) and a third guildmate who logs in gets them from Hunter.
13. `/bb sync` asks the guild again. `/bb settings` opens the settings (notifications, size, start tab, history length). `/bb debug` turns on debug lines in the chat (message traffic, progress).

## 5. What to look for
- Lua errors (the Allemano Hub Errors tab or BugSack).
- The window against the mockups in `mockups/` (spacing, text overflow, card height with notes and two takers).
- Taint/blocked-action warnings when shift-clicking items (should be none).
- That nothing is ever accepted or sent for you in the trade window.

The offline tests (`lua Tests/run.lua`) cover the logic with a fake game and several simulated players; they cannot
show how it looks or confirm the real trade events of the client.
