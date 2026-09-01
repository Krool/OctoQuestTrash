// Regenerate OctoQuestTrash data files from the cmangos classic-db extract.
const fs = require("fs");
const path = require("path");
const db = require(path.join(__dirname, "sqldb.json"));

// ---- Repeatables.lua: every quest with SpecialFlags & 1
const rep = [];
for (const qid in db.quests) {
  if (db.quests[qid].sf & 1) rep.push(parseInt(qid, 10));
}
rep.sort((a, b) => a - b);
console.log("repeatable quests (SpecialFlags&1):", rep.length);

const repLines = [];
for (let i = 0; i < rep.length; i += 15) {
  repLines.push("  " + rep.slice(i, i + 15).map((id) => "[" + id + "]=1").join(",") + ",");
}

const repFile = [
  "-- OctoQuestTrash repeatable-quest set.",
  "-- GENERATED from the cmangos classic-db 1.12 world database",
  "-- (github.com/cmangos/classic-db, quest_template.SpecialFlags & 1)",
  "-- via scratchpad gen-data.js. " + rep.length + " quests. A quest in this",
  "-- set is NEVER treated as done forever: its items keep their value",
  "-- after first completion (repeatable turn-in farming).",
  "OctoQuestTrashRepeatable = {",
  repLines.join("\n"),
  "  -- Turtle/OctoWoW custom repeatables (not in any 1.12 db; best-effort):",
  "  [41069]=1,           -- Black Lotus Collection",
  "  [40221]=1,           -- Argent Dawn valor token (turtle variant)",
  "  [60030]=1,           -- Fashion Demands Sacrifices (per-bracket coin turn-in)",
  "}",
  "",
].join("\n");
fs.writeFileSync(path.join(__dirname, "Repeatables.lua"), repFile);

// sanity: BG turn-ins from the gap list must now be present
const must = [7341, 7342, 7361, 7381, 7421, 7788, 7871, 7886, 7921, 8081, 8290, 8529, 8614, 16, 308, 3861];
const repSet = {};
rep.forEach((id) => (repSet[id] = 1));
const miss = must.filter((id) => !repSet[id]);
console.log(miss.length ? "STILL MISSING: " + miss.join(",") : "gap-list sanity: all present");

// ---- Provided.lua: itemID -> providing quest ids (SrcItemId)
const prov = {}; // itemId -> [qid,...]
for (const qid in db.quests) {
  const src = db.quests[qid].src;
  if (src && src > 0) {
    if (!prov[src]) prov[src] = [];
    prov[src].push(parseInt(qid, 10));
  }
}
const provItems = Object.keys(prov).map(Number).sort((a, b) => a - b);
console.log("provided items (SrcItemId):", provItems.length);

const provLines = provItems.map((iid) => {
  const it = db.items[iid];
  const name = it && it.name ? String(it.name).replace(/[\r\n]/g, " ") : "?";
  return "  [" + iid + "] = {" + prov[iid].sort((a, b) => a - b).join(",") + "}, -- " + name;
});

const provFile = [
  "-- OctoQuestTrash quest-provided item map: itemID -> quests whose accept",
  "-- hands you the item (quest_template.SrcItemId). GENERATED from the",
  "-- cmangos classic-db 1.12 world database via scratchpad gen-data.js.",
  "-- pfQuest's db has no SrcItemId concept, so without this table a",
  "-- provided item is invisible (or worse, judged only by OTHER quests",
  "-- that reference it). " + provItems.length + " items.",
  "OctoQuestTrashProvided = {",
  provLines.join("\n"),
  "}",
  "",
].join("\n");
fs.writeFileSync(path.join(__dirname, "Provided.lua"), provFile);

// spot-check the audit's examples
[8523, 5462, 15885, 22047, 18597, 18598].forEach((iid) => {
  console.log("prov[" + iid + "] =", prov[iid] ? prov[iid].join(",") : "MISSING");
});
