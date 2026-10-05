--[[ CraftHouse -- scan
     Reads the open profession window (TradeSkill API, or Craft API for
     Enchanting) into CH.me.profs[prof], including stats parsed from the
     item tooltips (enUS client). Also counts reagents in the bags.
]]--

local CH = CraftHouse

local tip = CreateFrame("GameTooltip", "CraftHouseTip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- "+5 Intellect", "... increase Intellect by 5" etc. (lower case)
local STATWORDS = {
  { "strength", "str" }, { "agility", "agi" }, { "stamina", "sta" },
  { "intellect", "int" }, { "spirit", "spi" },
  { "fire resistance", "fire" }, { "frost resistance", "frost" },
  { "nature resistance", "nat" }, { "shadow resistance", "shad" },
  { "arcane resistance", "arc" }, { "all resistances", "allres" },
  { "attack power", "ap" }, { "defense", "def" }, { "armor", "armor" },
  { "all stats", "allstats" }, { "health", "hp" }, { "mana", "mana" },
}

local SLOTS = {
  ["Head"] = "Head", ["Neck"] = "Neck", ["Shoulder"] = "Shoulder",
  ["Back"] = "Back", ["Chest"] = "Chest", ["Robe"] = "Chest",
  ["Wrist"] = "Wrist", ["Hands"] = "Hands", ["Waist"] = "Waist",
  ["Legs"] = "Legs", ["Feet"] = "Feet", ["Finger"] = "Finger",
  ["Trinket"] = "Trinket", ["Main Hand"] = "Weapon", ["One-Hand"] = "Weapon",
  ["Two-Hand"] = "Weapon", ["Off Hand"] = "Off Hand",
  ["Held In Off-hand"] = "Off Hand", ["Ranged"] = "Ranged",
  ["Thrown"] = "Ranged", ["Projectile"] = "Ranged", ["Shirt"] = "Other",
  ["Tabard"] = "Other",
}

local ENCHANT_SLOTS = {
  { "boots", "Feet" }, { "bracer", "Wrist" }, { "chest", "Chest" },
  { "cloak", "Back" }, { "gloves", "Hands" }, { "shield", "Off Hand" },
  { "2h weapon", "Weapon" }, { "weapon", "Weapon" },
}

local function AddStat(t, k, v)
  v = tonumber(v)
  if not v or v == 0 then return end
  if k == "allstats" then
    for _, s in ipairs({ "str", "agi", "sta", "int", "spi" }) do AddStat(t, s, v) end
    return
  end
  if k == "allres" then
    for _, s in ipairs({ "fire", "frost", "nat", "shad", "arc" }) do AddStat(t, s, v) end
    return
  end
  t[k] = (t[k] or 0) + v
end

-- Parses one tooltip line into stats. Returns true if it found something.
function CH.ParseLine(line, t)
  if not line or line == "" then return end
  local low = strlower(line)
  local _, a, b

  _, _, a = strfind(low, "^(%d+) armor$")
  if a then AddStat(t, "armor", a); return true end

  _, _, a = strfind(low, "%((%d+%.?%d*) damage per second%)")
  if a then AddStat(t, "dps", a); return true end

  _, _, a = strfind(low, "damage and healing done by magical spells and effects by up to (%d+)")
  if a then AddStat(t, "sp", a); AddStat(t, "heal", a); return true end

  _, _, b, a = strfind(low, "damage done by (%a+) spells and effects by up to (%d+)")
  if a then AddStat(t, "sp", a); return true end

  _, _, a = strfind(low, "healing done by spells and effects by up to (%d+)")
  if a then AddStat(t, "heal", a); return true end

  _, _, a = strfind(low, "chance to hit[%a ]* by (%d+)%%")
  if a then AddStat(t, "hit", a); return true end

  _, _, a = strfind(low, "critical strike[%a ]* by (%d+)%%")
  if a then AddStat(t, "crit", a); return true end

  _, _, a = strfind(low, "(%d+) mana per 5 sec")
  if a then AddStat(t, "mp5", a); return true end

  _, _, a = strfind(low, "increased defense %+(%d+)")
  if a then AddStat(t, "def", a); return true end

  local found
  for wi, w in ipairs(STATWORDS) do
    _, _, a = strfind(low, "%+(%d+) " .. w[1])
    if not a then _, _, a = strfind(low, w[1] .. " by (%d+)") end
    if not a then _, _, a = strfind(low, "(%d+) " .. w[1]) end
    if a and not (w[2] == "armor" and strfind(low, "armor penetration")) then
      AddStat(t, w[2], a)
      found = true
      -- "+3 Fire Resistance" must not count again as plain "+3 ..."
      low = gsub(low, w[1], "")
    end
  end
  return found
end

-- Category for items without a slot, from their tooltip text (lower case)
function CH.UseCategory(text, name)
  if strfind(text, "well fed") or strfind(text, "spend at least %d+ seconds eating") then
    return "Buff food"
  end
  if strfind(name, "poison") or strfind(text, "chance of poisoning") then return "Poison" end
  if strfind(text, "heals %d+ damage over") then return "Bandage" end
  local hp = strfind(text, "restores [%d to]+ health") or strfind(text, "%d+ health over")
  local mana = strfind(text, "restores [%d to]+ mana") or strfind(text, "%d+ mana over")
  if hp and mana then return "Health + Mana" end
  if hp then return "Health" end
  if mana then return "Mana" end
  if not strfind(text, "use:") then return "Material" end
  if strfind(text, "for %d+ min") or strfind(text, "for %d+ sec") or strfind(text, "increases") then
    if not strfind(text, "damage to") then return "Buff" end
  end
  if strfind(text, "damage") then return "Explosive" end
  return "Other"
end

-- Reads the currently set tooltip into rec fields l, c, t
local function ReadTooltip(rec, isCraft)
  local t = {}
  local cat
  local text = ""
  for i = 1, tip:NumLines() do
    local lf = getglobal("CraftHouseTipTextLeft" .. i)
    local rf = getglobal("CraftHouseTipTextRight" .. i)
    local left = lf and lf:GetText()
    local right = rf and rf:IsShown() and rf:GetText()
    if left then
      local _, _, lvl = strfind(left, "Requires Level (%d+)")
      if lvl then
        rec.l = tonumber(lvl)
      elseif i > 1 then
        text = text .. " " .. strlower(left)
        if not cat and SLOTS[left] then cat = SLOTS[left] end
        if not cat and strfind(left, "^%d+ Slot ") then cat = "Bag" end
        CH.ParseLine(left, t)
      end
    end
    if right and not cat and SLOTS[right] then cat = SLOTS[right] end
  end
  if isCraft then
    -- Enchants: "Enchant Bracer - Minor Stamina"
    cat = "Enchant"
  elseif not cat then
    cat = CH.UseCategory(text, strlower(rec.n or ""))
  end
  rec.c = cat or rec.c or "Other"
  rec.t = t
end

--------------------------------------------------------------------------
-- Profession scans
--------------------------------------------------------------------------

local function FinishProf(prof, rank, max, recipes, isCraft)
  local keys = {}
  for i, r in ipairs(recipes) do keys[i] = r.n end
  table.sort(keys)
  local p = CH.me.profs[prof] or {}
  p.rank, p.max, p.recipes = rank, max, recipes
  p.count = table.getn(recipes)
  p.hash = CH.Hash(table.concat(keys, ";"))
  p.craft = isCraft and 1 or nil
  p.time = time()
  p.sig = CH.Signature and CH.Signature(isCraft)
  CH.me.profs[prof] = p
  CH.openProf = prof
  CH.openCraft = isCraft
  if CH.OnScanned then CH.OnScanned(prof) end
end

function CH.ScanTradeSkill()
  local prof, rank, max = GetTradeSkillLine()
  if not prof or prof == "UNKNOWN" then return end

  -- Show everything: clear filters and expand all headers
  if SetTradeSkillSubClassFilter then SetTradeSkillSubClassFilter(0, 1, 1) end
  if SetTradeSkillInvSlotFilter then SetTradeSkillInvSlotFilter(0, 1, 1) end
  ExpandTradeSkillSubClass(0)

  local recipes = {}
  local header
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if kind == "header" then
      header = name
    elseif name then
      local link = GetTradeSkillItemLink(i)
      local rec = {
        n = name, id = CH.ItemID(link), q = CH.QualityFromLink(link),
        l = 0, d = kind, ic = GetTradeSkillIcon(i), link = link,
        mk = GetTradeSkillNumMade(i), r = {},
      }
      if rec.mk == 1 then rec.mk = nil end
      for j = 1, GetTradeSkillNumReagents(i) do
        local rname, _, rcount = GetTradeSkillReagentInfo(i, j)
        local rid = CH.ItemID(GetTradeSkillReagentItemLink(i, j))
        table.insert(rec.r, { rid, rcount, rname })
      end
      tip:ClearLines()
      tip:SetOwner(WorldFrame, "ANCHOR_NONE")
      tip:SetTradeSkillItem(i)
      ReadTooltip(rec)
      table.insert(recipes, rec)
    end
  end
  FinishProf(prof, rank, max, recipes)
end

function CH.ScanCraft()
  if not GetCraftDisplaySkillLine then return end
  local prof, rank, max = GetCraftDisplaySkillLine()
  if not prof then return end -- Beast Training has no skill line

  if ExpandCraftSkillLine then ExpandCraftSkillLine(0) end

  local recipes = {}
  for i = 1, GetNumCrafts() do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" then
      local link = GetCraftItemLink and GetCraftItemLink(i)
      local rec = {
        n = name, id = CH.ItemID(link), q = 1, l = 0, d = kind,
        ic = GetCraftIcon(i), link = link, r = {},
      }
      if rec.id > 0 then rec.q = CH.QualityFromLink(link) end
      for j = 1, GetCraftNumReagents(i) do
        local rname, _, rcount = GetCraftReagentInfo(i, j)
        local rid = GetCraftReagentItemLink and CH.ItemID(GetCraftReagentItemLink(i, j)) or 0
        table.insert(rec.r, { rid, rcount, rname })
      end
      tip:ClearLines()
      tip:SetOwner(WorldFrame, "ANCHOR_NONE")
      if rec.id > 0 then
        local _, _, hl = strfind(link, "(item:[%d:]+)")
        tip:SetHyperlink(hl)
        ReadTooltip(rec)
      else
        tip:SetCraftSpell(i)
        ReadTooltip(rec, true)
        local lname = strlower(name)
        for _, s in ipairs(ENCHANT_SLOTS) do
          if strfind(lname, s[1], 1, true) then rec.sl = s[2]; break end
        end
      end
      table.insert(recipes, rec)
    end
  end
  FinishProf(prof, rank, max, recipes, true)
end

--------------------------------------------------------------------------
-- Bag contents (itemID -> count), refreshed lazily
--------------------------------------------------------------------------

CH.bags = {}
CH.bagsDirty = true

function CH.BagCounts()
  if not CH.bagsDirty then return CH.bags end
  local counts = {}
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      if link then
        local id = CH.ItemID(link)
        local _, n = GetContainerItemInfo(bag, slot)
        local _, _, name = strfind(link, "%[(.+)%]")
        counts[id] = (counts[id] or 0) + (n or 1)
        if name then counts["n:" .. name] = (counts["n:" .. name] or 0) + (n or 1) end
      end
    end
  end
  CH.bags = counts
  CH.bagsDirty = false
  return counts
end

-- How many times rec can be crafted from what is in the bags
function CH.Available(rec)
  local bags = CH.BagCounts()
  local best
  for _, r in ipairs(rec.r or {}) do
    local have = (r[1] and r[1] > 0) and bags[r[1]] or bags["n:" .. (r[3] or "")] or 0
    local n = math.floor(have / (r[2] or 1))
    if not best or n < best then best = n end
  end
  return best or 0
end

CH.On("BAG_UPDATE", function()
  CH.bagsDirty = true
  if CH.OnBagsChanged and not CH.bagTimer then
    CH.bagTimer = true
    CH.After(0.5, function()
      CH.bagTimer = nil
      CH.OnBagsChanged()
    end)
  end
end)
