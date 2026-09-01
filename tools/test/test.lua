-- OctoQuestTrash behavior tests. Runs after stubs.lua and the addon files
-- (Repeatables.lua, Provided.lua, CustomKnown.lua, OctoQuestTrash.lua)
-- have been loaded into the same Lua state by run.js.

local failures = 0
local count = 0

local function check(label, got, want)
  count = count + 1
  if got ~= want then
    failures = failures + 1
    print("FAIL: " .. label .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
  else
    print("ok:   " .. label)
  end
end

-- ---------------------------------------------------------------- fixtures

local D = pfDB["quests"]["data"]
local N = pfDB["quests"]["enUS"]

-- plain one-time quest, eligible for the player
D[100] = { race = 255, obj = { I = { 9999 } } }
N[100] = { T = "Plain Collect Quest" }

-- race-locked quest (mask 2, player bit is 1)
D[101] = { race = 2, obj = { I = { 8888 } } }
N[101] = { T = "Other Faction Quest" }

-- event-flagged (seasonal) quest
D[102] = { event = 5, obj = { I = { 7777 } } }
N[102] = { T = "Holiday Quest" }

-- starter item quest
D[103] = { race = 255, start = { I = { 5555 } } }
N[103] = { T = "Item-Started Quest" }

-- REAL repeatable ids from Repeatables.lua, wired to fixture items:
-- 5508 Minion's Scourgestones, 4381 Un'Goro pylon, 7341 AV Ram Riding
-- Harnesses (from the BG gap that v1 missed)
assert(OctoQuestTrashRepeatable[5508], "5508 must be in the repeatable set")
assert(OctoQuestTrashRepeatable[4381], "4381 must be in the repeatable set")
assert(OctoQuestTrashRepeatable[7341], "7341 (BG turn-in) must be in the repeatable set")
D[5508] = { obj = { I = { 12840 } } }
N[5508] = { T = "Minion's Scourgestones" }

-- real Turtle custom repeatable: 41069 Black Lotus Collection
assert(OctoQuestTrashRepeatable[41069], "41069 must be in the repeatable set")
D[41069] = { obj = { I = { 13468 } } }
N[41069] = { T = "Black Lotus Collection" }

-- custom quest with KNOWN repeatability (pick one from CustomKnown that is
-- not repeatable) and one unknown custom absent from both sets
local knownCustom = nil
for qid in pairs(OctoQuestTrashCustomKnown) do
  if not OctoQuestTrashRepeatable[qid] and not D[qid] then
    knownCustom = qid
    break
  end
end
assert(knownCustom, "need a non-repeatable known custom quest")
D[knownCustom] = { obj = { I = { 6666 } } }
N[knownCustom] = { T = "Known Custom Quest" }

local unknownCustom = 99999
assert(not OctoQuestTrashCustomKnown[unknownCustom], "99999 must be unknown")
D[unknownCustom] = { obj = { I = { 6667 } } }
N[unknownCustom] = { T = "OctoWoW Custom Quest" }

-- item types
ItemFixtures[9999] = { name = "Plain Quest Fodder", type = "Quest" }
ItemFixtures[8888] = { name = "Valuable Mat", type = "Trade Goods" }
ItemFixtures[7777] = { name = "Holiday Token", type = "Quest" }
ItemFixtures[5555] = { name = "Starter Note", type = "Quest" }
ItemFixtures[12840] = { name = "Minion's Scourgestone", type = "Quest" }
ItemFixtures[13468] = { name = "Black Lotus", type = "Trade Goods" }
ItemFixtures[6666] = { name = "Known Custom Fodder", type = "Quest" }
ItemFixtures[6667] = { name = "Unknown Custom Fodder", type = "Quest" }
ItemFixtures[4444] = { name = "Unlinked Quest Item", type = "Quest" }
ItemFixtures[3333] = { name = "Ordinary Gray", type = "Junk" }
ItemFixtures[17333] = { name = "Aqual Quintessence", type = "Quest" }
ItemFixtures[5462] = { name = "Dartol's Rod of Transformation", type = "Quest" }

-- simulate login (builds index, reads player bits)
FireEvent("PLAYER_ENTERING_WORLD")

local OQT = OctoQuestTrash

-- ---------------------------------------------------------------- verdicts

-- active beats everything
pfQuest.questlog[100] = { "Plain Collect Quest", 1 }
check("active quest item", OQT.GetVerdict(9999), "active")
pfQuest.questlog[100] = nil

-- not done yet
check("open quest item", OQT.GetVerdict(9999), "maybe")

-- completed one-time quest
pfQuest_history[100] = { 0, 10 }
check("completed quest item", OQT.GetVerdict(9999), "safe")
pfQuest_history[100] = nil

-- starter item of an undone quest / done quest
check("starter, quest not done", OQT.GetVerdict(5555), "maybe")
pfQuest_history[103] = { 0, 10 }
check("starter, quest done", OQT.GetVerdict(5555), "safe")
pfQuest_history[103] = nil

-- repeatables are farm even when "completed"
pfQuest_history[5508] = { 0, 10 }
check("repeatable stays farm", OQT.GetVerdict(12840), "farm")
pfQuest_history[41069] = { 0, 10 }
check("turtle custom repeatable stays farm", OQT.GetVerdict(13468), "farm")

-- seasonal quests are never safe
pfQuest_history[102] = { 0, 10 }
check("event quest item stays farm", OQT.GetVerdict(7777), "farm")

-- race-locked only: honest "notyours", not "safe"
check("race-locked item", OQT.GetVerdict(8888), "notyours")

-- customs: known repeatability = hard verdict, unknown = hedge
pfQuest_history[knownCustom] = { 0, 10 }
check("known custom done = safe", OQT.GetVerdict(6666), "safe")
pfQuest_history[unknownCustom] = { 0, 10 }
check("unknown custom done = hedged", OQT.GetVerdict(6667), "custom")

-- never-delete list wins over everything
check("never-delete key item", OQT.GetVerdict(17333), "keep")

-- no links: quest-type = unknown, ordinary item = no verdict
check("unlinked quest-type item", OQT.GetVerdict(4444), "unknown")
check("ordinary item has no verdict", OQT.GetVerdict(3333), nil)

-- ------------------------------------------------------- provided items

-- 5462 Dartol's Rod: provided by real quests 1029/1030/1045 (Provided.lua)
local links = { [1029] = true, [1030] = true, [1045] = true }
pfQuest.questlog[1029] = { "Raene's Cleansing", 2 }
check("provided item guarded while quest active", OQT.GetVerdict(5462), "active")
pfQuest.questlog[1029] = nil
check("provided item, chain not done", OQT.GetVerdict(5462), "maybe")
for qid in pairs(links) do pfQuest_history[qid] = { 0, 10 } end
check("provided item, chain done", OQT.GetVerdict(5462), "safe")

-- ------------------------------------------------------- tooltip smoke

GameTooltip:Reset()
GameTooltip:SetBagItem(0, 1) -- BagFixtures empty: no line
check("tooltip silent on empty slot", table.getn(GameTooltip.lines), 0)

BagFixtures[0] = { [1] = 12840 }
GameTooltip:Reset()
GameTooltip:SetBagItem(0, 1)
check("tooltip annotates repeatable item", table.getn(GameTooltip.lines) >= 2, true)
check("tooltip verdict line is keep-farm",
  string.find(GameTooltip.lines[1], "repeatable") ~= nil, true)

-- ------------------------------------------------------- /oqt scan smoke

BagFixtures[0] = { [1] = 12840, [2] = 9999, [3] = 3333 }
pfQuest_history[100] = { 0, 10 }
DEFAULT_CHAT_FRAME.messages = {}
SlashCmdList["OCTOQUESTTRASH"]("")
check("scan produced output", table.getn(DEFAULT_CHAT_FRAME.messages) > 0, true)
local sawSafe, sawFarm = false, false
for _, msg in ipairs(DEFAULT_CHAT_FRAME.messages) do
  if string.find(msg, "Plain Quest Fodder") then sawSafe = true end
  if string.find(msg, "Scourgestone") then sawFarm = true end
end
check("scan lists completed-quest item", sawSafe, true)
check("scan lists repeatable item under keep", sawFarm, true)

-- ---------------------------------------------------------------- result

print(string.format("%d checks, %d failures", count, failures))
if failures > 0 then error("TESTS FAILED") end
