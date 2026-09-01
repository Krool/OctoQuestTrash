# Changelog

## 1.1.0 - 2026-09-01

- Hardening: tooltip hooks, the Bagshui rule, the `/oqt` scan, and the
  login index build are wrapped in pcall. A future pfQuest data-shape
  change degrades to "no verdict line", never an error popup mid-hover.
- `## Version` field in the toc.
- Test suite (`tools/test`): syntax, data sanity, and behavior tests
  running the real addon Lua under a stubbed WoW environment; CI
  workflow runs it on every push.
- MAINTAINING.md, changelog, README rework, in-game screenshots.

## 2026-09-01 - verification pass

- `Repeatables.lua` regenerated as the union of the cmangos 1.12 and
  preserved Turtle 1.18.1 world databases: 740 quests. Closes 99
  missing 1.12 repeatables (all battleground turn-ins among them:
  AV heads/hooves, WSG marks, AB resource crates) and adds all 66
  item-linked Turtle custom repeatables (Fashion brackets, Hyjal
  Dream Shard economy, Arena marks) plus 51 classics Turtle made
  repeatable.
- New `Provided.lua`: 854 quest-provided items (`SrcItemId`), which
  pfQuest's database cannot see. Provided items are now guarded while
  their quest is active and judged with their chain.
- New `CustomKnown.lua`: the 2428 custom quests with known
  repeatability get hard verdicts; OctoWoW-only customs keep the
  hedged "probably deletable".
- Verified: the tradable/Key type gate catches all 19 Keys and 351
  tradable items in the worst-case sweep; pfQuest's vanilla data had
  zero true mismatches against cmangos in a 200-quest sample.

## 2026-08-31 - v1

- Initial release: item-to-quest index from pfQuest's db, verdict
  tooltips on bag items, `/oqt` scan, Bagshui `SafeToDelete()` rule,
  repeatable/seasonal/race-class/custom guards, tradable-item wording
  gate, never-delete key list.
