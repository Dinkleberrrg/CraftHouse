--[[ CraftHouse -- craft
     Profession window events, crafting (also from a closed window: the
     profession gets opened first and the craft runs right after the scan),
     and the to-do queue.
]]--

local CH = CraftHouse

--------------------------------------------------------------------------
-- Profession window open/close
--------------------------------------------------------------------------

-- Keeps the Blizzard window open (crafting needs it) but out of sight.
-- Hiding it would close the profession.
local hider = CreateFrame("Frame")
hider:Hide()
hider:SetScript("OnUpdate", function()
  local f = this.target
  if not f or not f:IsShown() then this:Hide(); return end
  local _, _, _, x = f:GetPoint(1)
  if x ~= -5000 then
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -5000, 0)
  end
end)

local function HideBlizzard(name)
  if CH.db.settings.replace ~= 1 then return end
  local f = getglobal(name)
  if not f then return end
  hider.target = f
  hider:Show()
end

local function OnProfOpened(isCraft)
  if CH.ScanTimer then return end
  CH.ScanTimer = true
  -- One frame later: the list is filled and Blizzard's window placed
  CH.After(0.05, function()
    CH.ScanTimer = nil
    if isCraft then CH.ScanCraft() else CH.ScanTradeSkill() end
    if not CH.openProf then return end
    if CH.db.settings.autoopen == 1 or CH.db.settings.replace == 1 then
      HideBlizzard(isCraft and "CraftFrame" or "TradeSkillFrame")
      if CH.IsShown() then CH.Refresh() else CH.Show(CH.player, CH.openProf) end
    elseif CH.IsShown() then
      CH.Refresh()
    end
    if CH.pending and CH.pending.prof == CH.openProf then
      local p = CH.pending
      CH.pending = nil
      CH.Craft(p.rec, p.count, p.queueEntry)
    end
  end)
end

CH.On("TRADE_SKILL_SHOW", function() OnProfOpened(false) end)
CH.On("CRAFT_SHOW", function() OnProfOpened(true) end)

-- Rescan when skill ranks or recipes change (skill-up, new recipe)
-- The *_UPDATE events also fire for our own scan (expanding headers) and
-- for every bag change. Rescan only when rank or recipe count changed,
-- otherwise the scan would loop and the selection would get lost.
local function Signature(isCraft)
  if isCraft then
    local _, rank = GetCraftDisplaySkillLine()
    return (rank or 0) .. ":" .. GetNumCrafts()
  end
  local _, rank = GetTradeSkillLine()
  return (rank or 0) .. ":" .. GetNumTradeSkills()
end

local function Rescan(isCraft)
  if not CH.openProf or (CH.openCraft and true or false) ~= isCraft or CH.rescan then return end
  CH.rescan = true
  CH.After(0.3, function()
    CH.rescan = nil
    if not CH.openProf or (CH.openCraft and true or false) ~= isCraft then return end
    local p = CH.me.profs[CH.openProf]
    if p and p.sig == Signature(isCraft) then return end
    if isCraft then CH.ScanCraft() else CH.ScanTradeSkill() end
    if CH.IsShown() then CH.Refresh() end
  end)
end

CH.On("TRADE_SKILL_UPDATE", function() Rescan(false) end)
CH.On("CRAFT_UPDATE", function() Rescan(true) end)
CH.Signature = Signature

local function OnProfClosed()
  CH.openProf = nil
  CH.openCraft = nil
  hider:Hide()
  if CH.IsShown() then CH.Refresh() end
end
CH.On("TRADE_SKILL_CLOSE", OnProfClosed)
CH.On("CRAFT_CLOSE", OnProfClosed)

-- Closes the profession that is open in the background
function CH.CloseProfession()
  if not CH.openProf then return end
  if CH.openCraft then CloseCraft() else CloseTradeSkill() end
end

--------------------------------------------------------------------------
-- Crafting
--------------------------------------------------------------------------

local function FindIndex(name, isCraft)
  if isCraft then
    for i = 1, GetNumCrafts() do
      local n, _, kind = GetCraftInfo(i)
      if n == name and kind ~= "header" then return i end
    end
  else
    for i = 1, GetNumTradeSkills() do
      local n, kind = GetTradeSkillInfo(i)
      if n == name and kind ~= "header" then return i end
    end
  end
end

-- rec must be one of our own recipes (rec.prof set by the browser)
function CH.Craft(rec, count, queueEntry)
  local prof = rec.prof
  if not prof then return end
  count = count or 1

  if CH.openProf ~= prof then
    CH.pending = { prof = prof, rec = rec, count = count, queueEntry = queueEntry }
    CastSpellByName(CH.OPENSPELL[prof] or prof)
    return
  end

  local avail = CH.Available(rec)
  if avail < 1 then
    CH.Print("Missing reagents for " .. rec.n .. ".")
    return
  end
  if count > avail then count = avail end

  local idx = FindIndex(rec.n, CH.openCraft)
  if not idx then
    CH.Print(rec.n .. " not found in " .. prof .. ".")
    return
  end

  CH.casting = { name = rec.n, left = count, entry = queueEntry }
  if CH.openCraft then
    -- The Craft API makes one at a time
    CH.casting.left = 1
    DoCraft(idx)
  else
    DoTradeSkill(idx, count)
  end
