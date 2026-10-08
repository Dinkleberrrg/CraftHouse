--[[ CraftHouse -- core
     Namespace, saved variables, shared helpers, events and slash commands.

     Saved data (account wide, CraftHouseDB):
       chars[realm][char] = { profs = { [prof] = PROF } }   own characters
       others[realm][name] = { time, profs = { [prof] = PROF } }  shared by others
       queue[realm][char] = { {prof, name, count}, ... }
       lists[realm][char] = { out = { [name] = entries },  to-do lists for others
                              inc = { [name] = { time, items } } }  from others
       pos, scale, settings

     PROF = { rank, max, hash, count, craft (1 = Craft API, e.g. Enchanting),
              time, recipes = { REC, ... } }
     REC  = { n = name, id = itemID or 0, q = quality, l = required level,
              c = category (slot / "Enchant" / "Other"), t = { stat = value },
              d = difficulty (own only: optimal/medium/easy/trivial),
              r = { {id, count, name}, ... } reagents, ic = icon,
              mk = number made }
]]--

CraftHouse = {}
local CH = CraftHouse

CH.version  = "1.6.1"
CH.prefix   = "CraftHouse"
CH.realm    = nil
CH.player   = nil

-- Stats the search can filter on. Order = order in the menu.
CH.STATS = {
  { key = "str",   label = "Strength" },
  { key = "agi",   label = "Agility" },
  { key = "sta",   label = "Stamina" },
  { key = "int",   label = "Intellect" },
  { key = "spi",   label = "Spirit" },
  { key = "armor", label = "Armor" },
  { key = "sp",    label = "Spell Power" },
  { key = "heal",  label = "Healing" },
  { key = "ap",    label = "Attack Power" },
  { key = "hit",   label = "Hit %" },
  { key = "crit",  label = "Crit %" },
  { key = "mp5",   label = "Mana / 5s" },
  { key = "def",   label = "Defense" },
  { key = "dps",   label = "Weapon DPS" },
  { key = "fire",  label = "Fire Resist" },
  { key = "frost", label = "Frost Resist" },
  { key = "nat",   label = "Nature Resist" },
  { key = "shad",  label = "Shadow Resist" },
  { key = "arc",   label = "Arcane Resist" },
}
CH.STATLABEL = {}
for _, s in ipairs(CH.STATS) do CH.STATLABEL[s.key] = s.label end

-- Short names used in the result list
CH.STATSHORT = {
  str = "Str", agi = "Agi", sta = "Sta", int = "Int", spi = "Spi",
  armor = "Armor", sp = "SP", heal = "Heal", ap = "AP", hit = "Hit%",
  crit = "Crit%", mp5 = "Mp5", def = "Def", dps = "DPS",
  fire = "FireRes", frost = "FrostRes", nat = "NatRes", shad = "ShadRes",
  arc = "ArcRes",
}

-- Categories in the left list. Order = display order.
-- Only categories that occur in the current profession are shown.
CH.CATEGORIES = {
  "All", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands",
  "Waist", "Legs", "Feet", "Finger", "Trinket", "Weapon", "Off Hand",
  "Ranged", "Bag", "Enchant", "Health", "Mana", "Health + Mana",
  "Buff food", "Buff", "Bandage", "Poison", "Explosive", "Material", "Other",
}

CH.QUALITY = {
  [0] = { "Poor",      "ff9d9d9d" },
  [1] = { "Common",    "ffffffff" },
  [2] = { "Uncommon",  "ff1eff00" },
  [3] = { "Rare",      "ff0070dd" },
  [4] = { "Epic",      "ffa335ee" },
  [5] = { "Legendary", "ffff8000" },
}

CH.DIFF = {
  optimal = { 1.00, 0.50, 0.25, 4 },
  medium  = { 1.00, 1.00, 0.00, 3 },
  easy    = { 0.25, 0.75, 0.25, 2 },
  trivial = { 0.50, 0.50, 0.50, 1 },
}

-- Profession name -> spell that opens its window (where they differ)
CH.OPENSPELL = { ["Mining"] = "Smelting" }

