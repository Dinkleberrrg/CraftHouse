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
       P^<prof>^<rank>^<max>^<hash>^<count>^<craft>^<chunks>   start of a list
       E^<prof>^<n>^<entry>~<entry>~... recipes, chunk n of <chunks>
       R^<target>^<prof>^<hash>^<n>,<n> resend missing chunks
       O^<target>^<id>^<part>^<parts>^<prof;name;count>~...   to-do list
     entry: id;quality;level;category;stats;reagents;name;made
       stats    "int=5/sta=3"
       reagents "2321*2/2589*4" (item id, or the name when the id is unknown)
]]--

local CH = CraftHouse

local MAX_MSG    = 235
local SEND_DELAY = 0.35   -- addon messages
-- Whispers count as chat: the server mutes you for some seconds when too
-- many go out ("You must wait N seconds before speaking again"). We start
-- slow, back off when that message shows up and resend what got dropped.
local WHISPER_DELAY = 1.2
local WHISPER_TAG = "[CH]"
local KEY_TEXT = "[CraftHouse] Shared my recipes (CraftHouse addon) #"
local LIST_TEXT = "[CraftHouse] I sent you a to-do list (needs the CraftHouse addon). #"

--------------------------------------------------------------------------
-- Throttled sending
--------------------------------------------------------------------------

local queue = {}
local sender = CreateFrame("Frame")
sender.next = 0
sender.whisperDelay = WHISPER_DELAY
sender:SetScript("OnUpdate", function()
  if table.getn(queue) == 0 or GetTime() < sender.next then return end
  local m = table.remove(queue, 1)
  if m.route == "WHISPER" then
    SendChatMessage((m.raw or (WHISPER_TAG .. m.body)), "WHISPER", nil, m.target)
    sender.lastWhisper, sender.lastWhisperTime = m, GetTime()
    sender.next = GetTime() + sender.whisperDelay
  else
    SendAddonMessage(CH.prefix, m.body, m.route)
    sender.next = GetTime() + SEND_DELAY
  end
  if CH.OnSendProgress then CH.OnSendProgress(table.getn(queue)) end
end)

-- "You must wait 9 Seconds before speaking again." -> pause, resend
local function ChatLimited(text)
  if not text then return end
  local _, _, sec = strfind(strlower(text), "must wait (%d+) seconds? before speaking")
  return tonumber(sec)
end
CH.ChatLimited = ChatLimited

function CH.SetWhisperDelay(d) sender.whisperDelay = d end

function CH.SlowerWhispers()
  sender.whisperDelay = math.min(4, sender.whisperDelay + 0.5)
end

local function OnChatLimit(sec)
  -- the same message can arrive through several events
  if sender.limitAt and GetTime() - sender.limitAt < 1 then return end
  sender.limitAt = GetTime()
  local m = sender.lastWhisper
  if m and GetTime() - (sender.lastWhisperTime or 0) < 3 and queue[1] ~= m then
    table.insert(queue, 1, m)
  end
  sender.next = GetTime() + sec + 0.5
  sender.whisperDelay = math.min(4, sender.whisperDelay + 0.8)
  if not sender.warned then
    sender.warned = true
    CH.Print("Server chat limit reached, sharing continues more slowly.")
  end
end

local function CheckLimit(text)
  local sec = ChatLimited(text)
  if sec and sender.lastWhisper and GetTime() - (sender.lastWhisperTime or 0) < 5 then
    OnChatLimit(sec)
    return true
  end
end
CH.On("CHAT_MSG_SYSTEM", function(text) CheckLimit(text) end)
CH.On("UI_ERROR_MESSAGE", function(text) CheckLimit(text) end)

-- Hide that red message while CraftHouse itself is whispering
if UIErrorsFrame and UIErrorsFrame.AddMessage then
  local origAdd = UIErrorsFrame.AddMessage
  UIErrorsFrame.AddMessage = function(self, text, a, b, c, d, e)
    if CheckLimit(text) then return end
    return origAdd(self, text, a, b, c, d, e)
  end
