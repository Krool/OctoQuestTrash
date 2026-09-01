# Data generators

The addon's data files are generated, not hand-written. To regenerate:

1. `extract-sql.js` — parses `quest_template` + `item_template` from the
   cmangos classic 1.12 world dump (`classicmangos.sql` inside
   `classic-world-db.zip` from github.com/cmangos/classic-db releases)
   into `sqldb.json`.
2. Turtle side: clone github.com/Penqle/tortoise-wow (sparse:
   `sql/base/tw_world_quest_template.sql` + `sql/database_updates/world/`),
   apply base + migrations in filename order, emit `quests-effective.json`
   (`{ [questId]: { title, qf, sf } }` — `sf & 1` = repeatable).
3. `gen-data2.js` — reads both JSONs, writes `Repeatables.lua` (union of
   repeatable flags from both cores) and `CustomKnown.lua` (custom quests
   with known repeatability). `gen-data.js` is the earlier cmangos-only
   version, kept for reference; it also writes `Provided.lua` (SrcItemId →
   quest map).

Run with plain Node (no deps). Paths inside the scripts assume the JSONs
sit next to them.
