# OctoQuestTrash

**Know which quest items you can safely delete.** For WoW vanilla 1.12
clients on Turtle WoW / OctoWoW cores.

Quest items pile up: gray-text fodder from finished quests, starter notes
you already handed in, halves of chains you abandoned at level 20. The
client never tells you which of them still matter. This addon does, right
on the tooltip.

## Screenshots

<!-- screenshots go in screenshots/; suggested captures:
     tooltip-deletable.png  - red "Can be deleted" on a finished quest's leftover
     tooltip-repeatable.png - blue "Keep" on a scourgestone/turn-in item
     oqt-scan.png           - /oqt output in the chat frame
     bagshui-category.png   - a Bagshui category using SafeToDelete()  -->

*(screenshots coming soon)*

## What you see

Hover any bag, bank, or equipped item:

| Verdict | Meaning |
|---|---|
| **Can be deleted** (red) | Every quest that uses the item is completed, none of them repeatable or seasonal. |
| **Keep - needed for an active quest** (green) | A quest in your log wants it. |
| **Keep - a quest still wants this** (yellow) | A quest you have not done yet needs it. |
| **Keep - repeatable/seasonal quest wants this** (blue) | Permanent or recurring demand: turn-in farming, holiday quests. Never flagged deletable. |
| **Probably deletable** (orange) | Only completed server-custom quests reference it and their repeatability is not knowable. Hedge, not a verdict. |
| **No use to you** | Only race/class-locked quests use it. Stated honestly, not disguised as "completed". |
| **No quest data - keep to be safe** (gray) | Quest-type item the database has no link for. |

Tradable items are **never** told "delete". If the item has market value
(cloth, herbs, class-locked drops), the strongest advice you get is
"sell or AH it". Below the verdict, the tooltip lists the quests
involved and each one's status.

`/oqt` (or `/questtrash`) scans your bags, and the bank when it is open,
and prints everything with a verdict, deletables first.

## Install

Requires **pfQuest** (on OctoWoW: pfQuest + pfQuest-octo). All quest
data and completion history come from it.

- **OctoLauncher**: add this repo's git URL as an addon.
- **Manual**: clone or download so the folder is
  `Interface\AddOns\OctoQuestTrash` (this repo's root is the addon
  folder).

Then, in game, run **`/db query`** once per character. On Turtle-based
cores this fetches your full completed-quest list from the server and
backfills pfQuest's history. Without it, quests finished before pfQuest
was installed look "not done" and verdicts stay conservative. The addon
reminds you at login if history is empty.

Optional: with **Bagshui** installed, the addon registers a
`SafeToDelete()` rule function. Create a category with that rule and all
the dead weight gathers in one corner of your bags.

## How it decides

An item-to-quest index is built from pfQuest's database (items that
start quests, collect objectives, carry/use items) plus a shipped table
of quest-provided items that pfQuest cannot see. Each linked quest is
judged: in your log, completed, repeatable, seasonal, impossible for
your race/class, or not done yet. The most protective state wins.

The repeatable set is the union of every repeatable quest in **both**
the cmangos 1.12 world database and the preserved Turtle WoW 1.18.1
database (740 quests, including all 66 item-linked Turtle custom
repeatables). Repeatable on either core means never flagged deletable.
This matters because servers remember your first turn-in forever, so
"completed" alone would condemn every scourgestone, power crystal, and
battleground token in your bags.

## Honest limits

- Quest **rewards** are not in pfQuest's database, so rewards (keys,
  attunement items like the Drakefire Amulet) get no verdict. A
  built-in never-delete list guards the famous ones anyway.
- **OctoWoW-only custom quests** exist in no public database; their
  items are hedged as "probably deletable", never a hard verdict.
- pfQuest's client-side history can rarely mislabel an abandoned quest
  as completed. `/db query` rebuilds from the server and is the source
  of truth.
- The addon only ever advises. Nothing is deleted automatically, and
  everything unknown fails toward "keep".

## Development

`MAINTAINING.md` covers the architecture, invariants, and data
regeneration. Tests (`cd tools/test && npm install && npm test`) run
the real addon Lua under a stubbed WoW environment and validate the
generated data; CI runs them on every push.

Data credits: [pfQuest](https://github.com/shagu/pfQuest) (Shagu),
[cmangos classic-db](https://github.com/cmangos/classic-db),
[tortoise-wow](https://github.com/Penqle/tortoise-wow) (Turtle 1.18.1
preservation), and [QuestTips](https://github.com/entrail/QuestTips)
for proving the concept on Classic Era.

MIT licensed.
