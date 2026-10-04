--[[ CraftHouse -- comm
     Sharing recipes with other CraftHouse users.

     The "key" is a short summary of your professions: name, rank and a
     hash of the recipe list. Receivers keep a local cache per player and
     only ask for the full recipe list of a profession when its hash in
     the key differs from what they have cached.

     Routes: guild / raid / party members get addon messages
     (SendAddonMessage), everyone else gets whispers that the addon hides
     on both sides. Only the key whisper is readable for players without
     the addon; recipe data is only sent after a request, i.e. to players
     who have the addon.

     Messages, fields separated by "^":
       K^<ver>^<target>^<mode>^<prof>:<rank>:<max>:<hash>:<count>^...
            key; target = player it was sent to, "" = announcement;
            mode a = all professions, p = only the listed ones
       Q^<target>^<prof>,<prof>         request recipe lists from target
       P^<prof>^<rank>^<max>^<hash>^<count>^<craft>   start of a list
       E^<prof>^<entry>~<entry>~...     recipes
       O^<target>^<id>^<part>^<parts>^<prof;name;count>~...   to-do list
     entry: id;quality;level;category;stats;reagents;name;made
       stats    "int=5/sta=3"
       reagents "2321*2/2589*4" (item id, or the name when the id is unknown)
]]--

local CH = CraftHouse

local MAX_MSG    = 225
local SEND_DELAY = 0.35
local WHISPER_TAG = "[CH]"
local KEY_TEXT = "[CraftHouse] I shared my recipes with you (needs the CraftHouse addon). #"
local LIST_TEXT = "[CraftHouse] I sent you a to-do list (needs the CraftHouse addon). #"

--------------------------------------------------------------------------
-- Throttled sending
--------------------------------------------------------------------------

local queue = {}
local sender = CreateFrame("Frame")
sender.next = 0
sender:SetScript("OnUpdate", function()
  if table.getn(queue) == 0 or GetTime() < sender.next then return end
  local m = table.remove(queue, 1)
  if m.route == "WHISPER" then
    SendChatMessage((m.raw or (WHISPER_TAG .. m.body)), "WHISPER", nil, m.target)
  else
    SendAddonMessage(CH.prefix, m.body, m.route)
  end
  sender.next = GetTime() + SEND_DELAY
  if CH.OnSendProgress then CH.OnSendProgress(table.getn(queue)) end
end)

local function Send(route, target, body, raw)
  table.insert(queue, { route = route, target = target, body = body, raw = raw })
end

function CH.SendQueueLength() return table.getn(queue) end

--------------------------------------------------------------------------
-- Routes
--------------------------------------------------------------------------

local function InGuild(name)
  if not IsInGuild() then return end
  for i = 1, GetNumGuildMembers() do
    local n, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if n == name then return online end
  end
end

local function InGroup(name)
  for i = 1, GetNumRaidMembers() do
    if UnitName("raid" .. i) == name then return "RAID" end
  end
  for i = 1, GetNumPartyMembers() do
    if UnitName("party" .. i) == name then return "PARTY" end
  end
end

local function Route(name)
  if InGuild(name) then return "GUILD" end
  return InGroup(name) or "WHISPER"
end

--------------------------------------------------------------------------
-- Building messages
--------------------------------------------------------------------------

-- profs = { [prof] = true } to share only some, nil = all
local function KeyBody(target, profs)
  local parts = { "K", CH.version, target or "", profs and "p" or "a" }
  for prof, p in pairs(CH.me.profs) do
    if not profs or profs[prof] then
      table.insert(parts, prof .. ":" .. (p.rank or 0) .. ":" .. (p.max or 0) .. ":"
        .. (p.hash or "") .. ":" .. (p.count or 0))
    end
  end
  return table.concat(parts, "^")
end

-- Profession preselected for sharing: the open one, else the selected tab
function CH.DefaultShareProfs()
  local prof = CH.openProf
  if not prof and CH.view and CH.view.prof ~= "All" and CH.me.profs[CH.view.prof] then
    prof = CH.view.prof
  end
  if prof and CH.me.profs[prof] then return { [prof] = true } end
end

local function EncodeEntry(r)
  local stats = {}
  for k, v in pairs(r.t or {}) do table.insert(stats, k .. "=" .. v) end
  local reag = {}
  for _, x in ipairs(r.r or {}) do
    local id = (x[1] and x[1] > 0) and x[1] or (x[3] or "?")
    table.insert(reag, id .. "*" .. (x[2] or 1))
  end
  local cat = r.c or "Other"
  if r.sl then cat = cat .. ":" .. r.sl end
  return (r.id or 0) .. ";" .. (r.q or 1) .. ";" .. (r.l or 0) .. ";" .. cat .. ";"
    .. table.concat(stats, "/") .. ";" .. table.concat(reag, "/") .. ";"
    .. gsub(r.n, "[;~%^]", "") .. ";" .. (r.mk or 1)