end

-- Count finished crafts to tick off queue entries
CH.On("SPELLCAST_START", function(spell)
  if CH.casting and spell ~= CH.casting.name then CH.casting = nil end
end)

local function Interrupted()
  if CH.casting then CH.casting.cancel = true end
end
CH.On("SPELLCAST_INTERRUPTED", Interrupted)
CH.On("SPELLCAST_FAILED", Interrupted)

CH.On("SPELLCAST_STOP", function()
  local c = CH.casting
  if not c then return end
  -- INTERRUPTED may arrive right after STOP: decide a moment later
  CH.After(0.2, function()
    if c.cancel then
      if CH.casting == c then CH.casting = nil end
      return
    end
    if c.entry then CH.QueueDone(c.entry, 1) end
    c.left = c.left - 1
    if c.left <= 0 and CH.casting == c then CH.casting = nil end
    if CH.IsShown() then CH.Refresh() end
  end)
end)

--------------------------------------------------------------------------
-- Queue (to-do list)
--------------------------------------------------------------------------

-- list defaults to the own queue; also used for lists for/from others
function CH.QueueAdd(rec, count, list)
  list = list or CH.queue
  count = count or 1
  for _, e in ipairs(list) do
    if e.prof == rec.prof and e.name == rec.n then
      e.count = e.count + count
      if CH.IsShown() then CH.Refresh() end
      return
    end
  end
  table.insert(list, { prof = rec.prof, name = rec.n, count = count })
  if CH.IsShown() then CH.Refresh() end
end

function CH.QueueDone(entry, n)
  for i, e in ipairs(CH.queue) do
    if e == entry then
      e.count = e.count - n
      if e.count <= 0 then table.remove(CH.queue, i) end
      return
    end
  end
end

function CH.QueueRemove(i, list)
  table.remove(list or CH.queue, i)
  if CH.IsShown() then CH.Refresh() end
end

-- data = whose recipes (default: own)
function CH.QueueRecipe(e, data)
  local p = (data or CH.me).profs[e.prof]
  if not p then return end
  for _, r in ipairs(p.recipes) do
    if r.n == e.name then
      r.prof = e.prof
      return r
    end
  end
end

-- Total reagents the whole queue needs: list of {id, name, need, have}
function CH.QueueReagents(list, data)
  local need, order = {}, {}
  for _, e in ipairs(list or CH.queue) do
    local rec = CH.QueueRecipe(e, data)
    if rec then
      local times = e.count
      for _, r in ipairs(rec.r) do
        local key = (r[1] and r[1] > 0) and r[1] or ("n:" .. (r[3] or "?"))
        if not need[key] then
          need[key] = { id = r[1], name = r[3], need = 0 }
          table.insert(order, key)
        end
        need[key].need = need[key].need + r[2] * times
      end
    end
  end
  local bags = CH.BagCounts()
  local out = {}
  for _, key in ipairs(order) do
    local v = need[key]
    v.have = bags[key] or bags["n:" .. (v.name or "")] or 0
    table.insert(out, v)
  end
  return out
end

-- Crafts the first queue entry that can be made, preferring the
-- profession that is open right now.
function CH.QueueNext()
  local fallback
  for _, e in ipairs(CH.queue) do
    local rec = CH.QueueRecipe(e)
    if rec and CH.Available(rec) > 0 then
      if e.prof == CH.openProf then
        CH.Craft(rec, e.count, e)
        return
      end
      fallback = fallback or { rec, e }
    end
  end
  if fallback then
    local rec, e = fallback[1], fallback[2]
    CH.Craft(rec, e.count, e)
  else
    CH.Print("Nothing in the queue can be crafted with what is in your bags.")
  end
end

--------------------------------------------------------------------------
-- To-do lists for and from other players
--   CH.lists.out[name] = { entries }          list I build for name
--   CH.lists.inc[name] = { time, items = { entries } }   list name sent me
--------------------------------------------------------------------------

-- On login: tell about to-do lists that are waiting (e.g. from your main)
CH.On("PLAYER_ENTERING_WORLD", function()
  if CH.listNotice then return end
  CH.listNotice = true
  CH.After(6, function()
    for name, l in pairs(CH.lists.inc) do
      CH.Print("To-do list from " .. name .. " (" .. table.getn(l.items) .. " recipes) is waiting. /ch, then pick it in the queue panel.")
    end
  end)
end)

function CH.OutList(name)
  if not CH.lists.out[name] then CH.lists.out[name] = {} end
  return CH.lists.out[name]
end

-- Moves every recipe I know from a received list into my queue.
-- Returns how many entries were moved.
function CH.TakeOver(name)
  local l = CH.lists.inc[name]
  if not l then return 0 end
  local moved, i = 0, 1
  while i <= table.getn(l.items) do
    local e = l.items[i]
    local rec = CH.QueueRecipe(e)
    if rec then
      CH.QueueAdd(rec, e.count)
      table.remove(l.items, i)
      moved = moved + 1
    else
      i = i + 1
    end
  end
  if table.getn(l.items) == 0 then CH.lists.inc[name] = nil end
  if CH.IsShown() then CH.Refresh() end
  return moved
end
