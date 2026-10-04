--[[ CraftHouse -- ui
     Auction-house style browser: source (you / alts / other players),
     profession tabs, search, level range, quality, stat filter, category
     list, result list, details with craft buttons, queue and sharing.
]]--

local CH = CraftHouse

local W, H     = 840, 530
local ROWS     = 15
local ROWH     = 18
local QROWS    = 9
local MAXPROFS = 6
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ENCHANT_ICON = "Interface\\Icons\\Spell_Holy_GreaterHeal"

local view = {
  src = nil, prof = "All", search = "", lmin = nil, lmax = nil, q = 0,
  stat = nil, statMin = 1, cat = "All", mats = false, skill = false,
  sort = "level", sel = nil,
  list = nil,  -- nil = own queue, { kind = "out"/"in", name = player }
}
CH.view = view

local results = {}
local main

--------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------

local BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local PANEL = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function Panel(parent, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f:SetWidth(w); f:SetHeight(h)
  f:SetBackdrop(PANEL)
  f:SetBackdropColor(0, 0, 0, 0.6)
  f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  return f
end

local function Text(parent, font, x, y, w, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if w then fs:SetWidth(w) end
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local btnCount = 0
local function Button(parent, text, x, y, w, h, onClick)
  btnCount = btnCount + 1
  local b = CreateFrame("Button", "CraftHouseButton" .. btnCount, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetWidth(w); b:SetHeight(h or 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function EditBox(parent, x, y, w, numeric, onChange)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  e:SetWidth(w); e:SetHeight(20)
  e:SetAutoFocus(false)
  e:SetFontObject(ChatFontNormal)
  e:SetTextInsets(5, 5, 0, 0)
  e:SetBackdrop(PANEL)
  e:SetBackdropColor(0, 0, 0, 0.8)
  e:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  if numeric then e:SetNumeric(true); e:SetMaxLetters(3) end
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  e:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  e:SetScript("OnTabPressed", function() this:ClearFocus() end)
  if onChange then
    e:SetScript("OnTextChanged", function() onChange(this:GetText()) end)
  end
  return e
end

local cbCount = 0
local function Check(parent, label, x, y, onClick)
  cbCount = cbCount + 1
  local name = "CraftHouseCheck" .. cbCount
  local c = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  c:SetWidth(24); c:SetHeight(24)
  getglobal(name .. "Text"):SetText(label)
  c:SetScript("OnClick", function() onClick(this:GetChecked() and true or false) end)
  return c
end

local function Tip(frame, text)
  frame:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--------------------------------------------------------------------------
-- Popup menu
--------------------------------------------------------------------------

local menu
local MENU_MAX = 24

local function Menu(anchor, items, onSelect)
  if not menu then
    menu = CreateFrame("Frame", "CraftHouseMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop(PANEL)
    menu:SetBackdropColor(0, 0, 0, 0.95)
    menu:EnableMouse(true)
    menu.buttons = {}
    for i = 1, MENU_MAX do
      local b = CreateFrame("Button", nil, menu)
      b:SetHeight(16)
      b:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - (i - 1) * 16)
      b:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", b, "LEFT", 4, 0)
      b.text:SetJustifyH("LEFT")
      b:SetScript("OnClick", function()
        menu:Hide()
        if menu.onSelect then menu.onSelect(this.value) end
      end)
      menu.buttons[i] = b
    end
  end
  if menu:IsShown() and menu.anchor == anchor then menu:Hide(); return end
  menu.anchor = anchor
  menu.onSelect = onSelect
  local width = 120
  local n = math.min(table.getn(items), MENU_MAX)
  for i = 1, MENU_MAX do
    local b = menu.buttons[i]
    local it = items[i]
    if i <= n then
      b.value = it.value
      b.text:SetText((it.checked and "|cffffd100> |r" or "   ") .. it.text)
      width = math.max(width, b.text:GetStringWidth() + 24)
      b:Show()
    else
      b:Hide()
    end
  end
  menu:SetWidth(width)
  menu:SetHeight(n * 16 + 12)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:Show()
end

--------------------------------------------------------------------------
-- Data for the current view
--------------------------------------------------------------------------

local function SrcData()
  return CH.SourceData(view.src)
end

local function IsMine()
  return view.src == nil or view.src == CH.player
end

local function ItemName(id, fallback)
  if id and id > 0 then
    local n = GetItemInfo(id)
    if n then return n end
  end
  return fallback or ("Item #" .. (id or "?"))
end

local function RecIcon(rec)
  if rec.ic then return rec.ic end
  if rec.id and rec.id > 0 then
    local _, _, _, _, _, _, _, _, tex = GetItemInfo(rec.id)
    if tex then return tex end
  end
  if rec.c == "Enchant" then return ENCHANT_ICON end
  return QUESTION
end

local function StatText(rec)
  local parts = {}
  for _, s in ipairs(CH.STATS) do
    local v = rec.t and rec.t[s.key]
    if v then table.insert(parts, "+" .. v .. " " .. CH.STATSHORT[s.key]) end
  end
  if rec.t and rec.t.hp then table.insert(parts, rec.t.hp .. " HP") end
  return table.concat(parts, " ")
end

local DIFFORDER = { optimal = 4, medium = 3, easy = 2, trivial = 1 }

-- Used on the profession tabs when the full names do not fit
local SHORTPROF = {
  ["Leatherworking"] = "Leather", ["Blacksmithing"] = "Smithing",
  ["Engineering"] = "Engineer", ["Enchanting"] = "Enchant",
  ["Jewelcrafting"] = "Jewelcraft", ["First Aid"] = "First Aid",
}

local function Matches(rec)
  if view.search ~= "" and not strfind(strlower(rec.n), view.search, 1, true) then return end
  local lvl = rec.l or 0
  if view.lmin and lvl < view.lmin then return end
  if view.lmax and lvl > view.lmax then return end
  if view.q > 0 and (rec.q or 1) < view.q then return end
  if view.stat and ((rec.t and rec.t[view.stat]) or 0) < (view.statMin or 1) then return end
  if view.cat ~= "All" and rec.c ~= view.cat and rec.sl ~= view.cat then return end
  if view.skill and rec.d and (DIFFORDER[rec.d] or 0) < 2 then return end
  if view.mats and IsMine() and CH.Available(rec) < 1 then return end
  return true
end

local function Sorter(a, b)
  if view.sort == "name" then return a.n < b.n end
  if view.skill then
    local da, db = DIFFORDER[a.d] or 0, DIFFORDER[b.d] or 0
    if da ~= db then return da > db end
    if (a.l or 0) ~= (b.l or 0) then return (a.l or 0) < (b.l or 0) end
    return a.n < b.n
  end
  if view.sort == "stat" and view.stat then
    local va, vb = (a.t and a.t[view.stat]) or 0, (b.t and b.t[view.stat]) or 0
    if va ~= vb then return va > vb end
  end
  if (a.l or 0) ~= (b.l or 0) then return (a.l or 0) > (b.l or 0) end
  if (a.q or 1) ~= (b.q or 1) then return (a.q or 1) > (b.q or 1) end
  return a.n < b.n
end

local function BuildResults()
  results = {}
  local data = SrcData()
  if not data or not data.profs then return end
  for prof, p in pairs(data.profs) do
    if view.prof == "All" or view.prof == prof then
      for _, rec in ipairs(p.recipes or {}) do
        rec.prof = prof
        if Matches(rec) then table.insert(results, rec) end
      end
    end
  end
  table.sort(results, Sorter)
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local ui = {}

local function SetTooltipFor(rec)
  local hl, _
  if rec.link then
    _, _, hl = strfind(rec.link, "(item:[%d:]+)")
  elseif rec.id and rec.id > 0 and GetItemInfo(rec.id) then
    hl = "item:" .. rec.id .. ":0:0:0"
  end
  if hl then
    GameTooltip:SetHyperlink(hl)
  else
    GameTooltip:SetText(CH.Color(rec.q) .. rec.n .. "|r")
    local st = StatText(rec)
    if st ~= "" then GameTooltip:AddLine(st, 1, 1, 1, 1) end
    if (rec.l or 0) > 0 then GameTooltip:AddLine("Requires Level " .. rec.l, 1, 1, 1) end
  end
  GameTooltip:AddLine(rec.prof, 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function CreateRows(parent)
  ui.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROWH)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -22 - (i - 1) * ROWH)
    r:SetPoint("RIGHT", parent, "RIGHT", -26, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints(r)
    r.sel:SetTexture(1, 0.82, 0, 0.18)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetWidth(16); r.icon:SetHeight(16)
    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.diff = r:CreateTexture(nil, "ARTWORK")
    r.diff:SetWidth(6); r.diff:SetHeight(14)
    r.diff:SetPoint("LEFT", r, "LEFT", 20, 0)
    r.diff:SetTexture(1, 1, 1, 1)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r, "LEFT", 30, 0)
    r.name:SetWidth(180); r.name:SetHeight(ROWH); r.name:SetJustifyH("LEFT")
    r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.lvl:SetPoint("LEFT", r, "LEFT", 212, 0)
    r.lvl:SetWidth(26); r.lvl:SetJustifyH("CENTER")
    r.stats = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.stats:SetPoint("LEFT", r, "LEFT", 242, 0)
    r.stats:SetWidth(150); r.stats:SetHeight(ROWH); r.stats:SetJustifyH("LEFT")
    r.stats:SetTextColor(0.6, 1, 0.6)
    r.avail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.avail:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.avail:SetWidth(30); r.avail:SetJustifyH("RIGHT")
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function()
      local rec = this.rec
      if not rec then return end
      if IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
        ChatFrameEditBox:Insert(rec.link or rec.n)
        return
      end
      view.sel = rec
      if arg1 == "RightButton" then CH.AddToList(rec, 1) end
      CH.Refresh()
    end)
    r:SetScript("OnEnter", function()
      if not this.rec then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      SetTooltipFor(this.rec)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.rows[i] = r
  end
end

function CH.UpdateList()
  local sf = ui.scroll
  local n = table.getn(results)
  FauxScrollFrame_Update(sf, n, ROWS, ROWH)
  local offset = FauxScrollFrame_GetOffset(sf)
  local mine = IsMine()
  for i = 1, ROWS do
    local r = ui.rows[i]
    local rec = results[offset + i]
    r.rec = rec
    if rec then
      r.icon:SetTexture(RecIcon(rec))
      r.name:SetText(CH.Color(rec.q) .. rec.n .. "|r" .. (rec.mk and (" |cffaaaaaax" .. rec.mk .. "|r") or ""))
      r.lvl:SetText((rec.l or 0) > 0 and rec.l or "")
      r.stats:SetText(StatText(rec))
      local d = rec.d and CH.DIFF[rec.d]
      if d then r.diff:SetVertexColor(d[1], d[2], d[3]); r.diff:Show() else r.diff:Hide() end
      if mine then
        local a = CH.Available(rec)
        r.avail:SetText(a > 0 and ("|cff20ff20" .. a .. "|r") or "|cff6666660|r")
      else
        r.avail:SetText("")
      end
      if view.sel == rec then r.sel:Show() else r.sel:Hide() end
      r:Show()
    else
      r:Hide()
    end
  end
  ui.count:SetText(n .. " recipes")
end

--------------------------------------------------------------------------
-- Details (bottom)
--------------------------------------------------------------------------

local function UpdateDetails()
  local rec = view.sel
  local d = ui.details
  local mine = IsMine()
  if not rec then
    d.title:SetText("|cff888888Select a recipe. Right-click adds it to the queue.|r")
    d.reag:SetText("")
    d.icon:Hide()
    d.craft:Hide(); d.all:Hide(); d.queue:Hide(); d.num:Hide(); d.ask:Hide()
    return
  end
  d.icon:SetTexture(RecIcon(rec)); d.icon:Show()
  local extra = (rec.l or 0) > 0 and ("  |cffaaaaaaLevel " .. rec.l .. "|r") or ""
  d.title:SetText(CH.Color(rec.q) .. rec.n .. "|r" .. extra .. "  |cff888888" .. (rec.prof or "") .. "|r")
  local bags = CH.BagCounts()
  local lines = {}
  for _, r in ipairs(rec.r or {}) do
    local name = r[3] or ItemName(r[1])
    if IsMine() then
      local have = (r[1] and r[1] > 0) and bags[r[1]] or bags["n:" .. (r[3] or "")] or 0
      local col = have >= r[2] and "|cff20ff20" or "|cffff4040"
      table.insert(lines, col .. have .. "/" .. r[2] .. "|r " .. name)
    else
      table.insert(lines, r[2] .. "x " .. name)
    end
  end
  if table.getn(lines) > 5 then
    local more = table.getn(lines) - 4
    while table.getn(lines) > 4 do table.remove(lines) end
    table.insert(lines, "|cff888888+" .. more .. " more|r")
  end
  d.reag:SetText(table.concat(lines, "\n"))
  if mine then
    d.craft:Show(); d.all:Show(); d.queue:Show(); d.num:Show(); d.ask:Hide()
    d.queue:SetText("+ Queue")
    local a = CH.Available(rec)
    d.all:SetText("All (" .. a .. ")")
    if CH.openProf == rec.prof then d.craft:SetText("Craft") else d.craft:SetText("Open + Craft") end
  else
    d.craft:Hide(); d.all:Hide(); d.queue:Show(); d.num:Show(); d.ask:Show()
    d.queue:SetText("+ To-do list")
  end
end

--------------------------------------------------------------------------
-- Queue (right)
--------------------------------------------------------------------------

-- The list shown in the queue panel: entries, whose recipes, kind, player
local function CurrentList()
  local L = view.list
  if L and L.kind == "out" then
    return CH.OutList(L.name), (CH.SourceData(L.name)), "out", L.name
  end
  if L and L.kind == "in" then
    local l = CH.lists.inc[L.name]
    if l then return l.items, CH.me, "in", L.name end
    view.list = nil
  end
  return CH.queue, CH.me, "me"
end
CH.CurrentList = CurrentList

-- Right-click / "+ Queue": own recipes go to the own queue, another
-- player's recipes to the to-do list for that player.
function CH.AddToList(rec, count)
  if IsMine() then
    if view.list and view.list.kind == "out" then view.list = nil end
    CH.QueueAdd(rec, count)
  else
    view.list = { kind = "out", name = view.src }
    CH.QueueAdd(rec, count, CH.OutList(view.src))
  end
end

local function UpdateQueue()
  local q = ui.queue
  local list, data, kind, who = CurrentList()
  local n = table.getn(list)

  if kind == "me" then
    q.listBtn:SetText("My queue")
    q.b1:SetText("Craft next"); q.b2:Show()
    q.mtitle:SetText("Still missing for the queue")
  elseif kind == "out" then
    q.listBtn:SetText("For " .. who)
    q.b1:SetText("Send list"); q.b2:Hide()
    q.mtitle:SetText("Reagents " .. who .. " needs")
  else
    q.listBtn:SetText("From " .. who)
    q.b1:SetText("Take over"); q.b2:Hide()
    q.mtitle:SetText("Still missing for this list")
  end

  for i = 1, QROWS do
    local row = q.rows[i]
    local e = list[i]
    row.entry = e
    row.index = i
    if e then
      local rec = CH.QueueRecipe(e, data)
      local col = "|cffffffff"
      local suffix = ""
      if kind == "me" then
        if not (rec and CH.Available(rec) > 0) then col = "|cff888888" end
      elseif kind == "in" then
        if not rec then col = "|cffff6060"; suffix = " (unknown)"
        elseif CH.Available(rec) < 1 then col = "|cff888888" end
      end
      row.text:SetText(col .. e.count .. "x " .. e.name .. suffix .. "|r")
      row:Show()
    else
      row:Hide()
    end
  end
  local empty = ""
  if n == 0 then
    if kind == "out" then
      empty = "|cff888888Right-click " .. who .. "'s recipes to add them.|r"
    else
      empty = "|cff888888Empty. Right-click a recipe to add it.|r"
    end
  end
  q.more:SetText(n > QROWS and ("+" .. (n - QROWS) .. " more") or empty)

  local lines = {}
  for _, v in ipairs(CH.QueueReagents(list, data)) do
    local name = v.name or ItemName(v.id)
    if kind == "out" then
      table.insert(lines, v.need .. " " .. name .. " |cff888888(you have " .. v.have .. ")|r")
    else
      local missing = v.need - v.have
      if missing > 0 then
        table.insert(lines, "|cffff4040" .. missing .. "|r " .. name)
      end
    end
  end
  if table.getn(lines) == 0 and n > 0 and kind ~= "out" then lines[1] = "|cff20ff20All reagents in bags.|r" end
  if table.getn(lines) > 4 then
    local more = table.getn(lines) - 3
    while table.getn(lines) > 3 do table.remove(lines) end
    table.insert(lines, "|cff888888+" .. more .. " more|r")
  end
  q.missing:SetText(table.concat(lines, "\n"))
end

--------------------------------------------------------------------------
-- Header (source, professions)
--------------------------------------------------------------------------

local function UpdateHeader()
  local data, kind = SrcData()
  local name = view.src or CH.player
  local label = name
  if kind == "me" then label = name .. " (you)" elseif kind == "alt" then label = name .. " (alt)" end
  ui.srcBtn:SetText(label)

  local profs = {}
  if data and data.profs then
    for prof in pairs(data.profs) do table.insert(profs, prof) end
  end
  table.sort(profs)
  if view.prof ~= "All" and not (data and data.profs and data.profs[view.prof]) then view.prof = "All" end

  -- Tabs are sized to their text; if they do not fit, shorter labels
  local function Label(prof, style)
    if prof == "All" then return "All" end
    local p = data.profs[prof]
    local n = (style > 1) and (SHORTPROF[prof] or prof) or prof
    if style > 2 then return n end
    return n .. " |cffaaaaaa" .. (p.rank or "?") .. "|r"
  end
  local avail = W - 18 - 156
  for style = 1, 3 do
    local total = 0
    for i = 1, MAXPROFS + 1 do
      local b = ui.profBtns[i]
      local prof = (i == 1) and "All" or profs[i - 1]
      b.prof = prof
      if prof then
        b:SetText(Label(prof, style))
        local fs = getglobal(b:GetName() .. "Text")
        b.w = math.max(44, math.floor(fs:GetStringWidth() + 22))
        total = total + b.w + 2
      end
    end
    if total <= avail then break end
  end
  local x = 156
  for i = 1, MAXPROFS + 1 do
    local b = ui.profBtns[i]
    if b.prof then
      b:SetWidth(b.w)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", main, "TOPLEFT", x, -36)
      x = x + b.w + 2
      if view.prof == b.prof then b:LockHighlight() else b:UnlockHighlight() end
      b:Show()
    else
      b:Hide()
    end
  end

  -- info line for other players
  local info = ""
  if kind == "other" and data then
    info = "Shared " .. CH.Ago(data.time or data.keytime) .. " ago"
    if CH.IsOutdated(name) then info = info .. "  |cffffd100(newer key, click Update)|r" end
    ui.update:Show()
    ui.forget:Show()
  else
    if kind == "alt" then ui.forget:Show() else ui.forget:Hide() end
    if kind == "me" and CH.openProf then
      info = "|cff20ff20" .. CH.openProf .. " open|r"
    elseif kind == "me" and CH.Count(CH.me.profs) == 0 then
      info = "|cffffd100Open each profession once so CraftHouse can read it.|r"
    end
    ui.update:Hide()
  end
  ui.info:SetText(info)
end

function CH.Refresh()
  if not main or not main:IsShown() then return end
  BuildResults()
  -- keep the selection only if it is still in the source
  if view.sel then
    local found
    for _, r in ipairs(results) do if r == view.sel then found = true; break end end
    if not found then view.sel = nil end
  end
  UpdateHeader()
  CH.UpdateList()
  UpdateDetails()
  UpdateQueue()
  local pending = CH.SendQueueLength()
  ui.sendState:SetText(pending > 0 and ("Sending... " .. pending) or "")
end

function CH.OnSendProgress(n)
  if main and main:IsShown() then
    ui.sendState:SetText(n > 0 and ("Sending... " .. n) or "|cff20ff20Sent.|r")
  end
end

function CH.IsShown() return main and main:IsShown() end

--------------------------------------------------------------------------
-- Build the window
--------------------------------------------------------------------------

local function ResetFilters()
  view.search, view.lmin, view.lmax, view.q = "", nil, nil, 0
  view.stat, view.statMin, view.cat, view.mats, view.skill = nil, 1, "All", false, false
  ui.search:SetText(""); ui.lmin:SetText(""); ui.lmax:SetText("")
  ui.statMin:SetText("")
  ui.mats:SetChecked(nil); ui.skill:SetChecked(nil)
  ui.qBtn:SetText("Any quality"); ui.statBtn:SetText("Any stat")
end

local function Build()
  main = CreateFrame("Frame", "CraftHouseFrame", UIParent)
  main:SetWidth(W); main:SetHeight(H)
  main:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  main:SetBackdrop(BACKDROP)
  main:SetFrameStrata("HIGH")
  main:SetToplevel(true)
  main:EnableMouse(true)
  main:SetMovable(true)
  if main.SetClampedToScreen then main:SetClampedToScreen(true) end
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", function() this:StartMoving() end)
  main:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local p, _, rp, x, y = this:GetPoint(1)
    CH.db.pos = { p, rp, x, y }
  end)
  main:SetScript("OnHide", function()
    if menu then menu:Hide() end
    if CH.db.settings.replace == 1 then CH.CloseProfession() end
  end)
  main:Hide()
  table.insert(UISpecialFrames, "CraftHouseFrame")
  if CH.db.pos then
    main:ClearAllPoints()
    main:SetPoint(CH.db.pos[1], UIParent, CH.db.pos[2], CH.db.pos[3], CH.db.pos[4])
  end
  if CH.db.scale then main:SetScale(CH.db.scale) end

  local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", main, "TOP", 0, -16)
  title:SetText("|cff33ffccCraft|cffffffffHouse")

  local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", main, "TOPRIGHT", -6, -6)

  -- Row 1: source and professions
  ui.srcBtn = Button(main, "", 18, -36, 130, 22, function()
    local items = {}
    for _, s in ipairs(CH.Sources()) do
      local label = s.name
      if s.kind == "me" then label = label .. " (you)"
      elseif s.kind == "alt" then label = label .. " (alt)"
      else
        label = label .. "  |cff888888" .. CH.Ago(s.data.time or s.data.keytime) .. "|r"
        if CH.IsOutdated(s.name) then label = label .. " |cffffd100*|r" end
      end
      table.insert(items, { text = label, value = s.name, checked = (s.name == (view.src or CH.player)) })
    end
    Menu(this, items, function(name)
      view.src = name
      view.prof = "All"
      view.sel = nil
      local _, kind = CH.SourceData(name)
      if kind == "other" then
        view.list = { kind = "out", name = name }
      elseif view.list and view.list.kind == "out" then
        view.list = nil
      end
      CH.watching = (kind == "other") and name or nil
      if kind == "other" and CH.others[name] and CH.others[name].route ~= "WHISPER" then
        CH.RequestUpdate(name)
      end
      CH.Refresh()
    end)
  end)
  Tip(ui.srcBtn, "Whose recipes to show: you, your alts, or players who shared theirs with you.")

  ui.profBtns = {}
  for i = 1, MAXPROFS + 1 do
    local w = (i == 1) and 50 or 100
    local x = 156 + ((i == 1) and 0 or (52 + (i - 2) * 102))
    local b = Button(main, "", x, -36, w, 22, function()
      view.prof = this.prof
      view.sel = nil
      CH.Refresh()
    end)
    b:SetScript("OnEnter", function()
      local data = SrcData()
      local p = this.prof and data and data.profs and data.profs[this.prof]
      if not p then return end
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
      GameTooltip:SetText(this.prof .. "  " .. (p.rank or "?") .. "/" .. (p.max or "?"), 1, 1, 1)
      GameTooltip:AddLine(table.getn(p.recipes or {}) .. " recipes", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.profBtns[i] = b
  end

  -- Row 2: filters
  local lbl = Text(main, "GameFontNormalSmall", 20, -68)
  lbl:SetText("Search")
  ui.search = EditBox(main, 62, -64, 140, false, function(t)
    view.search = strlower(t or "")
    CH.Refresh()
  end)

  lbl = Text(main, "GameFontNormalSmall", 210, -68)
  lbl:SetText("Level")
  ui.lmin = EditBox(main, 246, -64, 34, true, function(t)
    view.lmin = tonumber(t); CH.Refresh()
  end)
  lbl = Text(main, "GameFontNormalSmall", 283, -68)
  lbl:SetText("-")
  ui.lmax = EditBox(main, 292, -64, 34, true, function(t)
    view.lmax = tonumber(t); CH.Refresh()
  end)

  ui.qBtn = Button(main, "Any quality", 334, -63, 96, 22, function()
    local items = { { text = "Any quality", value = 0, checked = view.q == 0 } }
    for q = 1, 4 do
      table.insert(items, { text = CH.Color(q) .. CH.QUALITY[q][1] .. "|r +", value = q, checked = view.q == q })
    end
    Menu(this, items, function(q)
      view.q = q
      ui.qBtn:SetText(q == 0 and "Any quality" or (CH.QUALITY[q][1] .. "+"))
      CH.Refresh()
    end)
  end)

  ui.statBtn = Button(main, "Any stat", 436, -63, 104, 22, function()
    local items = { { text = "Any stat", value = "", checked = view.stat == nil } }
    for _, s in ipairs(CH.STATS) do
      table.insert(items, { text = s.label, value = s.key, checked = view.stat == s.key })
    end
    Menu(this, items, function(k)
      if k == "" then
        view.stat = nil
        ui.statBtn:SetText("Any stat")
        if view.sort == "stat" then view.sort = "level" end
      else
        view.stat = k
        view.sort = "stat"
        ui.statBtn:SetText(CH.STATLABEL[k])
      end
      CH.Refresh()
    end)
  end)
  Tip(ui.statBtn, "Only recipes with this stat; sorted by it, highest first.")

  lbl = Text(main, "GameFontNormalSmall", 545, -68)
  lbl:SetText("min")
  ui.statMin = EditBox(main, 568, -64, 34, true, function(t)
    view.statMin = tonumber(t) or 1; CH.Refresh()
  end)

  ui.mats = Check(main, "Have mats", 612, -62, function(on) view.mats = on; CH.Refresh() end)
  Tip(ui.mats, "Only recipes you can craft right now from your bags.")
  ui.skill = Check(main, "Skill-up", 696, -62, function(on) view.skill = on; CH.Refresh() end)
  Tip(ui.skill, "Leveling mode: hides grey recipes and sorts orange > yellow > green.")
  Button(main, "Reset", 770, -63, 52, 22, function() ResetFilters(); CH.Refresh() end)

  -- Left: categories
  local cats = Panel(main, 16, -92, 112, 400)
  ui.catBtns = {}
  for i, cat in ipairs(CH.CATEGORIES) do
    local b = CreateFrame("Button", nil, cats)
    b:SetHeight(20)
    b:SetPoint("TOPLEFT", cats, "TOPLEFT", 5, -5 - (i - 1) * 20)
    b:SetPoint("RIGHT", cats, "RIGHT", -5, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.text:SetText(cat)
    b.cat = cat
    b:SetScript("OnClick", function()
      view.cat = this.cat
      for _, o in ipairs(ui.catBtns) do
        if o.cat == view.cat then o:LockHighlight() else o:UnlockHighlight() end
      end
      CH.Refresh()
    end)
    if cat == "All" then b:LockHighlight() end
    ui.catBtns[i] = b
  end

  -- Middle: result list
  local list = Panel(main, 132, -92, 452, 22 + ROWS * ROWH + 8)
  ui.list = list
  local hName = Button(list, "Name", 30, -3, 60, 18, function() view.sort = "name"; CH.Refresh() end)
  local hLvl = Button(list, "Lvl", 210, -3, 32, 18, function() view.sort = "level"; CH.Refresh() end)
  Tip(hName, "Sort by name"); Tip(hLvl, "Sort by required level")
  local hStats = Text(list, "GameFontNormalSmall", 246, -6); hStats:SetText("Stats")
  local hHave = Text(list, "GameFontNormalSmall", 396, -6, 50, "RIGHT"); hHave:SetText("Can")
  ui.count = Text(list, "GameFontDisableSmall", 96, -6)

  ui.scroll = CreateFrame("ScrollFrame", "CraftHouseListScroll", list, "FauxScrollFrameTemplate")
  ui.scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -22)
  ui.scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -26, 6)
  ui.scroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(ROWH, CH.UpdateList)
  end)
  CreateRows(list)

  -- Bottom middle: details
  local d = Panel(main, 132, -92 - (22 + ROWS * ROWH + 8) - 4, 452, 400 - (22 + ROWS * ROWH + 8) - 4)
  ui.details = d
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetWidth(28); d.icon:SetHeight(28)
  d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 6, -6)
  d.title = Text(d, "GameFontHighlight", 40, -8, 400)
  d.title:SetHeight(16)
  d.reag = Text(d, "GameFontHighlightSmall", 40, -26, 250)
  d.num = EditBox(d, 300, -26, 34, true)
  d.num:SetText("1")
  d.craft = Button(d, "Craft", 340, -25, 104, 22, function()
    if view.sel then CH.Craft(view.sel, tonumber(d.num:GetText()) or 1) end
  end)
  d.all = Button(d, "All", 340, -48, 104, 22, function()
    if view.sel then CH.Craft(view.sel, math.max(1, CH.Available(view.sel))) end
  end)
  d.queue = Button(d, "+ Queue", 300, -71, 144, 22, function()
    if view.sel then CH.AddToList(view.sel, tonumber(d.num:GetText()) or 1) end
  end)
  d.ask = Button(d, "Ask to craft", 340, -25, 104, 22, function()
    local rec = view.sel
    if not rec then return end
    local text = "/w " .. view.src .. " Hi! Could you craft " .. (rec.n) .. " for me?"
    if ChatFrame_OpenChat then
      ChatFrame_OpenChat(text)
    else
      ChatFrameEditBox:Show(); ChatFrameEditBox:SetText(text)
    end
  end)

  -- Right: queue
  local q = Panel(main, 588, -92, 236, 250)
  ui.queue = q
  q.listBtn = Button(q, "My queue", 6, -5, 150, 20, function()
    local items = { { text = "My queue", value = "", checked = view.list == nil } }
    local names = {}
    for name in pairs(CH.lists.inc) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
      local l = CH.lists.inc[name]
      table.insert(items, { text = "From " .. name .. " (" .. table.getn(l.items) .. ")  |cff888888" .. CH.Ago(l.time) .. "|r",
        value = "in:" .. name, checked = view.list and view.list.kind == "in" and view.list.name == name })
    end
    names = {}
    for name, l in pairs(CH.lists.out) do
      if table.getn(l) > 0 then table.insert(names, name) end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      table.insert(items, { text = "For " .. name .. " (" .. table.getn(CH.lists.out[name]) .. ")",
        value = "out:" .. name, checked = view.list and view.list.kind == "out" and view.list.name == name })
    end
    Menu(this, items, function(v)
      local _, _, kind, name = strfind(v, "^(%a+):(.+)$")
      if kind then view.list = { kind = kind, name = name } else view.list = nil end
      CH.Refresh()
    end)
  end)
  Tip(q.listBtn, "Your queue, to-do lists other players sent you, and lists you are putting together for others.")
  q.rows = {}
  for i = 1, QROWS do
    local row = CreateFrame("Button", nil, q)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", q, "TOPLEFT", 6, -26 - (i - 1) * 16)
    row:SetPoint("RIGHT", q, "RIGHT", -24, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.text:SetWidth(200); row.text:SetHeight(16); row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function()
      if not this.entry then return end
      local _, data, kind, who = CurrentList()
      local rec = CH.QueueRecipe(this.entry, data)
      if rec then
        view.src = (kind == "out") and who or nil
        view.prof, view.sel = rec.prof, rec
        CH.Refresh()
      end
    end)
    local x = CreateFrame("Button", nil, q)
    x:SetWidth(14); x:SetHeight(14)
    x:SetPoint("LEFT", row, "RIGHT", 2, 0)
    x:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
    x:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    x.row = row
    x:SetScript("OnClick", function()
      local e = this.row.entry
      if not e then return end
      if IsShiftKeyDown() or e.count <= 1 then
        CH.QueueRemove(this.row.index, (CurrentList()))
      else
        e.count = e.count - 1
        CH.Refresh()
      end
    end)
    Tip(x, "-1 (Shift-click: remove)")
    row.minus = x
    local orig = row.Show
    row.Show = function(self) orig(self); x:Show() end
    local origH = row.Hide
    row.Hide = function(self) origH(self); x:Hide() end
    q.rows[i] = row
  end
  q.more = Text(q, "GameFontDisableSmall", 8, -26 - QROWS * 16 - 2, 220)
  q.b1 = Button(q, "Craft next", 8, -222, 104, 22, function()
    local list, _, kind, who = CurrentList()
    if kind == "me" then
      CH.QueueNext()
    elseif kind == "out" then
      CH.SendList(who, list)
    else
      local moved = CH.TakeOver(who)
      CH.Print("Moved " .. moved .. " recipes to your queue.")
      if not CH.lists.inc[who] then view.list = nil end
      CH.Refresh()
    end
  end)
  q.b2 = Button(q, "Send", 114, -222, 56, 22, function()
    CH.SendList(ui.shareName:GetText(), CH.queue)
  end)
  Tip(q.b2, "Send your queue as a to-do list to the player named under 'Share with player'.")
  Button(q, "Clear", 172, -222, 56, 22, function()
    local _, _, kind, who = CurrentList()
    if kind == "me" then
      for i = table.getn(CH.queue), 1, -1 do table.remove(CH.queue, i) end
    elseif kind == "out" then
      CH.lists.out[who] = nil
    else
      CH.lists.inc[who] = nil
      view.list = nil
    end
    CH.Refresh()
  end)

  -- Right: missing reagents
  local m = Panel(main, 588, -346, 236, 76)
  q.mtitle = Text(m, "GameFontNormalSmall", 8, -6)
  q.missing = Text(m, "GameFontHighlightSmall", 8, -20, 220)

  -- Right: sharing
  local s = Panel(main, 588, -426, 236, 66)
  local st = Text(s, "GameFontNormalSmall", 8, -6); st:SetText("Share with player")
  ui.shareName = EditBox(s, 8, -20, 100)
  ui.shareName:SetScript("OnEnterPressed", function()
    this:ClearFocus(); CH.SendKeyTo(this:GetText())
  end)
  local sendBtn = Button(s, "Send", 112, -19, 54, 22, function() CH.SendKeyTo(ui.shareName:GetText()) end)
  Tip(sendBtn, "Send your recipe key to this player. If they use CraftHouse, they load your recipes and can browse them.")
  local gBtn = Button(s, "Guild", 170, -19, 58, 22, function() CH.AnnounceGuild(true) end)
  Tip(gBtn, "Share your key with your guild. Guild members load your recipes when they look at you.")
  ui.sendState = Text(s, "GameFontDisableSmall", 8, -46, 220)

  -- Info line under the header and "Update" for other players
  ui.info = Text(main, "GameFontDisableSmall", 20, -501, 560)
  ui.update = Button(main, "Update", 740, -496, 82, 20, function()
    if view.src and CH.others[view.src] then
      if CH.RequestUpdate(view.src, IsShiftKeyDown()) then
        CH.Print("Asked " .. view.src .. " for their latest recipes.")
      else
        CH.Print(view.src .. "'s recipes are up to date. Shift-click to reload anyway.")
      end
    end
  end)
  Tip(ui.update, "Ask this player for their latest recipes (they must be online). Shift-click reloads everything.")
  ui.update:Hide()

  StaticPopupDialogs["CRAFTHOUSE_FORGET"] = {
    text = "Delete the saved recipes of %s?",
    button1 = YES, button2 = NO,
    OnAccept = function() CH.Forget(CH.forgetName) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
  }
  ui.forget = Button(main, "Delete", 654, -496, 82, 20, function()
    if not view.src or view.src == CH.player then return end
    CH.forgetName = view.src
    StaticPopup_Show("CRAFTHOUSE_FORGET", view.src)
  end)
  Tip(ui.forget, "Delete this player's saved recipes from CraftHouse. Alts come back when you log in and open their professions.")
  ui.forget:Hide()

  -- Mouse wheel + Ctrl scales the window
  main:EnableMouseWheel(true)
  main:SetScript("OnMouseWheel", function()
    if not IsControlKeyDown() then return end
    local s2 = this:GetScale() + arg1 * 0.05
    if s2 < 0.6 then s2 = 0.6 elseif s2 > 1.4 then s2 = 1.4 end
    this:SetScale(s2)
    CH.db.scale = s2
  end)
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

function CH.Show(src, prof)
  if not main then Build() end
  if src then view.src = (src == CH.player) and nil or src end
  if prof then view.prof = prof end
  view.sel = nil
  main:Show()
  CH.Refresh()
end

function CH.Toggle()
  if main and main:IsShown() then main:Hide() else CH.Show() end
end

function CH.OnScanned(prof)
  if CH.OnRecipesChanged then CH.OnRecipesChanged() end
end

function CH.OnForget(name)
  if view.src == name then
    view.src, view.sel, view.prof = nil, nil, "All"
    if view.list and view.list.kind == "out" then view.list = nil end
  end
  CH.Refresh()
end

function CH.OnListReceived(from)
  if CH.IsShown() then CH.Refresh() end
end

function CH.OnBagsChanged()
  if CH.IsShown() then CH.Refresh() end
end