end

local function SendProf(route, target, prof)
  local p = CH.me.profs[prof]
  if not p then return end
  Send(route, target, "P^" .. prof .. "^" .. (p.rank or 0) .. "^" .. (p.max or 0) .. "^"
    .. (p.hash or "") .. "^" .. (p.count or 0) .. "^" .. (p.craft or 0))
  local head = "E^" .. prof .. "^"
  local blob = ""
  for _, r in ipairs(p.recipes) do
    local e = EncodeEntry(r)
    if blob ~= "" and strlen(head) + strlen(blob) + 1 + strlen(e) > MAX_MSG then
      Send(route, target, head .. blob)
      blob = ""
    end
    blob = (blob == "") and e or (blob .. "~" .. e)
  end
  if blob ~= "" then Send(route, target, head .. blob) end
end

--------------------------------------------------------------------------
-- Public functions
--------------------------------------------------------------------------

-- profs = { [prof] = true } to share only these, nil = all
function CH.SendKeyTo(name, profs)
  name = gsub(name or "", "^%s*(.-)%s*$", "%1")
  if name == "" then
    CH.Print("Type a player name first.")
    return
  end
  name = strupper(strsub(name, 1, 1)) .. strlower(strsub(name, 2))
  if CH.Count(CH.me.profs) == 0 then
    CH.Print("Open each of your professions once so CraftHouse can read them.")
    return
  end
  if profs and CH.Count(profs) == 0 then
    CH.Print("Select at least one profession.")
    return
  end
  if not CH.shared[name] then CH.shared[name] = {} end
  local names = {}
  for prof in pairs(CH.me.profs) do
    if not profs or profs[prof] then
      CH.shared[name][prof] = true
      table.insert(names, prof)
    end
  end
  table.sort(names)
  local route = Route(name)
  if route == "WHISPER" then
    Send("WHISPER", name, nil, KEY_TEXT .. KeyBody(name, profs))
  else
    Send(route, nil, KeyBody(name, profs))
  end
  CH.Print("Shared " .. table.concat(names, ", ") .. " with " .. name .. ".")
end

function CH.AnnounceGuild(verbose)
  if not IsInGuild() then
    if verbose then CH.Print("You are not in a guild.") end
    return
  end
  if CH.Count(CH.me.profs) == 0 then return end
  Send("GUILD", nil, KeyBody(""))
  if verbose then CH.Print("Shared your recipe key with your guild.") end
end

-- Asks a player for the professions whose cache is out of date.
-- Returns true if something was requested.
function CH.RequestUpdate(name, force)
  local o = CH.others[name]
  if not o or not o.key then return end
  local want = {}
  for prof, k in pairs(o.key) do
    local p = o.profs and o.profs[prof]
    if force or not p or p.hash ~= k.hash then table.insert(want, prof) end
  end
  if table.getn(want) == 0 then return end
  local route = o.route or Route(name)
  if route == "WHISPER" then
    Send("WHISPER", name, "Q^" .. name .. "^" .. table.concat(want, ","))
  else
    Send(route, nil, "Q^" .. name .. "^" .. table.concat(want, ","))
  end
  o.requested = time()
  return true
end

-- Profession-level summary of a player's key vs. cache
function CH.IsOutdated(name)
  local o = CH.others[name]
  if not o or not o.key then return end
  for prof, k in pairs(o.key) do
    local p = o.profs and o.profs[prof]
    if not p or p.hash ~= k.hash then return true end
  end
end