--------------------------------------------------------------------------
-- Helpers (Lua 5.0: no #, no %, no string.match)
--------------------------------------------------------------------------

function CH.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccCraftHouse|r: " .. msg)
end

function CH.Split(s, sep)
  local out, n, pos = {}, 0, 1
  if not s or s == "" then return out, 0 end
  while true do
    local a, b = strfind(s, sep, pos, true)
    n = n + 1
    if not a then
      out[n] = strsub(s, pos)
      break
    end
    out[n] = strsub(s, pos, a - 1)
    pos = b + 1
  end
  return out, n
end

-- Small string hash (no bit ops in 1.12), returned as base-36 text
function CH.Hash(s)
  local h = 5381
  for i = 1, strlen(s) do
    h = math.mod(h * 33 + string.byte(s, i), 2147483629)
  end
  local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
  repeat
    local d = math.mod(h, 36)
    out = strsub(digits, d + 1, d + 1) .. out
    h = math.floor(h / 36)
  until h == 0
  return out
end

function CH.ItemID(link)
  if not link then return 0 end
  local _, _, id = strfind(link, "item:(%d+)")
  return tonumber(id) or 0
end

function CH.QualityFromLink(link)
  if not link then return 1 end
  local _, _, hex = strfind(link, "|c(%x%x%x%x%x%x%x%x)")
  if hex then
    hex = strlower(hex)
    for q, v in pairs(CH.QUALITY) do
      if v[2] == hex then return q end
    end
  end
  return 1
end

function CH.Color(q)
  local v = CH.QUALITY[q or 1] or CH.QUALITY[1]
  return "|c" .. v[2]
end

function CH.Count(t)
  local n = 0
  if t then for _ in pairs(t) do n = n + 1 end end
  return n
end

function CH.Ago(t)
  if not t then return "?" end
  local d = time() - t
  if d < 3600 then return math.floor(d / 60) .. "m" end
  if d < 86400 then return math.floor(d / 3600) .. "h" end
  return math.floor(d / 86400) .. "d"
end

--------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------

local function Sub(t, k)
  if not t[k] then t[k] = {} end
  return t[k]
end

function CH.InitDB()
  if not CraftHouseDB then CraftHouseDB = {} end
  local db = CraftHouseDB
  Sub(db, "chars"); Sub(db, "others"); Sub(db, "queue")
  if not db.settings then
    db.settings = { replace = 1, autoopen = 1, guild = 1 }
  end
  CH.db = db
  CH.me = Sub(Sub(db.chars, CH.realm), CH.player)
  Sub(CH.me, "profs")
  CH.queue = Sub(Sub(db.queue, CH.realm), CH.player)
  CH.others = Sub(db.others, CH.realm)
  -- professions shared per player: shared[name][prof] = true
  CH.shared = Sub(Sub(Sub(db, "shared"), CH.realm), CH.player)
  CH.lists = Sub(Sub(Sub(db, "lists"), CH.realm), CH.player)
  Sub(CH.lists, "out"); Sub(CH.lists, "inc")
end

-- All sources the browser can show: own char, own alts, other players
function CH.Sources()
  local list = { { name = CH.player, kind = "me", data = CH.me } }
  for name, data in pairs(CH.db.chars[CH.realm]) do
    if name ~= CH.player and CH.Count(data.profs) > 0 then
      table.insert(list, { name = name, kind = "alt", data = data })
    end
  end
  for name, data in pairs(CH.others) do
    if not CH.db.chars[CH.realm][name] then
      table.insert(list, { name = name, kind = "other", data = data })
    end
  end
  return list
end

-- Deletes the saved recipes of an alt or another player
function CH.Forget(name)
  if not name or name == CH.player then return end
  local found
  if CH.db.chars[CH.realm][name] then CH.db.chars[CH.realm][name] = nil; found = true end
  if CH.others[name] then CH.others[name] = nil; found = true end
  if found then
    CH.Print("Deleted the saved recipes of " .. name .. ".")
  else
    CH.Print("No saved recipes for " .. name .. ".")
  end
  if CH.OnForget then CH.OnForget(name) end
end

function CH.SourceData(name)
  if not name or name == CH.player then return CH.me, "me" end
  local c = CH.db.chars[CH.realm][name]
  if c then return c, "alt" end
  return CH.others[name], "other"
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local ev = CreateFrame("Frame", "CraftHouseEvents")
CH.events = ev
ev.handlers = {}

function CH.On(event, fn)
  if not ev.handlers[event] then
    ev.handlers[event] = {}
    ev:RegisterEvent(event)
  end
  table.insert(ev.handlers[event], fn)
end

ev:SetScript("OnEvent", function()
  local list = ev.handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do fn(arg1, arg2, arg3, arg4) end
end)

-- Simple timers: CH.After(seconds, fn)
local timers = {}
local tf = CreateFrame("Frame")
tf:SetScript("OnUpdate", function()
  local now = GetTime()
  local i = 1
  while i <= table.getn(timers) do
    local t = timers[i]
    if now >= t[1] then
      table.remove(timers, i)
      t[2]()
    else
      i = i + 1
    end
  end
end)

function CH.After(sec, fn)
  table.insert(timers, { GetTime() + sec, fn })
end

CH.On("VARIABLES_LOADED", function()
  CH.realm  = GetRealmName()
  CH.player = UnitName("player")
  CH.InitDB()
  if CH.OnReady then CH.OnReady() end
end)

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

SLASH_CRAFTHOUSE1 = "/crafthouse"
SLASH_CRAFTHOUSE2 = "/ch"
SlashCmdList["CRAFTHOUSE"] = function(msg)
  local cmd, rest = msg or "", ""
  local _, _, a, b = strfind(cmd, "^(%S+)%s*(.*)$")
  if a then cmd, rest = strlower(a), b end

  if cmd == "" then
    CH.Toggle()
  elseif cmd == "send" and rest ~= "" then
    CH.SendKeyTo(rest, CH.DefaultShareProfs())
  elseif cmd == "guild" then
    CH.AnnounceGuild(true)
  elseif cmd == "replace" then
    CH.db.settings.replace = (CH.db.settings.replace == 1) and 0 or 1
    CH.Print("Replace Blizzard profession window: " .. (CH.db.settings.replace == 1 and "on" or "off"))
  elseif cmd == "autoopen" then
    CH.db.settings.autoopen = (CH.db.settings.autoopen == 1) and 0 or 1
    CH.Print("Open with profession window: " .. (CH.db.settings.autoopen == 1 and "on" or "off"))
  elseif cmd == "forget" and rest ~= "" then
    CH.Forget(strupper(strsub(rest, 1, 1)) .. strlower(strsub(rest, 2)))
  elseif cmd == "reset" then
    CH.db.pos = nil
    CH.db.scale = nil
    if CraftHouseFrame then
      CraftHouseFrame:ClearAllPoints()
      CraftHouseFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      CraftHouseFrame:SetScale(1)
    end
  else
    CH.Print("/ch  open/close the window")
    CH.Print("/ch send <name>  share your open profession (or all) with a player")
    CH.Print("/ch guild  share your recipes with your guild (nothing is shared automatically)")
    CH.Print("/ch replace  toggle replacing the Blizzard profession window")
    CH.Print("/ch autoopen  toggle opening with the profession window")
    CH.Print("/ch forget <name>  delete a player's shared recipes")
    CH.Print("/ch reset  reset window position and scale")
  end
end
