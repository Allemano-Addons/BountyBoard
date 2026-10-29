# Wire protocol (prefix `AllemanoBB`, channel GUILD)

A message: `<protocol>|<kind>|<id>|<part>/<parts>|<data>`

- protocol: `1`. Messages with another number are ignored.
- kind: `N` new bounty, `U` updated bounty, `T` take, `C` cancel, `P` progress, `M` manifest, `R` request.
- id: random token that ties the parts of one message together. part/parts: 1/1 for a short message.
- data: `key=value;key=value`, values percent-escaped. At most 200 characters per message (the game allows 255 for
  prefix, header and data together); a longer message is cut in up to 12 parts and put together by the receiver.

Bounty fields (N, U): `i` id, `c` creator, `y` type, `m` item id, `q` quantity, `r` reward (copper), `d` deadline,
`n` note, `s` status, `v` version, `t` created, `dq` delivered quantity, `pc` paid copper,
`rc` recipient (guild goals), `mt` who brings the materials (craft: crafter or creator), `cl` class of the creator, `fa` finished at, `ti` title (help bounties; `m` is 0), `k` takers (`name:progress:updatedAt:delivered:paid`, comma separated).

- T: `i` id, `w` the taker (must be the sender), `t` time, `p` count in bags.
- C: `i` id, `v` new version. Accepted only from the creator.
- A: `i`, `w` (the sender), `t` — a taker gives the job back (the entry gets a `left` marker, a 6th field `:1` in `k`).
- P: `i`, `w` (the sender), `p` count, `t` time, `dl` claimed delivered, `pd` claimed paid.
- M: `e` list of `id:version`. Whoever has a newer version (or has what the sender lacks) offers it after a random wait,
  and stays quiet when somebody else sent it first. R: `e` list of ids the sender wants.

Rules: the highest `v` of a bounty wins and replaces the creator's fields; takers are merged entry by entry (the newer
`updatedAt` wins; delivered and paid never go down); a player's own taker entry is never overwritten by others. Only
the creator's client raises a bounty to delivered or paid. Bounties expire locally at their deadline (same server time
everywhere), so nothing is sent. Sending is queued at about three messages a second; a refused send is retried.

There is no signature: a guildmate who modifies the addon can forge messages. The guild is trusted (see README).