end

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
-- Returns one or more key messages, each at most maxLen long. If the key
-- needs several messages, all are partial ("p") so none wipes the others.
local function KeyBodies(target, profs, maxLen)
  local entries = {}
  for prof, p in pairs(CH.me.profs) do
    if not profs or profs[prof] then
      table.insert(entries, prof .. ":" .. (p.rank or 0) .. ":" .. (p.max or 0) .. ":"
        .. (p.hash or "") .. ":" .. (p.count or 0))
    end
  end
  local function Head(mode) return "K^" .. CH.version .. "^" .. (target or "") .. "^" .. mode end
  local whole = Head(profs and "p" or "a") .. "^" .. table.concat(entries, "^")
  if strlen(whole) <= maxLen then return { whole } end
  local out, cur = {}, Head("p")
  for _, e in ipairs(entries) do
    if cur ~= Head("p") and strlen(cur) + 1 + strlen(e) > maxLen then
      table.insert(out, cur)
      cur = Head("p")
    end
    cur = cur .. "^" .. e
  end
  table.insert(out, cur)
  return out
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

-- Splits a profession into numbered chunks (same result every time)
local function Chunks(prof)
  local p = CH.me.profs[prof]
  local chunks, blob = {}, ""
  local head = "E^" .. prof .. "^999^"
  for _, r in ipairs(p.recipes) do
    local e = EncodeEntry(r)
    if blob ~= "" and strlen(head) + strlen(blob) + 1 + strlen(e) > MAX_MSG then
      table.insert(chunks, blob)
      blob = ""
    end
    blob = (blob == "") and e or (blob .. "~" .. e)
  end
  if blob ~= "" or table.getn(chunks) == 0 then table.insert(chunks, blob) end
  return chunks
end

-- only = { [n] = true } resends just those chunks
local function SendProf(route, target, prof, only)
  local p = CH.me.profs[prof]
  if not p then return end
  local chunks = Chunks(prof)
  if not only then
    Send(route, target, "P^" .. prof .. "^" .. (p.rank or 0) .. "^" .. (p.max or 0) .. "^"
      .. (p.hash or "") .. "^" .. (p.count or 0) .. "^" .. (p.craft or 0) .. "^" .. table.getn(chunks))
  end
  for i, c in ipairs(chunks) do
    if not only or only[i] then Send(route, target, "E^" .. prof .. "^" .. i .. "^" .. c) end
  end
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
    for i, body in ipairs(KeyBodies(name, profs, 250 - strlen(KEY_TEXT))) do
      Send("WHISPER", name, body, (i == 1) and (KEY_TEXT .. body) or nil)
    end
  else
    for _, body in ipairs(KeyBodies(name, profs, MAX_MSG)) do Send(route, nil, body) end
  end
  CH.Print("Shared " .. table.concat(names, ", ") .. " with " .. name .. ".")
end

function CH.AnnounceGuild(verbose)
  if not IsInGuild() then
    if verbose then CH.Print("You are not in a guild.") end
    return
  end
  if CH.Count(CH.me.profs) == 0 then return end
  CH.shared["@guild"] = {}
  for prof in pairs(CH.me.profs) do CH.shared["@guild"][prof] = true end
  for _, body in ipairs(KeyBodies("", nil, MAX_MSG)) do Send("GUILD", nil, body) end
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
  CH.requests[name] = CH.requests[name] or { n = 0 }
  CH.requests[name].t = GetTime()
  return true
end

-- open requests: name -> { t = sent at, n = retries }
CH.requests = {}

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
    if CH.OnListSent then CH.OnListSent(name, list) end
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
  if CH.OnListSent then CH.OnListSent(name, list) end
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
        or (route == "GUILD" and CH.shared["@guild"] and CH.shared["@guild"][prof])
      if ok and (not answered[key] or GetTime() - answered[key] > 20) then
        answered[key] = GetTime()
        SendProf(route, target, prof)
      end
    end

  elseif kind == "R" then
    if f[2] ~= CH.player then return end
    local prof = f[3] or ""
    local p = CH.me.profs[prof]
    local ok = (CH.shared[from] and CH.shared[from][prof])
      or (route == "GUILD" and CH.shared["@guild"] and CH.shared["@guild"][prof])
    if not p or not ok then return end
    local target = (route == "WHISPER") and from or nil
    -- they missed whispers: send slower from now on
    if route == "WHISPER" then CH.SlowerWhispers() end
    if p.hash ~= f[4] then
      SendProf(route, target, prof)      -- changed meanwhile: everything again
    else
      local only = {}
      for _, n in ipairs((CH.Split(f[5] or "", ","))) do
        if tonumber(n) then only[tonumber(n)] = true end
      end
      SendProf(route, target, prof, only)
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
      count = tonumber(f[6]) or 0, craft = (f[7] == "1") and 1 or nil,
      nchunks = tonumber(f[8]) or 1, parts = {}, got = 0,
      from = from, prof = f[2] or "", route = route, last = GetTime(), tries = 0,
    }

  elseif kind == "E" then
    local prof = f[2] or ""
    local s = staging[from .. "\1" .. prof]
    local n = tonumber(f[3])
    if not s or not n then return end
    -- the entry text itself may not contain "^", so f[4] is the whole blob
    if not s.parts[n] then
      s.parts[n] = f[4] or ""
      s.got = s.got + 1
      s.tries = 0  -- progress: count retries only while nothing arrives
    end
    s.last = GetTime()
    if s.got >= s.nchunks then
      staging[from .. "\1" .. prof] = nil
      s.recipes = {}
      for i = 1, s.nchunks do
        for _, e in ipairs((CH.Split(s.parts[i] or "", "~"))) do
          if e ~= "" then table.insert(s.recipes, DecodeEntry(e)) end
        end
      end
      s.parts, s.got, s.nchunks, s.from, s.prof, s.route, s.last, s.tries = nil
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