-- Sends a to-do list (entries {prof, name, count}) to a player
function CH.SendList(name, list)
  name = gsub(name or "", "^%s*(.-)%s*$", "%1")
  if name == "" then
    CH.Print("Type a player name first.")
    return
  end
  name = strupper(strsub(name, 1, 1)) .. strlower(strsub(name, 2))
  if not list or table.getn(list) == 0 then
    CH.Print("The list is empty.")
    return
  end
  -- Own alt: same account, so the list is simply stored for them
  if CH.db.chars[CH.realm][name] and name ~= CH.player then
    local items = {}
    for _, e in ipairs(list) do
      table.insert(items, { prof = e.prof, name = e.name, count = e.count })
    end
    local lists = CH.db.lists[CH.realm]
    if not lists[name] then lists[name] = { out = {}, inc = {} } end
    if not lists[name].inc then lists[name].inc = {} end
    lists[name].inc[CH.player] = { time = time(), items = items }
    CH.Print("To-do list (" .. table.getn(items) .. " recipes) is waiting for " .. name
      .. ". Log in with " .. name .. " to craft it.")
    return
  end
  local entries = {}
  for _, e in ipairs(list) do
    table.insert(entries, e.prof .. ";" .. gsub(e.name, "[;~%^]", "") .. ";" .. e.count)
  end
  -- pack the entries into as few messages as possible
  local id = CH.Hash(name .. time() .. GetTime())
  local chunks, blob = {}, ""
  for _, e in ipairs(entries) do
    if blob ~= "" and strlen(blob) + 1 + strlen(e) > MAX_MSG - 90 then
      table.insert(chunks, blob)
      blob = ""
    end
    blob = (blob == "") and e or (blob .. "~" .. e)
  end
  table.insert(chunks, blob)
  local route = Route(name)
  local total = table.getn(chunks)
  for i, c in ipairs(chunks) do
    local body = "O^" .. name .. "^" .. id .. "^" .. i .. "^" .. total .. "^" .. c
    if route == "WHISPER" then
      Send("WHISPER", name, body, (i == 1) and (LIST_TEXT .. body) or nil)
    else
      Send(route, nil, body)
    end
  end
  CH.Print("Sent a to-do list (" .. table.getn(entries) .. " recipes) to " .. name .. ".")
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------

local incoming = {}  -- [sender] = { id, parts = {}, got, total }

local staging = {}   -- [sender .. "\1" .. prof] = { head, recipes }
local answered = {}  -- [route .. target .. prof] = time, against request storms

local function DecodeEntry(e)
  local f = CH.Split(e, ";")
  local rec = {
    id = tonumber(f[1]) or 0, q = tonumber(f[2]) or 1, l = tonumber(f[3]) or 0,
    c = f[4] or "Other", t = {}, r = {}, n = f[7] or "?", mk = tonumber(f[8]),
  }
  if rec.mk == 1 then rec.mk = nil end
  local _, _, cat, sl = strfind(rec.c, "^(.-):(.+)$")
  if cat then rec.c, rec.sl = cat, sl end
  for _, s in ipairs((CH.Split(f[5] or "", "/"))) do
    local _, _, k, v = strfind(s, "^(%a+)=([%d%.]+)$")
    if k then rec.t[k] = tonumber(v) end
  end
  for _, s in ipairs((CH.Split(f[6] or "", "/"))) do
    local _, _, id, n = strfind(s, "^(.+)%*(%d+)$")
    if id then
      if tonumber(id) then
        table.insert(rec.r, { tonumber(id), tonumber(n) })
      else
        table.insert(rec.r, { 0, tonumber(n), id })
      end
    end
  end
  return rec
end

local function OtherEntry(name)
  if not CH.others[name] then CH.others[name] = { profs = {} } end
  local o = CH.others[name]
  if not o.profs then o.profs = {} end
  return o
end

