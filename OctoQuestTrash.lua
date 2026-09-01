-- OctoQuestTrash - tells you when a quest item can be safely deleted.
-- Vanilla 1.12 (Lua 5.0), built for Turtle/OctoWoW cores.
--
-- Data sources (all from pfQuest, which must be installed):
--   pfDB["quests"]["data"][qid].start.I  = items that START quest qid
--   pfDB["quests"]["data"][qid].obj.I    = items collected as objectives
--   pfDB["quests"]["data"][qid].obj.IR   = items carried/used on targets
--   pfDB["quests"]["data"][qid].event    = seasonal/event quest marker
--   pfQuest_history[qid]                 = completed quests (backfill: /db query)
--   pfQuest.questlog[qid]                = quests currently in the log
--   OctoQuestTrashRepeatable[qid]        = repeatable quests (Repeatables.lua:
--                                          union of the cmangos 1.12 and
--                                          Turtle 1.18.1 world dbs)
--   OctoQuestTrashProvided[iid]          = quest-provided items (SrcItemId,
--                                          from the cmangos 1.12 db)
--   OctoQuestTrashCustomKnown[qid]       = customs with known repeatability
--
-- Verdicts per bag item (most protective wins):
--   active   - a quest in your log wants it. Keep.
--   farm     - a REPEATABLE or SEASONAL quest references it: permanent /
--              recurring demand, never flagged deletable no matter what
--              the history says (repeatables stay "completed" server-side
--              after the first turn-in; seasonal flags can be reset).
--   maybe    - a quest you haven't done yet wants it. Keep.
--   custom   - only custom (Turtle/Octo, id >= 40000) completed quests
--              reference it; repeatability of customs is unknowable from
--              the db, so this is only "probably deletable".
--   safe     - every referencing quest is completed (non-repeatable,
--              non-seasonal). For tradable items (item type ~= Quest) the
--              advice is softened to sell/AH - never "delete" something
--              with market value (e.g. class-locked mats).
--   notyours - referenced only by quests impossible for your race/class.
--              Same idea as safe, but the reason is stated honestly.
--   unknown  - item type is Quest but the db has no link for it. Keep.
--
-- Caveats (see README): pfQuest_history can be polluted by pfQuest's
-- abandon-detection edge cases; /db query rebuilds it from the server
-- (.queststatus) and is the recommended source of truth. Quest REWARDS
-- are not in pfQuest's db, so keys/attunements get no verdict (by design;
-- a small never-delete list guards them in case future dbs add links).

OctoQuestTrash = {}
local OQT = OctoQuestTrash

local index = nil        -- [itemID] = { {qid, role}, ... }  role: "start"|"obj"|"req"
local prace, pclass = nil, nil
local hinted = nil
local lastHistoryCount = -1

local CUSTOM_QUEST_MIN = 40000

-- Items never to advise deleting even if a db update links them to
-- completed quests: keys, attunements, portal items, quintessences.
local NEVER_DELETE = {
  [17333]=1, -- Aqual Quintessence
  [22754]=1, -- Eternal Quintessence
  [17191]=1, -- Scepter of Celebras
  [12344]=1, -- Seal of Ascension
  [16309]=1, -- Drakefire Amulet
  [9240]=1,  -- Mallet of Zul'Farrak
  [13704]=1, -- Skeleton Key (Scholomance)
  [11000]=1, -- Shadowforge Key
  [6893]=1,  -- Workshop Key
  [5396]=1,  -- Key to Searing Gorge
  [18249]=1, -- Crescent Key
  [12846]=1, -- Argent Dawn Commission
  [11511]=1, -- Cenarion Beacon
}

local ROLE_TEXT = { start = "starts", obj = "needed for", req = "used in", prov = "given by" }

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccOcto|cffffffffQuestTrash|r: " .. msg)
end

-- ---------------------------------------------------------------- index

