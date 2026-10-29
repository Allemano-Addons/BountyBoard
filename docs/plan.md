# Allemano Bounty Board – plan

Status: idé/plan (2026-10-28). Ingen kod ännu – byggs av Patrick med Claude.

## Pitch
En uppdragstavla för guilden i spelet. Någon lägger ut ett jobb med belöning, någon tar det, betalning sker manuellt via trade/mail och addonet verifierar och bokför. Fyller luckan efter Venitras BountyBoard (CurseForge), som är övergivet inför WoW Forever eftersom det byggde på automatiserade trades.

## Grundprincip: läsa, aldrig agera
Addons får inte genomföra trades, skicka mail eller flytta guld utan att spelaren klickar själv (AcceptTrade, SendMail m.fl. kräver hardware event). Därför:
- Spelaren trejdar/mailar själv.
- Addonet LÄSER trade-fönstret och inkorgen och matchar mot öppna bounties.
- Ingen central bank, ingen personal, ingen server. Allt är peer-to-peer inom guilden.

## Bounty-typer
1. **Farm** – "20x Thorium Bar, 5g". Item + antal, kan delas upp på flera leverantörer.
2. **Craft** – "Lionheart Helm, egna mats, 2g tips". Kopplas till CraftBoard: visa vem i guilden som har receptet.
3. **Hjälp** – carry, elite-quest, summon. Fri text, bekräftas manuellt av båda.
4. **Kill-on-sight (PvP)** – "Gankarn-Pyrewood, 1g/kill". Kill verifieras via combat log (PARTY_KILL) hos den som tar jobbet; skickas som bevis till beställaren.
5. **Guildbounty** – lagt av officer, mål i totalt antal ("40x Greater Fire Protection Potion till MC"), många bidrar, progress-bar.

## Livscykel
Öppen → Tagen (låst till en eller flera) → Levererad (verifierad) → Betald (verifierad) → Stängd.
Även: Utgången (deadline), Avbruten (av beställare), Omtvistad.

## Verifiering
- **Trade:** TRADE_SHOW / TRADE_PLAYER_ITEM_CHANGED / TRADE_TARGET_ITEM_CHANGED / TRADE_ACCEPT_UPDATE, GetTradeTargetItemInfo, GetTradePlayerItemInfo, GetTargetTradeMoney/GetPlayerTradeMoney. Spara snapshot precis före accept; vid UI_INFO_MESSAGE "Trade complete" → matcha mot bounty.
- **Mail:** MAIL_INBOX_UPDATE + GetInboxHeaderInfo/GetInboxItem. Ämnesraden kan förifyllas med bounty-ID (t.ex. "[BB#123]") när spelaren öppnar sändfönstret via addonet – spelaren klickar Skicka själv.
- **Kill:** COMBAT_LOG_EVENT_UNFILTERED, subevent PARTY_KILL där källan är spelaren/gruppen och destName matchar målet.
- Båda parter signerar varje steg (litet meddelande), så historiken håller även om en part är offline.

## Synk
- C_ChatInfo.SendAddonMessage på GUILD-kanalen, prefix "AllemanoBB", ChatThrottleLib/AceComm-liknande chunking.
- Varje bounty har ID = skaparens namn + löpnummer + tidsstämpel. Senaste version vinner (version-räknare per bounty).
- Vid inloggning: be om "manifest" (ID + version), hämta bara det som saknas.
- SavedVariables per konto för historik och rykte.

## Live-progress (bags)
När någon tagit ett farm- eller guildbounty visas deras aktuella antal live för alla i guilden.
- Lyssna på BAG_UPDATE (debounce ~1 s), räkna med GetItemCount(itemID) för varje aktivt jobb.
- Skicka bara när siffran ändrats, max var 5–10 s per spelare (addon-meddelande "PROG", bountyID, antal, tidsstämpel).
- Kortet visar progressbar per tagare: "10/20 i väskan". Guildbounty summerar: "23/40 levererat · 8 till på väg".
- Offline/inaktiv: senaste siffran ligger kvar med ålder ("10/20 · 2 h sedan").
- Bank räknas bara om cachad/öppen; alts via AltBoard-integration (senare).
- Bara informativt: trade/mail-verifieringen avgör vad som faktiskt är levererat. Siffran kan sjunka om man säljer/använder items.

## Rykte & historik
- Antal klarade jobb, levererat i tid, avbrutna, tvister.
- Titlar: Lärling → Slaktare → Mästerslaktare (namnen kan temas per guild).
- Topplista i fönstret.
- Ledger-integration: alla betalningar loggas där.

## UI (LibAllemano-utseende)
- Huvudfönster med flikar: Tavla, Mina bounties, Mina jobb, Topplista, Historik.
- Tavlan som kort/lappar (passar Slaktlistan-känslan), filter per typ.
- "Lägg ut"-dialog: typ, item (shift-klicka in), antal, belöning (g/s/c), deadline, anteckning.
- Notiser via Hush (någon tog ditt jobb, leverans mottagen, betalning mottagen).
- Minimap-knapp + Hub-ingång.

## Integrationer
- **Hush** – notiser och snabb whisper till motparten.
- **Ledger** – bokföring av betalningar.
- **CraftBoard** – vem kan crafta, och direkt "lägg craft-bounty".
- **Hub** – ingång och gemensamma inställningar.
- **Discord/Slakthuset-sajten (senare)** – export-sträng eller via befintlig Discord-koppling, så öppna bounties postas i en kanal och syns på sajten.

## MVP (v0.1)
1. Farm-bounties: lägg ut, ta, avbryt, deadline.
2. Guild-synk via addon-meddelanden.
3. Trade-verifiering (items + guld).
4. Live-progress från väskorna (BAG_UPDATE + GetItemCount), synkat i guilden.
5. Enkel historik och räknare för klarade jobb.
6. Ett fönster i Allemano-stil.

## Senare
- v0.2: Mail-verifiering, Craft-typ + CraftBoard, Hush-notiser, Ledger.
- v0.3: Guildbounties med delleveranser, officersbehörighet per guild rank.
- v0.4: Kill-on-sight + combat log-verifiering, topplista/titlar.
- v0.5: Discord/sajt-export.

## Risker / öppna frågor
- Fusk: falska "levererad"-meddelanden – lös genom att båda parter måste signera, och trade-snapshot från båda sidor.
- Spam av bounties – max antal öppna per spelare, officer kan ta bort.
- Bara guild i v1, eller även cross-guild via egen kanal? (Förslag: bara guild först.)
- WoW Forever-API: verifiera att trade/mail-funktionerna ovan finns och beter sig som i Classic Era vid launch. Testa i TBC Classic-klienten under tiden.
- Namn: "Allemano Bounty Board" vs eget namn för att inte krocka med Venitras "BountyBoard" på CurseForge.