-- Watchdog: chunks that went missing (chat limit, lag) are asked for again
local watch = CreateFrame("Frame")
watch.next = 0
watch:SetScript("OnUpdate", function()
  if GetTime() < watch.next then return end
  watch.next = GetTime() + 1
  -- a request (or the list start) may have been dropped: ask again
  for name, r in pairs(CH.requests) do
    local busy
    for key in pairs(staging) do
      if strsub(key, 1, strlen(name) + 1) == name .. "\1" then busy = true end
    end
    if not busy and GetTime() - r.t > 20 then
      if r.n < 3 and CH.IsOutdated(name) then
        r.n = r.n + 1
        CH.RequestUpdate(name)
      else
        CH.requests[name] = nil
      end
    end
  end
  for key, s in pairs(staging) do
    local wait = (s.route == "WHISPER") and 15 or 8
    if GetTime() - s.last > wait then
      if s.tries >= 4 then
        staging[key] = nil
        CH.Print("Could not load " .. s.from .. "'s " .. s.prof .. " completely. Try Update later.")
      else
        s.tries = s.tries + 1
        s.last = GetTime()
        local missing = {}
        for i = 1, s.nchunks do
          if not s.parts[i] and table.getn(missing) < 40 then table.insert(missing, i) end
        end
        local body = "R^" .. s.from .. "^" .. s.prof .. "^" .. (s.hash or "") .. "^" .. table.concat(missing, ",")
        if s.route == "WHISPER" then
          Send("WHISPER", s.from, body)
        else
          Send(s.route, nil, body)
        end
      end
    end
  end
end)

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

-- Nothing is shared or synced automatically: keys go out only when you
-- press Send / Guild, and data only to players who then ask for it.

--------------------------------------------------------------------------
-- Name suggestions for "Share with player": group, friends, whispers
-- of this session, your alts and players who shared with you
--------------------------------------------------------------------------

local recent = {}  -- names whispered with this session, newest last

local function Remember(name)
  if not name or name == "" then return end
  for i, n in ipairs(recent) do
    if n == name then table.remove(recent, i); break end
  end
  table.insert(recent, name)
end
CH.On("CHAT_MSG_WHISPER", function(_, from) Remember(from) end)
CH.On("CHAT_MSG_WHISPER_INFORM", function(_, to) Remember(to) end)

-- Returns { {name, tag}, ... } whose name starts with prefix
function CH.NameSuggestions(prefix)
  prefix = strlower(prefix or "")
  local out, seen = {}, { [CH.player] = true }
  local function Add(name, tag)
    if not name or seen[name] then return end
    if prefix ~= "" and strsub(strlower(name), 1, strlen(prefix)) ~= prefix then return end
    seen[name] = true
    table.insert(out, { name = name, tag = tag })
  end
  for i = 1, GetNumRaidMembers() do Add(UnitName("raid" .. i), "group") end
  for i = 1, GetNumPartyMembers() do Add(UnitName("party" .. i), "group") end
  for i = table.getn(recent), 1, -1 do Add(recent[i], "whisper") end
  if GetNumFriends then
    for i = 1, GetNumFriends() do
      local name, _, _, _, connected = GetFriendInfo(i)
      Add(name, connected and "friend" or "friend, offline")
    end
  end
  for name in pairs(CH.db.chars[CH.realm]) do Add(name, "your alt") end
  for name in pairs(CH.others) do Add(name, "shared with you") end
  return out
end
