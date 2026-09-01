// Regenerate Repeatables.lua as the UNION of cmangos 1.12 and Turtle
// (tortoise-wow preservation) repeatable flags, and emit CustomKnown.lua
// (custom quests whose repeatability IS known, so the hedge can relax).
const fs = require("fs");
const path = require("path");
const cm = require(path.join(__dirname, "sqldb.json")); // cmangos 1.12
const tw = require(path.join(__dirname, "quests-effective.json")); // turtle effective

const rep = {};
let nCm = 0, nTw = 0;
for (const qid in cm.quests) if (cm.quests[qid].sf & 1) { rep[qid] = 1; nCm++; }
for (const qid in tw) if (tw[qid].sf & 1) { if (!rep[qid]) nTw++; rep[qid] = 1; }
const ids = Object.keys(rep).map(Number).sort((a, b) => a - b);
console.log("union repeatables:", ids.length, "(cmangos", nCm + ", turtle-only +" + nTw + ")");

const lines = [];
for (let i = 0; i < ids.length; i += 15) {
  lines.push("  " + ids.slice(i, i + 15).map((id) => "[" + id + "]=1").join(",") + ",");
}
fs.writeFileSync(path.join(__dirname, "Repeatables.lua"), [
  "-- OctoQuestTrash repeatable-quest set: UNION of",
  "--   cmangos classic-db 1.12 (github.com/cmangos/classic-db,",
  "--     quest_template.SpecialFlags & 1): " + nCm + " quests",
  "--   Turtle WoW 1.18.1 preservation db (github.com/Penqle/tortoise-wow,",
  "--     base + all migrations applied): +" + nTw + " more (incl. all custom",
  "--     repeatables >= 40000 and classics Turtle made repeatable)",
  "-- GENERATED via scratchpad gen-data2.js. " + ids.length + " quests total.",
  "-- Union = over-protective on purpose: a quest repeatable on EITHER core",
  "-- is never treated as done forever (OctoWoW may follow either).",
  "OctoQuestTrashRepeatable = {",
  lines.join("\n"),
  "}",
  "",
].join("\n"));

// customs with known repeatability (they're in the turtle db) -> the
// "probably deletable" hedge is unnecessary for them
const known = Object.keys(tw).map(Number).filter((id) => id >= 40000).sort((a, b) => a - b);
console.log("known customs:", known.length);
const kLines = [];
for (let i = 0; i < known.length; i += 15) {
  kLines.push("  " + known.slice(i, i + 15).map((id) => "[" + id + "]=1").join(",") + ",");
}
fs.writeFileSync(path.join(__dirname, "CustomKnown.lua"), [
  "-- OctoQuestTrash: custom (>= 40000) quests present in the Turtle 1.18.1",
  "-- preservation db (github.com/Penqle/tortoise-wow), i.e. their",
  "-- repeatability is KNOWN (repeatable ones are in Repeatables.lua).",
  "-- A completed custom quest in this set gets a normal verdict; customs",
  "-- NOT in it (OctoWoW-only additions) keep the hedged \"probably",
  "-- deletable\" wording. GENERATED via scratchpad gen-data2.js. " + known.length + " quests.",
  "OctoQuestTrashCustomKnown = {",
  kLines.join("\n"),
  "}",
  "",
].join("\n"));

// sanity: agent's custom repeatable list must all be in the union set
const customRep = [40340, 40617, 40709, 40871, 41005, 41068, 41079, 41328, 50318, 60031, 60035, 80219, 80740];
const missA = customRep.filter((id) => !rep[id]);
// and the 51 turtle-repeatable classics samples
const classicTw = [254, 908, 6241, 7478, 7479, 7480, 7830];
const missB = classicTw.filter((id) => !rep[id]);
console.log(missA.length || missB.length ? "MISSING: " + missA.join(",") + " | " + missB.join(",") : "sanity: all present");
