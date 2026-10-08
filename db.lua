--[[ CraftHouse -- db
     Local copy of all profession recipes (data.lua, generated from the
     OctoWoW client files by tools/gen_db.py). It lets a share key carry
     the recipes themselves: every recipe of a profession has a fixed
     position, and a key is a bit mask over those positions.

     data.lua row: { spell, name, item, made, yellow, grey, reagents,
                     tools, focus, quality, level, category, slot, stats }

     Item stats are not in the client files. They come from scans
     (learned into data.lua when it is regenerated) and, at runtime, from
     the tooltips of items your client has already seen (CH.db.learned).
]]--

local CH = CraftHouse

local DB = CraftHouse_DB or { profs = {}, items = {} }
CH.dbVersion = CraftHouse_DB_VERSION or "none"

local bySpell, byItem, byName = {}, {}, {}
for prof, list in pairs(DB.profs) do
  bySpell[prof], byItem[prof], byName[prof] = {}, {}, {}
  for i, row in ipairs(list) do
    bySpell[prof][row[1]] = i
    if row[3] > 0 and not byItem[prof][row[3]] then byItem[prof][row[3]] = i end
    if not byName[prof][row[2]] then byName[prof][row[2]] = i end
  end
end

function CH.DBHas(prof) return DB.profs[prof] ~= nil end

-- Position of a scanned recipe in the local copy (by product, else name)
function CH.DBMatch(prof, rec)
  if not byName[prof] then return end
  if rec.id and rec.id > 0 and byItem[prof][rec.id] then return byItem[prof][rec.id] end
  return byName[prof][rec.n]
end

function CH.DBSpell(prof, i)
  local row = DB.profs[prof] and DB.profs[prof][i]
  return row and row[1]
end

-- true if the local copy already knows stats (or the level) of position i
function CH.DBHasStats(prof, i)
  local row = DB.profs[prof] and DB.profs[prof][i]
  return row and ((row[14] and row[14] ~= "") or (row[11] and row[11] > 0))
end

function CH.DBItemName(id)
  return id and DB.items[id]
end

--------------------------------------------------------------------------
-- Bit masks: positions 1..n, 6 bits per character
--------------------------------------------------------------------------

local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local VALUE = {}
for i = 1, 64 do VALUE[strsub(ALPHA, i, i)] = i - 1 end
local POW = { [0] = 1, 2, 4, 8, 16, 32 }

-- set = { [position] = true }
function CH.EncodeMask(set, n)
  local out = {}
  local chars = math.ceil(n / 6)
  for c = 0, chars - 1 do
    local v = 0
    for b = 0, 5 do
      if set[c * 6 + b + 1] then v = v + POW[b] end
    end
    out[c + 1] = strsub(ALPHA, v + 1, v + 1)
  end
  local s = table.concat(out)
  return (gsub(s, "A+$", ""))
end

-- returns a list of positions
function CH.DecodeMask(mask)
  local out = {}
  for c = 1, strlen(mask or "") do
    local v = VALUE[strsub(mask, c, c)] or 0
    for b = 5, 0, -1 do
      local p = POW[b]
      if v >= p then
        v = v - p
        table.insert(out, (c - 1) * 6 + b + 1)
      end
    end
  end
  table.sort(out)
  return out
end

-- Mask + count of recipes not in the local copy, from own scanned recipes
function CH.MaskFor(prof, recipes)
  local set, unmapped = {}, 0
  for _, r in ipairs(recipes or {}) do
    local i = CH.DBMatch(prof, r)
    if i then set[i] = true else unmapped = unmapped + 1 end
  end
  return CH.EncodeMask(set, table.getn(DB.profs[prof] or {})), unmapped
end

--------------------------------------------------------------------------
-- Recipes from the local copy
--------------------------------------------------------------------------

local function ParseStats(s)
  local t = {}
  for _, part in ipairs((CH.Split(s or "", "/"))) do
    local _, _, k, v = strfind(part, "^(%a+)=([%d%.]+)$")
    if k then t[k] = tonumber(v) end
  end
  return t
end

