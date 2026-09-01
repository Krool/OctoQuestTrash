-- Minimal WoW 1.12 + pfQuest environment for running OctoQuestTrash
-- under a modern Lua VM (fengari, Lua 5.3). Only what the addon touches.

-- Lua 5.0 compat the addon relies on
table.getn = table.getn or function(t) return #t end

-- bit library (1.12 clients expose one via pfQuest/compat)
bit = bit or {
  band = function(a, b)
    local result, bitval = 0, 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then result = result + bitval end
      a = math.floor(a / 2)
      b = math.floor(b / 2)
      bitval = bitval * 2
    end
    return result
  end,
}

-- frames: capture created frames so tests can fire events
CreatedFrames = {}
function CreateFrame(kind, name)
  local f = { scripts = {}, events = {} }
  function f.RegisterEvent(self, e) self.events[e] = true end
  function f.SetScript(self, which, fn) self.scripts[which] = fn end
  function f.Hide(self) end
  function f.Show(self) end
  table.insert(CreatedFrames, f)
  return f
end

function FireEvent(e)
  event = e -- 1.12 delivers the event name as a global
  for _, f in ipairs(CreatedFrames) do
    if f.events[e] and f.scripts.OnEvent then
      f.scripts.OnEvent(f)
    end
  end
  event = nil
end

-- tooltip: record added lines for assertions
GameTooltip = { lines = {} }
function GameTooltip.SetBagItem(self, bag, slot) return nil, nil end
function GameTooltip.SetInventoryItem(self, unit, slot) return nil, nil, nil end
function GameTooltip.AddLine(self, text) table.insert(self.lines, text) end
function GameTooltip.Show(self) end
function GameTooltip.Reset(self) self.lines = {} end

DEFAULT_CHAT_FRAME = { messages = {} }
function DEFAULT_CHAT_FRAME.AddMessage(self, msg) table.insert(self.messages, msg) end

SlashCmdList = {}

-- player: a level-10 Human Warrior
function UnitRace(u) return "Human", "Human" end
function UnitClass(u) return "Warrior", "WARRIOR" end
function UnitLevel(u) return 10 end

-- item info: tests register fixtures via ItemFixtures[id] = { name, type }
ItemFixtures = {}
function GetItemInfo(id)
  local fx = ItemFixtures[id]
  if not fx then return nil end
  -- 1.12 order: name, link, quality, minLevel, TYPE, subtype, stack, equipLoc, texture
  return fx.name, "item:" .. id, 1, 1, fx.type, "", 1, "", ""
end

-- bags: tests fill BagFixtures[bag] = { [slot] = itemID }
BagFixtures = {}
function GetContainerNumSlots(bag)
  local b = BagFixtures[bag]
  if not b then return 0 end
  local n = 0
  for slot in pairs(b) do if slot > n then n = slot end end
  return n
end
function GetContainerItemLink(bag, slot)
  local b = BagFixtures[bag]
  if not b or not b[slot] then return nil end
  return "|cffffffff|Hitem:" .. b[slot] .. ":0:0:0|h[item]|h|r"
end
function GetInventoryItemLink(unit, slot) return nil end

-- pfQuest surface the addon reads (fixtures filled by test.lua)
pfDB = { quests = { data = {}, enUS = {} }, items = { enUS = {} } }
pfDB["quests"]["loc"] = pfDB["quests"]["enUS"]
pfDB["items"]["loc"] = pfDB["items"]["enUS"]
pfQuest = { questlog = {} }
pfQuest_history = {}
pfDatabase = {}
function pfDatabase.GetBitByRace(self, race) return 1 end   -- Human bit
function pfDatabase.GetBitByClass(self, class) return 1 end -- Warrior bit

-- Bagshui deliberately absent (integration guarded in the addon)
Bagshui = nil
