// OctoQuestTrash test runner.
// 1. Syntax-checks every addon Lua file (luaparse, Lua 5.1 grammar - the
//    1.12 client accepts this superset of its Lua 5.0).
// 2. Validates the generated data files (counts, sentinel ids).
// 3. Executes the addon under a stubbed WoW environment (fengari) and
//    runs the behavior tests in test.lua.
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const root = path.join(__dirname, "..", "..");
const addonFiles = ["Repeatables.lua", "Provided.lua", "CustomKnown.lua", "OctoQuestTrash.lua"];
let failed = false;

// ---- 1. syntax
for (const f of addonFiles) {
  const src = fs.readFileSync(path.join(root, f), "utf8");
  try {
    luaparse.parse(src, { luaVersion: "5.1" });
    console.log("syntax ok: " + f);
  } catch (e) {
    console.log("SYNTAX FAIL: " + f + ": " + e.message);
    failed = true;
  }
}

// ---- 2. data sanity
function countIds(file, pattern) {
  const src = fs.readFileSync(path.join(root, file), "utf8");
  let n = 0;
  const re = new RegExp(pattern, "gm");
  while (re.exec(src)) n++;
  return n;
}
const repCount = countIds("Repeatables.lua", "\\[\\d+\\]=1");
const provCount = countIds("Provided.lua", "^  \\[\\d+\\] = \\{");
const knownCount = countIds("CustomKnown.lua", "\\[\\d+\\]=1");
console.log(`data: ${repCount} repeatables, ${provCount} provided items, ${knownCount} known customs`);
if (repCount < 700) { console.log("DATA FAIL: repeatable set suspiciously small"); failed = true; }
if (provCount < 800) { console.log("DATA FAIL: provided map suspiciously small"); failed = true; }
if (knownCount < 2000) { console.log("DATA FAIL: known-custom set suspiciously small"); failed = true; }
// sentinels: BG turn-in 7341 (the v1 gap), custom 41069, scourgestones 5508
const repSrc = fs.readFileSync(path.join(root, "Repeatables.lua"), "utf8");
for (const id of [7341, 41069, 5508, 4381, 7796]) {
  if (repSrc.indexOf("[" + id + "]=1") < 0) {
    console.log("DATA FAIL: sentinel repeatable " + id + " missing");
    failed = true;
  }
}

if (failed) { console.log("ABORTING before behavior tests"); process.exit(1); }

// ---- 3. behavior under fengari
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function runLua(label, src) {
  const status = lauxlib.luaL_loadbuffer(L, to_luastring(src), src.length, to_luastring("@" + label));
  if (status !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.log("LUA FAIL in " + label + ": " + lua.lua_tojsstring(L, -1));
    process.exit(1);
  }
}

runLua("stubs.lua", fs.readFileSync(path.join(__dirname, "stubs.lua"), "utf8"));
for (const f of addonFiles) {
  runLua(f, fs.readFileSync(path.join(root, f), "utf8"));
}

// capture print output
let output = [];
lua.lua_register(L, to_luastring("print"), (L) => {
  const n = lua.lua_gettop(L);
  const parts = [];
  for (let i = 1; i <= n; i++) parts.push(lua.lua_tojsstring(L, i) || lauxlib.luaL_tolstring(L, i));
  output.push(parts.join("\t"));
  return 0;
});

const testSrc = fs.readFileSync(path.join(__dirname, "test.lua"), "utf8");
const status = lauxlib.luaL_loadbuffer(L, to_luastring(testSrc), testSrc.length, to_luastring("@test.lua"));
const ok = status === lua.LUA_OK && lua.lua_pcall(L, 0, 0, 0) === lua.LUA_OK;
console.log(output.join("\n"));
if (!ok) {
  console.log("BEHAVIOR TESTS FAILED: " + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
console.log("ALL TESTS PASSED");
