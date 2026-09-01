# OctoQuestTrash

Tells you when a quest item can be safely deleted — for WoW **vanilla 1.12**
(Turtle WoW / OctoWoW cores). Hover any bag item and get a verdict:

- **Can be deleted** — every quest that uses the item is completed
  (and none of them is repeatable or seasonal).
- **Keep — needed for an active quest** — it's wanted by a quest in your log.
- **Keep — a quest still wants this** — a quest you haven't done yet needs it.
- **Keep — repeatable/seasonal quest wants this** — permanent or recurring
  demand (turn-in farming, holiday quests). Never flagged deletable.
- **Probably deletable (custom quest)** — only completed Turtle/Octo custom
  quests reference it; whether those are repeatable can't be known from the
  database, so you get a hedge instead of a hard verdict.
- **No use to you** — only race/class-locked quests use it. Tradable items
  are never told "delete": they get "sell or AH it" wording instead.

Below the verdict, the tooltip lists the quests involved and their status.

`/oqt` (or `/questtrash`) scans your bags (and bank, when open) and prints
everything with a verdict, deletables first.

## Requirements

- **pfQuest** (with the Turtle database; on OctoWoW use pfQuest + pfQuest-octo).
  All quest data and completion history come from it.
- Optional: **Bagshui** — OctoQuestTrash registers a `SafeToDelete()` rule
  function, so you can make a bag category that corrals all the dead weight:
  rule expression `SafeToDelete()`.

## Setup

1. Install to `Interface\AddOns\OctoQuestTrash` (this repo's root is the
   addon folder — a git clone or the launcher's git-URL addon add works
   as-is).
2. In game, run **`/db query`** once per character. On Turtle-based cores
   this asks the server (`.queststatus`) for your full completed-quest list
   and backfills pfQuest's history — without it, quests finished before
   pfQuest was installed look "not done" and verdicts stay conservative.

## How it decides

An item→quest index is built from pfQuest's database: items that **start**
quests, items **collected** as objectives, and items **used on** targets.
Each linked quest is judged: in your log / completed (pfQuest history) /
repeatable (a shipped list of all 515 repeatable 1.12 quests, generated
from the vanilla world database, plus known Turtle customs) / seasonal
(pfQuest's event flag) / impossible for your race or class / not done yet.
The most protective state wins.

## Honest limits

- **Quest rewards are not in pfQuest's database**, so rewards (including
  keys and attunement items like the Drakefire Amulet) get no verdict.
  A built-in never-delete list guards the famous ones (Aqual/Eternal
  Quintessence, Scepter of Celebras, Seal of Ascension, dungeon keys)
  in case future databases add links.
- **Turtle/Octo custom repeatables** beyond the known list can slip
  through as "probably deletable" — hence the hedge, never a hard verdict.
- **pfQuest's history isn't perfect**: in rare cases an abandoned or
  server-removed quest can be recorded as completed. `/db query` rebuilds
  the history from the server and is the recommended source of truth.
- The addon only ever advises. Nothing is deleted automatically.

## License

MIT
