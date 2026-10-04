-- 1.12 API stubs for offline tests (Lua 5.4 via lupa). Not loaded in-game.
table.getn = function(t) return #t end
math.mod = math.fmod
strfind, strsub, strlen, strlower, strupper, gsub, format, strbyte =
  string.find, string.sub, string.len, string.lower, string.upper, string.gsub, string.format, string.byte
string.gfind = string.gmatch
local _now = 1000
function GetTime() return _now end
function SetNow(t) _now = t end
function time() return 1700000000 + math.floor(_now) end
function getglobal(n) return _G[n] end
OUT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(OUT, m) end }

local Obj = {}
ALL = {}
local function new(name)
  local o = setmetatable({ scripts = {}, shown = false, text = "", name = name, points = {} }, Obj)
  table.insert(ALL, o)
  if name then _G[name] = o end
  return o
end
local methods = {
  SetScript = function(s, k, f) s.scripts[k] = f end,
  GetScript = function(s, k) return s.scripts[k] end,
  RegisterEvent = function(s, e) rawset(s, "events", rawget(s, "events") or {}); s.events[e] = true end,
  Show = function(s) local was = s.shown; s.shown = true; if not was and s.scripts.OnShow then this = s; s.scripts.OnShow() end end,
  Hide = function(s) local was = s.shown; s.shown = false; if was and s.scripts.OnHide then this = s; s.scripts.OnHide() end end,
  IsShown = function(s) return s.shown end,
  IsVisible = function(s) return s.shown end,
  GetName = function(s) return s.name end,
  SetText = function(s, t) s.text = t; if s.name and s.kind == "Button" and _G[s.name .. "Text"] then _G[s.name .. "Text"].text = t end; if s.scripts.OnTextChanged then local o = this; this = s; s.scripts.OnTextChanged(); this = o end end,
  GetText = function(s) return s.text end,
  GetChecked = function(s) return s.checked end,
  SetChecked = function(s, v) s.checked = v end,
  GetPoint = function(s) local p = s.points[1] or {"CENTER", nil, "CENTER", 0, 0}; return p[1], p[2], p[3], p[4], p[5] end,
  SetPoint = function(s, a, b, c, d, e) s.points[1] = {a, b, c, d, e} end,
  ClearAllPoints = function(s) s.points = {} end,
  GetScale = function() return 1 end,
  GetStringWidth = function(s) return 6 * #(s.text or "") end,
  CreateFontString = function() return new() end,
  CreateTexture = function() return new() end,
  NumLines = function(s) return s.lines and #s.lines or 0 end,
}
Obj.__index = function(t, k) if type(k) == "string" and k:match("^%u") then return methods[k] or function() end end end

function CreateFrame(kind, name, parent, tmpl)
  local f = new(name); f.shown = true
  f.kind = kind
  if tmpl == "UICheckButtonTemplate" or tmpl == "UIPanelButtonTemplate" then new(name .. "Text") end
  if tmpl == "GameTooltipTemplate" then
    for i = 1, 30 do new(name .. "TextLeft" .. i); new(name .. "TextRight" .. i) end
  end
  return f
end
UIParent = new("UIParent"); WorldFrame = new("WorldFrame"); GameTooltip = new("GameTooltip")
ChatFrameEditBox = new("ChatFrameEditBox")
UISpecialFrames = {}
SlashCmdList = {}
ChatFontNormal = {}
function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_OnVerticalScroll() end
function IsShiftKeyDown() return false end
StaticPopupDialogs = {}
function StaticPopup_Show(n, a) POPUP = {n, a} end
YES, NO = "Yes", "No"
function IsControlKeyDown() return false end
function GetRealmName() return "Octo" end
PLAYER = "Henry"
function UnitName() return PLAYER end
function IsInGuild() return GUILD ~= nil end
function GetNumGuildMembers() return GUILD and #GUILD or 0 end
function GetGuildRosterInfo(i) return GUILD[i], nil, nil, nil, nil, nil, nil, nil, 1 end
function GetNumRaidMembers() return 0 end
function GetNumPartyMembers() return 0 end
SENT = {}
function SendAddonMessage(p, m, ch) table.insert(SENT, {"ADDON", p, m, ch}) end
function SendChatMessage(m, kind, lang, target) table.insert(SENT, {kind, m, target}) end
function ChatFrame_OnEvent(event) CHATSHOWN = (CHATSHOWN or 0) + 1 end
function GetItemInfo(id) return nil end
function CastSpellByName(n) CAST = n end
function CloseTradeSkill() end
function CloseCraft() end

-- Bags: { {link, count}, ... } in bag 0
BAG = {}
function GetContainerNumSlots(b) return b == 0 and #BAG or 0 end
function GetContainerItemLink(b, s) return BAG[s] and BAG[s][1] end
function GetContainerItemInfo(b, s) return "tex", BAG[s] and BAG[s][2] end

-- Tradeskill: TS = { line = {name, rank, max}, list = { {name, kind, link, reagents={{name,count,link}}, tip={ {left,right},... } } } }
function GetTradeSkillLine() return TS.line[1], TS.line[2], TS.line[3] end
function GetNumTradeSkills() return #TS.list end
function GetTradeSkillInfo(i) local r = TS.list[i]; return r.name, r.kind, 0 end
function GetTradeSkillItemLink(i) return TS.list[i].link end
function GetTradeSkillIcon(i) return "icon" .. i end
function GetTradeSkillNumMade(i) return 1, 1 end
function GetTradeSkillNumReagents(i) return #(TS.list[i].reagents or {}) end
function GetTradeSkillReagentInfo(i, j) local r = TS.list[i].reagents[j]; return r[1], "tex", r[2], 0 end
function GetTradeSkillReagentItemLink(i, j) return TS.list[i].reagents[j][3] end
function ExpandTradeSkillSubClass() end
function DoTradeSkill(i, n) DONE = {i, n} end
methods.SetTradeSkillItem = function(s, i)
  local tip = TS.list[i].tip or {}
  s.lines = tip
  for k = 1, 30 do
    local l, r = _G[s.name .. "TextLeft" .. k], _G[s.name .. "TextRight" .. k]
    l.text = tip[k] and tip[k][1] or nil
    r.text = tip[k] and tip[k][2] or nil
    r.shown = tip[k] and tip[k][2] ~= nil
  end
end

function Fire(event, a1, a2, a3, a4)
  event_ = event
  _G.event = event; arg1, arg2, arg3, arg4 = a1, a2, a3, a4
  local f = CraftHouseEvents
  if rawget(f, "events") and f.events[event] then this = f; f.scripts.OnEvent() end
end
function Tick(dt, steps)
  for _ = 1, (steps or 1) do
    SetNow(GetTime() + dt)
    for _, o in ipairs(ALL) do
      if o.scripts.OnUpdate and o.shown then this = o; o.scripts.OnUpdate() end
    end
  end
end