-- Skill-up colour of a recipe for a given skill rank
function CH.Difficulty(rank, yellow, grey)
  if not rank or not yellow or not grey or grey == 0 then return end
  if rank < yellow then return "optimal" end
  if rank < math.floor((yellow + grey) / 2) then return "medium" end
  if rank < grey then return "easy" end
  return "trivial"
end

-- Builds a recipe table (same fields as a scanned one) for position i
function CH.DBRecipe(prof, i, rank)
  local row = DB.profs[prof] and DB.profs[prof][i]
  if not row then return end
  local rec = {
    n = row[2], id = row[3], sid = row[1], ix = i, y = row[5], g = row[6],
    mk = (row[4] > 1) and row[4] or nil, r = {},
    q = row[10] or 1, l = row[11] or 0, c = row[12], sl = row[13], t = ParseStats(row[14]),
  }
  for _, part in ipairs((CH.Split(row[7], "/"))) do
    local _, _, id, n = strfind(part, "^(%d+)%*(%d+)$")
    if id then
      id = tonumber(id)
      table.insert(rec.r, { id, tonumber(n), DB.items[id] })
    end
  end
  local tools = {}
  for _, id in ipairs((CH.Split(row[8], ","))) do
    if tonumber(id) then table.insert(tools, DB.items[tonumber(id)] or ("Item #" .. id)) end
  end
  if row[9] and row[9] ~= "" then table.insert(tools, row[9]) end
  if table.getn(tools) > 0 then rec.tools = table.concat(tools, ", ") end
  if not rec.c then
    rec.c = (rec.id == 0) and "Enchant" or "Other"
  end
  if rec.c == "Enchant" and not rec.sl then
    local lname = strlower(rec.n)
    for _, s in ipairs({ { "boots", "Feet" }, { "bracer", "Wrist" }, { "chest", "Chest" },
                         { "cloak", "Back" }, { "gloves", "Hands" }, { "shield", "Off Hand" },
                         { "weapon", "Weapon" } }) do
      if strfind(lname, s[1], 1, true) then rec.sl = s[2]; break end
    end
  end
  rec.d = CH.Difficulty(rank, rec.y, rec.g)
  CH.ApplyLearned(rec)
  return rec
end

-- Recipes for a mask
function CH.RecipesFromMask(prof, mask, rank)
  local out = {}
  for _, i in ipairs(CH.DecodeMask(mask)) do
    local rec = CH.DBRecipe(prof, i, rank)
    if rec then table.insert(out, rec) end
  end
  return out
end

--------------------------------------------------------------------------
-- Learning stats at runtime from items the client has cached
--------------------------------------------------------------------------

local tried = {}

function CH.ApplyLearned(rec)
  if not CH.db or not rec.id or rec.id == 0 then return end
  local L = CH.db.learned and CH.db.learned[rec.id]
  if not L then return end
  if (not rec.t or not next(rec.t)) and L.t then rec.t = L.t end
  if (rec.l or 0) == 0 and L.l then rec.l = L.l end
  if (not rec.q or rec.q == 1) and L.q then rec.q = L.q end
  if (not rec.c or rec.c == "Other") and L.c then rec.c = L.c end
end

-- Reads stats from the tooltip of a cached item (no server query)
function CH.Learn(rec)
  if not rec.id or rec.id == 0 or tried[rec.id] then return end
  if rec.t and next(rec.t) and (rec.l or 0) > 0 then return end
  tried[rec.id] = true
  if not CH.db.learned then CH.db.learned = {} end
  if CH.db.learned[rec.id] then CH.ApplyLearned(rec); return end
  local name, _, q = GetItemInfo(rec.id)
  if not name then tried[rec.id] = nil; return end
  local tmp = { n = rec.n, c = nil }
  CH.ReadItemTooltip("item:" .. rec.id .. ":0:0:0", tmp)
  CH.db.learned[rec.id] = { t = tmp.t, l = tmp.l, q = q, c = tmp.c }
  CH.ApplyLearned(rec)
end

-- Saves stats of own scanned recipes, so data.lua can learn them later
function CH.LearnFromScan(recipes)
  if not CH.db.learned then CH.db.learned = {} end
  for _, r in ipairs(recipes) do
    if r.id and r.id > 0 and r.t and next(r.t) then
      CH.db.learned[r.id] = { t = r.t, l = r.l, q = r.q, c = r.c }
    end
  end
end