local function AddLink(itemID, qid, role)
  itemID = tonumber(itemID)
  if not itemID then return end
  if not index[itemID] then index[itemID] = {} end
  -- the db repeats ids sometimes ({16305, 16305}); skip exact duplicates
  for _, link in ipairs(index[itemID]) do
    if link[1] == qid and link[2] == role then return end
  end
  table.insert(index[itemID], { qid, role })
end

local function BuildIndex()
  if not (pfDB and pfDB["quests"] and pfDB["quests"]["data"]) then return end
  index = {}
  for qid, q in pairs(pfDB["quests"]["data"]) do
    if q["start"] and q["start"]["I"] then
      for _, iid in pairs(q["start"]["I"]) do AddLink(iid, qid, "start") end
    end
    if q["obj"] then
      if q["obj"]["I"] then
        for _, iid in pairs(q["obj"]["I"]) do AddLink(iid, qid, "obj") end
      end
      if q["obj"]["IR"] then
        for _, iid in pairs(q["obj"]["IR"]) do AddLink(iid, qid, "req") end
      end
    end
  end
  -- quest-provided items (SrcItemId): pfQuest's db has no concept of them,
  -- so without these links a provided item is invisible - or judged only
  -- by OTHER quests and read "deletable" while its own quest is mid-flight
  if OctoQuestTrashProvided then
    for iid, qids in pairs(OctoQuestTrashProvided) do
      for _, qid in pairs(qids) do AddLink(iid, qid, "prov") end
    end
  end
end

local function InitPlayerBits()
  if pfDatabase and pfDatabase.GetBitByRace and bit then
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    prace = pfDatabase:GetBitByRace(race)
    pclass = pfDatabase:GetBitByClass(class)
  end
end

-- ---------------------------------------------------------------- state

local function QuestName(qid)
  local loc = pfDB and pfDB["quests"] and (pfDB["quests"]["loc"] or pfDB["quests"]["enUS"])
  local entry = loc and loc[qid]
  if entry and entry["T"] then return entry["T"] end
  return "quest #" .. qid
end

-- "active" | "repeat" | "event" | "done" | "customdone" | "never" | "open"
local function QuestState(qid)
  if pfQuest and pfQuest.questlog and pfQuest.questlog[qid] then return "active" end
  if OctoQuestTrashRepeatable and OctoQuestTrashRepeatable[qid] then return "repeat" end
  local q = pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][qid]
  if q and q["event"] then return "event" end
  if pfQuest_history and pfQuest_history[qid] then
    -- customs get the hedged verdict only when their repeatability is
    -- unknowable (absent from the Turtle preservation db = OctoWoW-only)
    if qid >= CUSTOM_QUEST_MIN
      and not (OctoQuestTrashCustomKnown and OctoQuestTrashCustomKnown[qid]) then
      return "customdone"
    end
    return "done"
  end
  if q and bit then
    if q["race"] and prace and bit.band(q["race"], prace) ~= prace then return "never" end
    if q["class"] and pclass and bit.band(q["class"], pclass) ~= pclass then return "never" end
  end
  return "open"
end

-- Returns verdict, links ({ {qid, role, state}, ... }) or nil for
-- items with no quest link and non-Quest item type.
function OQT.GetVerdict(itemID)
  if not index then BuildIndex() end
  if NEVER_DELETE[itemID] then return "keep", {} end
  local links = index and index[itemID]
  if not links then
    local _, _, _, _, itemType = GetItemInfo(itemID)
    if itemType == "Quest" then return "unknown", {} end
    return nil
  end
  local has = {}
  local out = {}
  for _, link in ipairs(links) do
    local state = QuestState(link[1])
    table.insert(out, { link[1], link[2], state })
    has[state] = true
  end
  local verdict
  if has["active"] then verdict = "active"
  elseif has["repeat"] or has["event"] then verdict = "farm"
  elseif has["open"] then verdict = "maybe"
  elseif has["customdone"] then verdict = "custom"
  elseif has["done"] then verdict = "safe"
  elseif has["never"] then verdict = "notyours"
  else verdict = "unknown" end
  return verdict, out