local function Handle(body, from, route)
  if not body or from == CH.player then return end
  local f = CH.Split(body, "^")
  local kind = f[1]

  if kind == "K" then
    -- own alts are read locally, no need to cache them twice
    if CH.db.chars[CH.realm][from] then return end
    local o = OtherEntry(from)
    -- mode field (1.4+); older keys list the professions from field 4 on
    local first, partial = 4, false
    if f[4] == "a" or f[4] == "p" then first, partial = 5, (f[4] == "p") end
    if not partial or not o.key then o.key = {} end
    o.keytime, o.route = time(), route
    o.ver = f[2]
    for i = first, table.getn(f) do
      local k = CH.Split(f[i], ":")
      if k[1] and k[1] ~= "" and k[2] then
        o.key[k[1]] = { rank = tonumber(k[2]), max = tonumber(k[3]), hash = k[4], count = tonumber(k[5]) }
        local p = o.profs[k[1]]
        if p and p.hash == k[4] then p.rank, p.max = tonumber(k[2]), tonumber(k[3]) end
      end
    end
    -- forget professions they dropped (only a full key says that)
    if not partial then
      for prof in pairs(o.profs) do
        if not o.key[prof] then o.profs[prof] = nil end
      end
    end
    if f[3] == CH.player then
      if CH.RequestUpdate(from) then
        CH.Print(from .. " shared their recipes with you. Loading...")
      else
        CH.Print(from .. " shared their recipes with you (already up to date). /ch to browse.")
      end
    end
    if CH.IsShown() then CH.Refresh() end

  elseif kind == "Q" then
    if f[2] ~= CH.player then return end
    local target = (route == "WHISPER") and from or nil
    for _, prof in ipairs((CH.Split(f[3] or "", ","))) do
      local p = CH.me.profs[prof]
      local key = route .. (target or "") .. prof .. (p and p.hash or "")
      -- only professions we shared with them (or with the guild)
      local ok = (CH.shared[from] and CH.shared[from][prof])
        or (route == "GUILD" and CH.db.settings.guild == 1)
      if ok and (not answered[key] or GetTime() - answered[key] > 20) then
        answered[key] = GetTime()
        SendProf(route, target, prof)
      end
    end

  elseif kind == "O" then
    if f[2] ~= CH.player then return end
    local id, part, total = f[3], tonumber(f[4]) or 1, tonumber(f[5]) or 1
    local inc = incoming[from]
    if not inc or inc.id ~= id then
      inc = { id = id, parts = {}, got = 0, total = total }
      incoming[from] = inc
    end
    if not inc.parts[part] then
      inc.parts[part] = f[6] or ""
      inc.got = inc.got + 1
    end
    if inc.got < inc.total then return end
    incoming[from] = nil
    local items = {}
    for p = 1, inc.total do
      for _, e in ipairs((CH.Split(inc.parts[p] or "", "~"))) do
        local x = CH.Split(e, ";")
        if x[1] and x[2] then
          table.insert(items, { prof = x[1], name = x[2], count = tonumber(x[3]) or 1 })
        end
      end
    end
    CH.lists.inc[from] = { time = time(), items = items }
    CH.Print(from .. " sent you a to-do list (" .. table.getn(items) .. " recipes). /ch to see it.")
    if CH.OnListReceived then CH.OnListReceived(from) end

  elseif kind == "P" then
    if CH.db.chars[CH.realm][from] then return end
    staging[from .. "\1" .. (f[2] or "")] = {
      rank = tonumber(f[3]), max = tonumber(f[4]), hash = f[5],
      count = tonumber(f[6]) or 0, craft = (f[7] == "1") and 1 or nil, recipes = {},
    }

  elseif kind == "E" then
    local prof = f[2] or ""
    local s = staging[from .. "\1" .. prof]
    if not s then return end
    -- the entry text itself may not contain "^", so f[3] is the whole blob
    for _, e in ipairs((CH.Split(f[3] or "", "~"))) do
      if e ~= "" then table.insert(s.recipes, DecodeEntry(e)) end
    end
    if table.getn(s.recipes) >= s.count then
      staging[from .. "\1" .. prof] = nil
      local o = OtherEntry(from)
      s.time = time()
      o.profs[prof] = s
      o.time = time()
      if not o.key then o.key = {} end
      o.key[prof] = { rank = s.rank, max = s.max, hash = s.hash, count = s.count }
      if CH.IsShown() then CH.Refresh() end
      if route == "WHISPER" or (CH.watching == from) then
        CH.Print("Loaded " .. from .. "'s " .. prof .. " (" .. s.count .. " recipes).")
      end
    end
  end
end

CH.On("CHAT_MSG_ADDON", function(prefix, msg, channel, from)
  if prefix ~= CH.prefix then return end
  Handle(msg, from, channel)
end)

local function WhisperBody(msg)
  if not msg then return end
  if strsub(msg, 1, strlen(WHISPER_TAG)) == WHISPER_TAG then
    return strsub(msg, strlen(WHISPER_TAG) + 1)
  end
  if strsub(msg, 1, strlen(KEY_TEXT)) == KEY_TEXT then
    return strsub(msg, strlen(KEY_TEXT) + 1)
  end
  if strsub(msg, 1, strlen(LIST_TEXT)) == LIST_TEXT then
    return strsub(msg, strlen(LIST_TEXT) + 1)
  end
end

CH.On("CHAT_MSG_WHISPER", function(msg, from)
  local body = WhisperBody(msg)
  if body then Handle(body, from, "WHISPER") end
end)

-- Hide our whispers in every chat frame, incoming and outgoing
local origChatFrame_OnEvent = ChatFrame_OnEvent
function ChatFrame_OnEvent(event)
  if (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM") and WhisperBody(arg1) then
    return
  end
  return origChatFrame_OnEvent(event)
end

--------------------------------------------------------------------------
-- Guild announcement on login and after recipe changes
--------------------------------------------------------------------------

local lastHashes
local function HashSummary()
  local t = {}
  for prof, p in pairs(CH.me.profs) do table.insert(t, prof .. (p.hash or "")) end
  table.sort(t)
  return table.concat(t, ",")
end

CH.On("PLAYER_ENTERING_WORLD", function()
  if CH.loggedIn then return end
  CH.loggedIn = true
  CH.After(15, function()
    lastHashes = HashSummary()
    if CH.db.settings.guild == 1 then CH.AnnounceGuild() end
  end)
end)

function CH.OnRecipesChanged()
  if not lastHashes or CH.db.settings.guild ~= 1 then return end
  local h = HashSummary()
  if h ~= lastHashes then
    lastHashes = h
    CH.After(5, function() CH.AnnounceGuild() end)
  end
end
