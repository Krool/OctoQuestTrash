# Maintaining OctoQuestTrash

Everything a future maintainer (human or agent) needs. The README covers
what the addon does; this file covers how it works and how to change it
safely.

## Architecture

Four Lua files, loaded in toc order:

| File | Role |
|---|---|
| `Repeatables.lua` | Generated set: quest ids repeatable on the cmangos 1.12 core OR the Turtle 1.18.1 core (740). Never treated as "done forever". |
| `Provided.lua` | Generated map: itemID to the quests whose accept hands you the item (`SrcItemId`, 854 items). pfQuest's db has no such concept. |
| `CustomKnown.lua` | Generated set: custom quests (id >= 40000) present in the preserved Turtle db (2428), i.e. their repeatability is known. |
| `OctoQuestTrash.lua` | All logic. |

At `PLAYER_ENTERING_WORLD` the addon builds an in-memory reverse index
from pfQuest's database plus `Provided.lua`:

```
index[itemID] = { {questID, role}, ... }
  role: "start" (item begins the quest)   <- pfDB quests[qid].start.I
        "obj"   (collect objective)       <- .obj.I
        "req"   (carried/used on target)  <- .obj.IR
        "prov"  (handed out on accept)    <- Provided.lua
```

Each linked quest resolves to a state, checked in this order (first hit
wins) in `QuestState()`:

1. `active` - in `pfQuest.questlog`
2. `repeat` - in `OctoQuestTrashRepeatable`
3. `event` - pfQuest db `event` field set (seasonal; servers reset these)
4. `done` / `customdone` - in `pfQuest_history`; customs absent from
   `CustomKnown` degrade to `customdone` (repeatability unknowable)
5. `never` - race/class bitmask says this character can never take it
6. `open` - none of the above

Item verdict = most protective state across all links
(`OQT.GetVerdict`): `active` > `farm` (any repeat/event) > `maybe` (any
open) > `custom` (any customdone) > `safe` (all done) > `notyours` (all
never). Items in the hardcoded `NEVER_DELETE` table short-circuit to
`keep`. Unlinked items of type Quest report `unknown`; anything else
gets no verdict at all.

Two guards sit on top of the verdict when rendering
(`VerdictLine`):

- **Type gate**: only items whose `GetItemInfo` type (5th return; the
  6th is subtype) is `Quest` ever get "Can be deleted". Tradable items
  get sell/AH wording. This is what protects class-locked mats and
  every Key-class item.
- **Honest reasons**: `notyours` says "race/class-locked", never
  "quest completed".

Display surfaces: wrappers around `GameTooltip.SetBagItem` and
`SetInventoryItem` (bank/equipped), the `/oqt` chat scan, and a Bagshui
rule function `SafeToDelete()` (fires on `safe` + `notyours`).

## Invariants (do not break these)

- **Never auto-delete anything.** The addon advises only.
- **A repeatable or seasonal link makes an item permanently un-deletable**
  no matter what the history says. Repeatables stay flagged "rewarded"
  server-side after the first turn-in, so history cannot distinguish
  "done once, still farming" from "done".
- **Tradable items never get delete wording.**
- **Unknown means keep.** Missing data, uncached items, OctoWoW-only
  custom quests: always fail toward keeping.
- 1.12 client = **Lua 5.0**: no `string.match`, no `#`, no varargs
  tricks; `table.getn`; event args arrive as globals (`event`, `arg1`).
  `luaparse` with the 5.1 grammar is the syntax checker (the client
  accepts that superset).

## Tests

```
cd tools/test
npm install
npm test
```

Three layers: luaparse syntax check of every shipped file, data-file
sanity (counts + sentinel ids, e.g. AV turn-in 7341 which the first
release famously missed), and behavior tests that execute the real
addon under fengari (Lua VM in Node) with a stubbed WoW/pfQuest
environment (`stubs.lua`). Add a fixture + `check(...)` line in
`test.lua` for every bug you fix. CI runs the same suite on every push
(`.github/workflows/test.yml`).

The suite cannot test: real client rendering, the pfQuest merge timing,
`/db query` server behavior. Those need an in-game smoke test: hover a
known repeatable turn-in item (expect blue "Keep"), hover a completed
one-time quest's leftover (expect red), run `/oqt`, run `/db query`.

## Updating the data files

Regenerate rather than hand-edit (generator docs: `tools/README.md`).
Sources of truth:

- **cmangos classic-db** (github.com/cmangos/classic-db): 1.12 quest
  flags, SrcItemId, item classes.
- **tortoise-wow** (github.com/Penqle/tortoise-wow): the preserved
  Turtle WoW 1.18.1 server db. Turtle's own database site is gone
  (NXDOMAIN since the 2026 shutdown); this is the surviving copy.
- OctoWoW-only quests exist in **neither**. They surface through
  pfQuest-octo's db and stay hedged via the `CustomKnown` mechanism.
  If OctoWoW publishes a db dump some day, extend `CustomKnown.lua`
  and `Repeatables.lua` from it.

Hand-edits that ARE appropriate: adding ids to `NEVER_DELETE` in
`OctoQuestTrash.lua` (keys/attunements), and appending
newly-discovered custom repeatables to the bottom section of
`Repeatables.lua` (keep the generated block pristine so a regeneration
can be diffed).

## Coupling to other addons

pfQuest internals read (verify after any pfQuest update):
`pfDB["quests"]["data"]` shape (`start.I/obj.I/obj.IR/event/race/class`),
`pfDB["quests"]["loc"]` (title `.T`), `pfQuest.questlog`,
`pfQuest_history` (numeric quest-id keys), `pfDatabase:GetBitByRace/Class`.
On OctoWoW, `/db query` comes from pfQuest-octo's patchtable.lua
(TWQUEST addon messages) and wholesale-replaces `pfQuest_history`.

Bagshui: only the public API (`Bagshui:AddRuleFunction`,
`Bagshui:QueueInventoryUpdate`), both guarded with nil checks. The
recategorize is gated on the history COUNT changing, not on raw
QUEST_LOG_UPDATE events.

## Known limitations (accepted, documented in README)

- Quest rewards are not in pfQuest's db; rewards get no verdict.
  `NEVER_DELETE` guards the famous keys in case a future db adds links.
- pfQuest's client-side history can rarely record an abandoned or
  server-removed quest as completed (its REMOVE-vs-abandon detection
  has races). `/db query` is the fix and the recommended source of
  truth.
- OctoWoW-only custom quests: hedged wording, never a hard verdict.
- The Repeatables union deliberately over-protects: ~105 quests are
  repeatable on stock 1.12 but one-time on Turtle (AQ turn-ins, some
  BG series). They read "Keep - repeatable" even where OctoWoW made
  them one-time. Wrong in the safe direction; leave it.

## Releasing

This repo IS the addon folder (toc at root), so the OctoLauncher
git-URL addon flow and a plain `git clone` into `Interface\AddOns`
both work. On the owner's machine `Interface\AddOns\OctoQuestTrash`
is this checkout and the launcher auto-updates it: **commit and push
every change or the next launch discards it**. Tag releases (`vN`)
when behavior changes; data-only regenerations can ride on main.