end

-- Deletion advice only applies to true Quest-type items; anything tradable
-- (mats, class-locked drops) gets sell/AH wording instead of "delete".
local function IsQuestType(itemID)
  local _, _, _, _, itemType = GetItemInfo(itemID)
  return itemType == "Quest"
end

-- ---------------------------------------------------------------- tooltip

local STATE_COLOR = {
  active = "|cff33ff99", ["repeat"] = "|cff88bbff", event = "|cff88bbff",
  done = "|cffff5555", customdone = "|cffcc8855", never = "|cff888888",
  open = "|cffffcc00",
}
local STATE_TEXT = {
  active = "in your log", ["repeat"] = "repeatable", event = "seasonal",
  done = "completed", customdone = "done, custom quest",
  never = "not for your race/class", open = "not done yet",
}

local VERDICT_LINE = {
  active   = "|cff33ff99Keep - needed for an active quest|r",
  farm     = "|cff88bbffKeep - a repeatable/seasonal quest wants this|r",
  maybe    = "|cffffcc00Keep - a quest still wants this|r",
  custom   = "|cffcc8855Probably deletable |r|cffaaaaaa(custom quest, repeatability unknown)|r",
  keep     = "|cff33ff99Keep - key/attunement item|r",
  unknown  = "|cffaaaaaaNo quest data - keep to be safe|r",
}

local function VerdictLine(verdict, itemID)
  if verdict == "safe" then
    if IsQuestType(itemID) then
      return "|cffff5555Can be deleted|r |cffaaaaaa(quests completed - per pfQuest history)|r"
    end
    return "|cffff9955No quest needs this anymore|r |cffaaaaaa(tradable - sell or AH it)|r"
  elseif verdict == "notyours" then
    if IsQuestType(itemID) then
      return "|cffff5555Can be deleted|r |cffaaaaaa(only race/class-locked quests use it)|r"
    end
    return "|cffff9955No use to you|r |cffaaaaaa(race/class-locked quests; tradable - sell or AH it)|r"
  end
  return VERDICT_LINE[verdict]
end

local function Annotate(tooltip, itemID)
  local verdict, links = OQT.GetVerdict(itemID)
  if not verdict then return end

  tooltip:AddLine(VerdictLine(verdict, itemID))

  local shown = 0
  for _, link in ipairs(links) do
    shown = shown + 1
    if shown > 4 then
      tooltip:AddLine("|cffaaaaaa  ...and " .. (table.getn(links) - 4) .. " more|r")
      break
    end
    local qid, role, state = link[1], link[2], link[3]
    tooltip:AddLine("|cffaaaaaa  " .. ROLE_TEXT[role] .. "|r " .. QuestName(qid)
      .. " " .. STATE_COLOR[state] .. "(" .. STATE_TEXT[state] .. ")|r")
  end
  tooltip:Show()
end

local origSetBagItem = GameTooltip.SetBagItem
function GameTooltip.SetBagItem(self, bag, slot)
  local hasCooldown, repairCost = origSetBagItem(self, bag, slot)
  local link = GetContainerItemLink(bag, slot)
  if link then
    local _, _, sid = string.find(link, "item:(%d+)")
    if sid then Annotate(self, tonumber(sid)) end
  end
  return hasCooldown, repairCost
end

-- bank main slots (and equipped items) come through SetInventoryItem
local origSetInventoryItem = GameTooltip.SetInventoryItem
function GameTooltip.SetInventoryItem(self, unit, invSlot)
  local hasItem, hasCooldown, repairCost = origSetInventoryItem(self, unit, invSlot)
  if unit == "player" then
    local link = GetInventoryItemLink("player", invSlot)
    if link then
      local _, _, sid = string.find(link, "item:(%d+)")
      if sid then Annotate(self, tonumber(sid)) end
    end
  end
  return hasItem, hasCooldown, repairCost
end

-- ---------------------------------------------------------------- scan

