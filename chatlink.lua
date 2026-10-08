--[[ CraftHouse -- chatlink
     Profession links in chat, like in later WoW versions.

     Shift-click one of your profession tabs in CraftHouse to put a code
     into the chat line, e.g.  LFW [CH:Enchanting:300:ce84:gA8x...]
     The code carries rank, recipe-copy version and the recipe mask.
     Players with CraftHouse see it as a clickable link
     "[Henry's Enchanting]"; a click shows exactly those recipes, built from
     the local recipe copy (nothing is whispered). Players without the
     addon just see the code.
]]--

local CH = CraftHouse

local PATTERN = "%[CH:([^:%]]+):(%d+):(%w+):([%w%-_]*)%]"

-- Code for one of your professions, or nil
function CH.LinkCode(prof)
  local p = CH.me.profs[prof]
  if not p or not CH.DBHas(prof) then return end
  local mask = CH.MaskFor(prof, p.recipes)
  return "[CH:" .. prof .. ":" .. (p.rank or 0) .. ":" .. strsub(CH.dbVersion, 1, 4) .. ":" .. mask .. "]"
end

function CH.InsertLink(prof)
  local code = CH.LinkCode(prof)
  if not code then
    CH.Print("Open " .. prof .. " once so CraftHouse can read it.")
    return
  end
  if ChatFrameEditBox:IsVisible() then
    ChatFrameEditBox:Insert(code)
  elseif ChatFrame_OpenChat then
    ChatFrame_OpenChat(code)
  else
    ChatFrameEditBox:Show()
    ChatFrameEditBox:SetText(code)
  end
end

-- Turns codes in a chat line into clickable links (sender = who wrote it)
function CH.LinkifyChat(text, sender)
  if not text or not sender or not strfind(text, "[CH:", 1, true) then return text end
  return (gsub(text, PATTERN, function(prof, rank, ver, mask)
    return "|cff33ffcc|Hcrafthouse:" .. sender .. ":" .. prof .. ":" .. rank .. ":" .. ver .. ":" .. mask
      .. "|h[" .. sender .. "'s " .. prof .. " " .. rank .. "]|h|r"
  end))
end

-- Shows the recipes of a link
function CH.OpenLink(sender, prof, rank, ver, mask)
  rank = tonumber(rank)
  if sender == CH.player or (CH.db.chars[CH.realm][sender] and CH.db.chars[CH.realm][sender].profs[prof]) then
    CH.Show(sender, prof)
    return
  end
  if ver ~= strsub(CH.dbVersion, 1, 4) or not CH.DBHas(prof) then
    CH.Print(sender .. " uses a different CraftHouse version. Both of you need the latest update to open this link.")
    return
  end
  if not CH.others[sender] then CH.others[sender] = { profs = {} } end
  local o = CH.others[sender]
  if not o.profs then o.profs = {} end
  local p = o.profs[prof]
  if not p or p.mask ~= mask then
    o.profs[prof] = {
      rank = rank, hash = "link:" .. mask, mask = mask, time = time(),
      recipes = CH.RecipesFromMask(prof, mask, rank),
    }
    if not o.time then o.time = time() end
  end
  CH.Show(sender, prof)
end

-- Clicks on our links
local origSetItemRef = SetItemRef
function SetItemRef(link, text, button)
  if link and strsub(link, 1, 11) == "crafthouse:" then
    local f = CH.Split(link, ":")
    CH.OpenLink(f[2], f[3], f[4], f[5], f[6] or "")
    return
  end
  return origSetItemRef(link, text, button)
end
