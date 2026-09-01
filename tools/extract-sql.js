// Stream-parse classicmangos.sql for quest_template + item_template.
const fs = require("fs");
const path = require("path");
const SQL = path.join(__dirname, "worlddb", "classicmangos.sql");

// tuple parser: given string starting at '(' returns [values[], endIdxAfterParen]
function parseTuple(s, i) {
  const vals = [];
  i++; // past (
  let cur = "";
  while (i < s.length) {
    const c = s[i];
    if (c === "'") {
      let str = "";
      i++;
      while (i < s.length) {
        if (s[i] === "\\") { str += s[i + 1]; i += 2; }
        else if (s[i] === "'") {
          if (s[i + 1] === "'") { str += "'"; i += 2; } else { i++; break; }
        } else { str += s[i]; i++; }
      }
      vals.push(str);
      // skip to , or )
      while (s[i] !== "," && s[i] !== ")") i++;
    } else if (c === "," ) {
      if (cur !== "") { vals.push(cur.trim()); cur = ""; }
      else if (vals.length === 0 || s[i-1] === ",") vals.push("");
      i++;
    } else if (c === ")") {
      if (cur !== "") vals.push(cur.trim());
      return [vals, i + 1];
    } else { cur += c; i++; }
  }
  throw new Error("unterminated tuple");
}

function colIndex(cols, name) {
  const i = cols.indexOf(name.toLowerCase());
  if (i < 0) throw new Error("col not found: " + name);
  return i;
}

async function main() {
  const quests = {};
  const items = {};
  let questCols = null, itemCols = null;
  let mode = null; // 'ct-quest','ct-item'
  let pending = ""; // partial line buffer for INSERT continuation

  const rl = require("readline").createInterface({
    input: fs.createReadStream(SQL, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });

  let collecting = null; // {table, buf}
  for await (const rawLine of rl) {
    const line = rawLine;
    if (mode) {
      const m = /^\s*`([A-Za-z_0-9]+)`/.exec(line);
      if (m) { (mode === "q" ? questCols : itemCols).push(m[1].toLowerCase()); continue; }
      if (/^\)/.test(line) || /PRIMARY KEY|KEY |UNIQUE/.test(line)) { if (/^\)/.test(line)) mode = null; continue; }
      mode = null;
      continue;
    }
    if (line.startsWith("CREATE TABLE `quest_template`")) { questCols = []; mode = "q"; continue; }
    if (line.startsWith("CREATE TABLE `item_template`")) { itemCols = []; mode = "i"; continue; }

    let table = null;
    if (line.startsWith("INSERT INTO `quest_template`")) table = "q";
    else if (line.startsWith("INSERT INTO `item_template`")) table = "i";
    else if (!collecting) continue;

    let chunk = collecting ? collecting.buf + "\n" + line : line;
    if (collecting) table = collecting.table;
    // does statement end on this line? cmangos dumps end statements with ');' typically per line
    if (!/;\s*$/.test(chunk)) { collecting = { table, buf: chunk }; continue; }
    collecting = null;

    // parse all tuples in the statement after VALUES
    let vi = chunk.indexOf("VALUES");
    if (vi < 0) continue;
    let i = chunk.indexOf("(", vi);
    while (i >= 0 && i < chunk.length) {
      let vals, ni;
      try { [vals, ni] = parseTuple(chunk, i); } catch (e) { break; }
      if (table === "q") {
        const c = (n) => vals[colIndex(questCols, n)];
        const entry = +c("entry");
        quests[entry] = {
          t: c("Title"),
          sf: +c("SpecialFlags"), qf: +c("QuestFlags"),
          src: +c("SrcItemId"),
          req: [+c("ReqItemId1"), +c("ReqItemId2"), +c("ReqItemId3"), +c("ReqItemId4")].filter(x => x > 0),
          races: +c("RequiredRaces"), classes: +c("RequiredClasses"),
        };
      } else {
        const c = (n) => vals[colIndex(itemCols, n)];
        const entry = +c("entry");
        items[entry] = {
          n: c("name"), cl: +c("class"), sub: +c("subclass"),
          sq: +c("startquest"), fl: +c("Flags"), sell: +c("SellPrice"),
          bond: +c("bonding"), sp: +c("spellid_1"), maxc: +c("maxcount"),
        };
      }
      // find next '(' after ni (skip , between tuples)
      while (ni < chunk.length && chunk[ni] !== "(" && chunk[ni] !== ";") ni++;
      if (chunk[ni] !== "(") break;
      i = ni;
    }
  }
  console.log("quests:", Object.keys(quests).length, "items:", Object.keys(items).length);
  fs.writeFileSync(path.join(__dirname, "sqldb.json"), JSON.stringify({ quests, items }));
  // sanity
  console.log("q1 (sample):", JSON.stringify(quests[7], null, 0));
  console.log("item 6948:", JSON.stringify(items[6948]));
}
main().catch(e => { console.error(e); process.exit(1); });