local VERDICT_HEAD = {
  safe = "|cffff5555Deletable / no longer needed:|r",
  notyours = "|cffff9955Race/class-locked (no use to you):|r",
  custom = "|cffcc8855Probably deletable (custom quests):|r",
  farm = "|cff88bbffRepeatable/seasonal demand (keep):|r",
  maybe = "|cffffcc00Quest not done yet (keep):|r",
  unknown = "|cffaaaaaaQuest items with no data (keep):|r",
}
local SCAN_ORDER = { "safe", "notyours", "custom", "farm", "maybe", "unknown" }

function OQT.Scan()
  local groups = {}
  for _, key in ipairs(SCAN_ORDER) do groups[key] = {} end
  local seen = {}
  for bag = -1, 10 do
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local _, _, sid = string.find(link, "item:(%d+)")
          local itemID = tonumber(sid)
          if itemID and not seen[itemID] then
            seen[itemID] = true
            local verdict, links = OQT.GetVerdict(itemID)
            if verdict and groups[verdict] then
              local name = GetItemInfo(itemID)
              if not name and pfDB and pfDB["items"] then
                local iloc = pfDB["items"]["loc"] or pfDB["items"]["enUS"]
                name = iloc and iloc[itemID]
              end
              name = name or ("item #" .. itemID)
              local why = ""
              if links and links[1] then why = " |cffaaaaaa- " .. QuestName(links[1][1]) .. "|r" end
              table.insert(groups[verdict], "  " .. name .. why)
            end
          end
        end
      end
    end
  end

  local total = 0
  for _, key in ipairs(SCAN_ORDER) do
    if table.getn(groups[key]) > 0 then
      Print(VERDICT_HEAD[key])
      for _, line in ipairs(groups[key]) do
        DEFAULT_CHAT_FRAME:AddMessage(line)
        total = total + 1
      end
    end
  end
  if total == 0 then
    Print("no quest items needing a verdict in your bags.")
  end
end

SLASH_OCTOQUESTTRASH1 = "/oqt"
SLASH_OCTOQUESTTRASH2 = "/questtrash"
SlashCmdList["OCTOQUESTTRASH"] = function()
  OQT.Scan()
end

-- ---------------------------------------------------------------- bagshui

local function RegisterBagshui()
  if not (Bagshui and Bagshui.AddRuleFunction) then return end
  Bagshui:AddRuleFunction({
    functionNames = { "SafeToDelete", "std" },
    ruleFunction = function(rules)
      local id = rules.item and rules.item.id
      if not id or id == 0 then return false end
      local verdict = OQT.GetVerdict(id)
      return verdict == "safe" or verdict == "notyours"
    end,
    ruleTemplates = {
      { code = "SafeToDelete()", description = "Quest items no longer needed: all their quests completed or race/class-impossible (OctoQuestTrash, per pfQuest history)." },
    },
    description = "OctoQuestTrash: quest item no longer needed.",
  })
end

-- ---------------------------------------------------------------- events

local function HistoryCount()
  local n = 0
  if pfQuest_history then
    for _ in pairs(pfQuest_history) do n = n + 1 end
  end
  return n
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    InitPlayerBits()
    if not index then BuildIndex() end
    lastHistoryCount = HistoryCount()
    if not hinted then
      hinted = true
      RegisterBagshui()
      if not (pfDB and pfDB["quests"]) then
        Print("|cffff5555pfQuest not found|r - verdicts unavailable.")
      elseif lastHistoryCount == 0 and UnitLevel("player") > 5 then
        Print("no completed-quest history yet - run |cff33ffcc/db query|r once to fetch it from the server.")
      end
    end
  elseif event == "QUEST_LOG_UPDATE" then
    -- verdicts only change when the completed set changes; gate the
    -- Bagshui recategorize on that instead of every log-update burst
    local n = HistoryCount()
    if n ~= lastHistoryCount then
      lastHistoryCount = n
      if Bagshui and Bagshui.QueueInventoryUpdate then
        Bagshui:QueueInventoryUpdate(2, true)
      end
    end
  end
end)
