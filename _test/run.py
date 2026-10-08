# Offline test: two clients (Henry, Bob) in separate Lua states (lupa).
# Run: python _test/run.py   (needs: python -m pip install lupa)
import os, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ["core.lua", "scan.lua", "craft.lua", "comm.lua", "ui.lua"]


def client(name):
    L = LuaRuntime(unpack_returned_tuples=True)
    L.execute(open(os.path.join(ROOT, "_test", "stubs.lua")).read())
    L.execute(f'PLAYER = "{name}"')
    for f in FILES:
        L.execute(open(os.path.join(ROOT, f), encoding="utf-8").read())
    L.execute('Fire("VARIABLES_LOADED")')
    return L


fails = 0


def check(cond, msg):
    global fails
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        fails += 1


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def visible(L):
    s = L.eval('(function() local t = {} for _, o in ipairs(ALL) do if o.rec and o.shown and o.kind == "Button" then table.insert(t, o.rec.n) end end table.sort(t) return table.concat(t, "|") end)()')
    return s.split("|") if s else []


A = client("Henry")
B = client("Bob")

# --- tooltip parsing
A.execute('''
T = {}
local lines = {"+5 Intellect", "+3 Stamina", "45 Armor",
 "Equip: Increases damage and healing done by magical spells and effects by up to 12.",
 "Equip: Restores 4 mana per 5 sec.", "+10 Fire Resistance", "(12.5 damage per second)",
 "Equip: Improves your chance to hit by 1%."}
for _, l in ipairs(lines) do CraftHouse.ParseLine(l, T) end
''')
T = A.eval('T')
check(T['int'] == 5 and T['sta'] == 3 and T['armor'] == 45 and T['sp'] == 12 and T['heal'] == 12, "stats int/sta/armor/sp")
check(T['mp5'] == 4 and T['fire'] == 10 and T['dps'] == 12.5 and T['hit'] == 1, "stats mp5/fire/dps/hit")
check(T['str'] is None and T['mana'] is None, "no phantom stats")

# --- scan tradeskill
A.execute('''
TS = { line = {"Tailoring", 150, 225}, list = {
  {name="Cloth", kind="header"},
  {name="Mystic Robe", kind="optimal", link="|cff1eff00|Hitem:1001:0:0:0|h[Mystic Robe]|h|r",
    reagents={{"Bolt of Wool", 3, "|cffffffff|Hitem:2997:0:0:0|h[Bolt of Wool]|h|r"}},
    tip={{"Mystic Robe"},{"Binds when equipped"},{"Chest","Cloth"},{"40 Armor"},{"+6 Intellect"},{"+4 Spirit"},{"Requires Level 25"}}},
  {name="Linen Belt", kind="trivial", link="|cffffffff|Hitem:1002:0:0:0|h[Linen Belt]|h|r",
    reagents={{"Bolt of Linen Cloth", 1, "|cffffffff|Hitem:2996:0:0:0|h[Bolt of Linen Cloth]|h|r"}},
    tip={{"Linen Belt"},{"Waist","Cloth"},{"10 Armor"},{"+1 Stamina"},{"Requires Level 5"}}},
  {name="Stout Bag", kind="easy", link="|cffffffff|Hitem:1003:0:0:0|h[Stout Bag]|h|r",
    reagents={{"Bolt of Wool", 2, "|cffffffff|Hitem:2997:0:0:0|h[Bolt of Wool]|h|r"}},
    tip={{"Stout Bag"},{"8 Slot Bag"}}},
}}
BAG = { {"|cffffffff|Hitem:2997:0:0:0|h[Bolt of Wool]|h|r", 7} }
''')
A.execute('Fire("TRADE_SKILL_SHOW"); Tick(0.1, 2)')
P = A.eval('CraftHouse.me.profs.Tailoring')
check(P is not None and P['count'] == 3, "scanned 3 recipes")
recs = {r['n']: r for r in P['recipes'].values()}
robe = recs['Mystic Robe']
check(robe['l'] == 25 and robe['c'] == 'Chest' and robe['q'] == 2 and robe['t']['int'] == 6 and robe['t']['spi'] == 4,
      "robe level/slot/quality/stats")
check(recs['Stout Bag']['c'] == 'Bag' and recs['Linen Belt']['c'] == 'Waist', "bag + waist category")
check(A.eval('CraftHouseFrame ~= nil and CraftHouseFrame:IsShown()'), "window opened with profession")
check(visible(A) == ['Linen Belt', 'Mystic Robe', 'Stout Bag'], "all recipes listed")

# --- filters
A.execute('CraftHouse.view.stat = "int"; CraftHouse.view.sort = "stat"; CraftHouse.Refresh()')
check(visible(A) == ['Mystic Robe'], "stat filter int -> robe only")
A.execute('CraftHouse.view.stat = nil; CraftHouse.view.lmin = 1; CraftHouse.view.lmax = 10; CraftHouse.Refresh()')
check(visible(A) == ['Linen Belt'], "level 1-10 -> belt")
A.execute('CraftHouse.view.lmin = 20; CraftHouse.view.lmax = 30; CraftHouse.Refresh()')
check(visible(A) == ['Mystic Robe'], "level 20-30 -> robe")
A.execute('CraftHouse.view.lmin = nil; CraftHouse.view.lmax = nil; CraftHouse.view.skill = true; CraftHouse.Refresh()')
check(visible(A) == ['Mystic Robe', 'Stout Bag'], "skill-up hides grey")
A.execute('CraftHouse.view.skill = false; CraftHouse.view.mats = true; CraftHouse.Refresh()')
check(visible(A) == ['Mystic Robe', 'Stout Bag'], "have mats (7 wool)")
A.execute('CraftHouse.view.mats = false; CraftHouse.view.cat = "Waist"; CraftHouse.Refresh()')
check(visible(A) == ['Linen Belt'], "category waist")
A.execute('CraftHouse.view.cat = "All"; CraftHouse.view.search = "robe"; CraftHouse.Refresh()')
check(visible(A) == ['Mystic Robe'], "search text")
A.execute('CraftHouse.view.search = ""; CraftHouse.Refresh()')

# --- queue + craft
A.execute('''
local p = CraftHouse.me.profs.Tailoring
local robe
for _, r in ipairs(p.recipes) do if r.n == "Mystic Robe" then robe = r end end
robe.prof = "Tailoring"
CraftHouse.QueueAdd(robe, 3)
QR = CraftHouse.QueueReagents()
''')
qr = A.eval('QR[1]')
check(qr['need'] == 9 and qr['have'] == 7, "queue reagents: 9 needed, 7 in bags")
A.execute('CraftHouse.QueueNext()')
check(tuple(A.eval('DONE').values()) == (2, 2), "craft next: DoTradeSkill(2, 2) limited by mats")
A.execute('Fire("SPELLCAST_START", "Mystic Robe"); Fire("SPELLCAST_STOP"); Tick(0.1, 3)')
check(A.eval('CraftHouse.queue[1].count') == 2, "queue ticks down after a cast")
A.execute('Fire("SPELLCAST_START", "Mystic Robe"); Fire("SPELLCAST_INTERRUPTED"); Fire("SPELLCAST_STOP"); Tick(0.1, 3)')
check(A.eval('CraftHouse.queue[1].count') == 2, "interrupted cast does not tick")

A.execute('Fire("TRADE_SKILL_CLOSE"); CAST = nil; DONE = nil')
A.execute('local q = CraftHouse.QueueRecipe(CraftHouse.queue[1]); CraftHouse.Craft(q, 1)')
check(A.eval('CAST') == 'Tailoring', "opens profession when closed")
A.execute('Fire("TRADE_SKILL_SHOW"); Tick(0.1, 2)')
check(A.eval('DONE') is not None, "pending craft runs after open")


# --- sharing
def deliver(src, dst, srcname):
    sent = [list(m.values()) for m in src.eval('SENT').values()]
    src.execute('SENT = {}')
    for m in sent:
        if m[0] == 'WHISPER':
            dst.execute(f'Fire("CHAT_MSG_WHISPER", {lua_str(m[1])}, "{srcname}")')
            dst.execute(f'arg1 = {lua_str(m[1])}; CHATSHOWN = 0; ChatFrame_OnEvent("CHAT_MSG_WHISPER")')
            if dst.eval('CHATSHOWN') != 0:
                print("  visible whisper:", m[1][:70])
            src.execute(f'arg1 = {lua_str(m[1])}; CHATSHOWN = 0; ChatFrame_OnEvent("CHAT_MSG_WHISPER_INFORM")')
            if src.eval('CHATSHOWN') != 0:
                print("  visible outgoing whisper:", m[1][:70])
        else:
            dst.execute(f'Fire("CHAT_MSG_ADDON", "{m[1]}", {lua_str(m[2])}, "{m[3]}", "{srcname}")')
        if len(m[1] if m[0] == 'WHISPER' else m[2]) > 254:
            print("  TOO LONG:", len(m[1]))
    return len(sent)


def pump(rounds=20):
    for _ in range(rounds):
        A.execute('Tick(0.4)')
        B.execute('Tick(0.4)')
        deliver(A, B, "Henry")
        deliver(B, A, "Bob")


A.execute('SENT = {}; CraftHouse.SendKeyTo("bob")')
pump(120)
bp = B.eval('CraftHouse.others.Henry')
check(bp is not None and bp['profs']['Tailoring'] is not None and bp['profs']['Tailoring']['count'] == 3,
      "Bob received Henry's Tailoring")
br = {r['n']: r for r in bp['profs']['Tailoring']['recipes'].values()}
check(br['Mystic Robe']['t']['int'] == 6 and br['Mystic Robe']['l'] == 25 and br['Mystic Robe']['c'] == 'Chest',
      "shared recipe keeps stats/level/slot")
check(br['Mystic Robe']['r'][1][1] == 2997 and br['Mystic Robe']['r'][1][2] == 3, "shared reagents")
B.execute('CraftHouse.Show("Henry"); CraftHouse.view.stat = "int"; CraftHouse.Refresh()')
check(visible(B) == ['Mystic Robe'], "Bob filters Henry's recipes by Int")

# unchanged key -> no request
A.execute('SENT = {}; CraftHouse.SendKeyTo("Bob")')
A.execute('Tick(0.4)')
B.execute('SENT = {}')
deliver(A, B, "Henry")
B.execute('Tick(0.4)')
check(len(list(B.eval('SENT').values())) == 0, "unchanged key -> Bob requests nothing")

# new recipe -> new key -> Bob updates
A.execute('''table.insert(TS.list, {name="Wool Cloak", kind="optimal", link="|cff1eff00|Hitem:1004:0:0:0|h[Wool Cloak]|h|r",
  reagents={{"Bolt of Wool", 2, "|cffffffff|Hitem:2997:0:0:0|h[Bolt of Wool]|h|r"}},
  tip={{"Wool Cloak"},{"Back"},{"+2 Agility"},{"Requires Level 20"}}})''')
A.execute('Fire("TRADE_SKILL_UPDATE"); Tick(0.4, 2)')
A.execute('SENT = {}; CraftHouse.SendKeyTo("Bob")')
pump(120)
check(B.eval('CraftHouse.others.Henry.profs.Tailoring.count') == 4, "Bob's cache updated after new key")

# many recipes -> chunking stays under 255
A.execute('''for i = 1, 120 do table.insert(TS.list, {name="Long Recipe Name Number " .. i, kind="easy",
  link="|cff1eff00|Hitem:" .. (5000+i) .. ":0:0:0|h[x]|h|r",
  reagents={{"Bolt of Wool", 2, "|cffffffff|Hitem:2997:0:0:0|h[Bolt of Wool]|h|r"},{"Thread", 1, "|cffffffff|Hitem:2320:0:0:0|h[Thread]|h|r"}},
  tip={{"x"},{"Hands","Leather"},{"+2 Agility"},{"+3 Stamina"},{"55 Armor"},{"Requires Level 40"}}}) end''')
A.execute('Fire("TRADE_SKILL_UPDATE"); Tick(0.4, 2)')
A.execute('SENT = {}; CraftHouse.SendKeyTo("Bob")')
pump(300)
check(B.eval('CraftHouse.others.Henry.profs.Tailoring.count') == 124, "124 recipes arrive in chunks")

# to-do list: Bob builds a list from Henry's recipes and sends it
B.execute('''CraftHouse.Show("Henry"); CraftHouse.view.stat = nil; CraftHouse.Refresh()
local robe
for _, r in ipairs(CraftHouse.others.Henry.profs.Tailoring.recipes) do if r.n == "Mystic Robe" then robe = r end end
robe.prof = "Tailoring"
CraftHouse.AddToList(robe, 2)
for i = 1, 40 do
  local r = CraftHouse.others.Henry.profs.Tailoring.recipes[i + 4]
  r.prof = "Tailoring"
  CraftHouse.AddToList(r, 1)
end
local list, _, kind, who = CraftHouse.CurrentList()
LKIND, LWHO, LN = kind, who, table.getn(list)
SENT = {}
CraftHouse.SendList(who, list)''')
check(B.eval('LKIND') == 'out' and B.eval('LWHO') == 'Henry' and B.eval('LN') == 41, "Bob's to-do list for Henry has 41 entries")
pump(120)
inc = A.eval('CraftHouse.lists.inc.Bob')
check(inc is not None and len(list(inc['items'].values())) == 41, "Henry received Bob's to-do list (41)")
A.execute('QBEFORE = table.getn(CraftHouse.queue); MOVED = CraftHouse.TakeOver("Bob")')
check(A.eval('MOVED') == 41 and A.eval('CraftHouse.lists.inc.Bob') is None, "take over moves all known recipes to the queue")
A.execute('ROBEQ = 0 for _, e in ipairs(CraftHouse.queue) do if e.name == "Mystic Robe" then ROBEQ = e.count end end')
check(A.eval('ROBEQ') == 4, "robe count merged into existing queue entry (2 + 2)")
# Henry views the UI with an incoming list containing an unknown recipe
A.execute('CraftHouse.lists.inc.Bob = { time = time(), items = { {prof="Tailoring", name="Mystic Robe", count=1}, {prof="Alchemy", name="Unknown Potion", count=3} } }')
A.execute('CraftHouse.view.list = { kind = "in", name = "Bob" }; CraftHouse.Refresh(); MOVED = CraftHouse.TakeOver("Bob")')
check(A.eval('MOVED') == 1 and len(list(A.eval('CraftHouse.lists.inc.Bob.items').values())) == 1, "unknown recipes stay in the received list")

# guild route
A.execute('GUILD = {"Henry", "Bob"}')
B.execute('GUILD = {"Henry", "Bob"}')
A.execute('SENT = {}; CraftHouse.SendKeyTo("Bob"); Tick(0.4)')
s1 = list(list(A.eval('SENT').values())[0].values())
check(s1[0] == 'ADDON' and s1[3] == 'GUILD', "guild member gets addon message, not whisper")

# profession tabs fit (long names get shortened)
A.execute("""CraftHouse.me.profs.Leatherworking = { rank = 300, max = 300, recipes = {} }
CraftHouse.me.profs.Blacksmithing = { rank = 300, max = 300, recipes = {} }
CraftHouse.me.profs.Engineering = { rank = 300, max = 300, recipes = {} }
CraftHouse.me.profs["First Aid"] = { rank = 300, max = 300, recipes = {} }
CraftHouse.me.profs.Cooking = { rank = 300, max = 300, recipes = {} }
CraftHouse.Show(); CraftHouse.Refresh()
RIGHT = 0
for _, o in ipairs(ALL) do if o.prof and o.w and o.shown then local x = o.points[1][4]; if x + o.w > RIGHT then RIGHT = x + o.w end end end""")
check(A.eval('RIGHT') <= 822, "profession tabs fit in the window (right edge %s)" % A.eval('RIGHT'))

# forget a player
A.execute('CraftHouse.others.Bob = { profs = {}, time = time() }; CraftHouse.Show("Bob"); CraftHouse.Forget("Bob")')
check(A.eval('CraftHouse.others.Bob') is None and A.eval('CraftHouse.view.src') is None, "forget deletes player and returns to own recipes")

# alts: the alt browses the main's recipes and leaves a to-do list for the main
A.execute('''
local main = CraftHouse.me
CraftHouse.db.chars.Octo.Altie = { profs = {} }
-- log in as the alt
PLAYER = "Altie"; CraftHouse.player = "Altie"; CraftHouse.InitDB()
CraftHouse.Show("Henry")
local _, kind = CraftHouse.SourceData("Henry")
ALTKIND = kind
local robe
for _, r in ipairs(main.profs.Tailoring.recipes) do if r.n == "Mystic Robe" then robe = r end end
robe.prof = "Tailoring"
CraftHouse.AddToList(robe, 5)
local list, _, k, who = CraftHouse.CurrentList()
SENT = {}
CraftHouse.SendList(who, list)
NSENT = table.getn(SENT)
-- back on the main
PLAYER = "Henry"; CraftHouse.player = "Henry"; CraftHouse.InitDB()
QBEFORE = 0 for _, e in ipairs(CraftHouse.queue) do if e.name == "Mystic Robe" then QBEFORE = e.count end end
MOVED = CraftHouse.TakeOver("Altie")
QAFTER = 0 for _, e in ipairs(CraftHouse.queue) do if e.name == "Mystic Robe" then QAFTER = e.count end end
''')
check(A.eval('ALTKIND') == 'alt', "main shows up as alt source on the alt")
check(A.eval('NSENT') == 0, "list for an alt is stored locally, nothing sent over the network")
check(A.eval('MOVED') == 1 and A.eval('QAFTER') - A.eval('QBEFORE') == 5, "main takes over the alt's list (+5 robes)")

# consumable categories
A.execute('''
local U = CraftHouse.UseCategory
UC = {
  U("use: restores 552 health over 21 sec. if you spend at least 10 seconds eating you will become well fed", "x"),
  U("use: restores 455 to 585 health.", "x"),
  U("use: restores 700 to 900 mana.", "x"),
  U("", "bolt of wool"),
  U("use: heals 400 damage over 8 sec.", "x"),
  U("use: increases agility by 25 for 1 hr.", "x"),
  U("use: restores 1000 health and 1000 mana over 30 sec.", "x"),
  U("use: inflicts 100 to 200 fire damage to enemies in a 5 yard radius", "x"),
}''')
check(list(A.eval('UC').values()) == ['Buff food', 'Health', 'Mana', 'Material', 'Bandage', 'Buff', 'Health + Mana', 'Explosive'],
      "consumable categories: %s" % list(A.eval('UC').values()))

# dynamic categories: only what Tailoring has
A.execute('CraftHouse.Show(); CraftHouse.view.prof = "Tailoring"; CraftHouse.Refresh()')
cats = A.eval('(function() local t = {} for _, o in ipairs(ALL) do if o.cat and o.shown then table.insert(t, o.cat) end end return table.concat(t, ",") end)()').split(",")
check("Bag" in cats and "Chest" in cats and "Head" not in cats and "Health" not in cats, "category list is dynamic: %s" % cats)

# share only some professions
C = client("Carl")
def deliver_to_carl():
    sent = [list(m.values()) for m in A.eval('SENT').values()]
    A.execute('SENT = {}')
    for m in sent:
        if m[0] == 'WHISPER' and m[2] == 'Carl':
            C.execute(f'Fire("CHAT_MSG_WHISPER", {lua_str(m[1])}, "Henry")')
    sent = [list(m.values()) for m in C.eval('SENT').values()]
    C.execute('SENT = {}')
    for m in sent:
        if m[0] == 'WHISPER':
            A.execute(f'Fire("CHAT_MSG_WHISPER", {lua_str(m[1])}, "Carl")')
A.execute('GUILD = nil; SENT = {}; CraftHouse.SendKeyTo("Carl", { Tailoring = true })')
for _ in range(300):
    A.execute('Tick(0.4)'); C.execute('Tick(0.4)'); deliver_to_carl()
ck = C.eval('CraftHouse.others.Henry.key')
check(sorted(ck.keys()) == ['Tailoring'], "partial key only contains Tailoring")
check(C.eval('CraftHouse.others.Henry.profs.Tailoring.count') == 124, "Carl loaded Tailoring")
# Carl asks for Leatherworking anyway -> refused
A.execute('SENT = {}')
A.execute('Fire("CHAT_MSG_WHISPER", "[CH]Q^Henry^Leatherworking", "Carl"); Tick(0.4, 3)')
check(len(list(A.eval('SENT').values())) == 0, "unshared profession is not sent")

# global search: Bob sees Henry's Int items with the crafter name
B.execute('CraftHouse.Show("*"); CraftHouse.view.stat = "int"; CraftHouse.view.prof = "All"; CraftHouse.view.cat = "All"; CraftHouse.Refresh()')
owners = B.eval('(function() local t = {} for _, o in ipairs(ALL) do if o.rec and o.shown and o.kind == "Button" then table.insert(t, o.rec.n .. "@" .. o.rec.owner) end end return table.concat(t, ",") end)()')
check("Mystic Robe@Henry" in owners, "global search lists Henry's robe with owner (%s)" % owners)
B.execute('CraftHouse.view.sel = nil; for _, o in ipairs(ALL) do if o.rec and o.shown and o.rec.n == "Mystic Robe" then CraftHouse.AddToList(o.rec, 1) end end')
check(B.eval('CraftHouse.view.list.kind') == 'out' and B.eval('CraftHouse.view.list.name') == 'Henry', "adding from global search goes to the to-do list for the crafter")

# sorting: skill-up colour vs. level are separate
def order(L):
    return L.eval('(function() local t = {} for _, r in ipairs(CraftHouse.SortedForTest()) do table.insert(t, r.n) end return table.concat(t, ",") end)()').split(",")
A.execute('''
CraftHouse.me.profs.Test = { rank = 1, max = 1, recipes = {
  { n = "A30 green", l = 30, d = "easy", r = {}, t = {} },
  { n = "B10 orange", l = 10, d = "optimal", r = {}, t = {} },
  { n = "C20 yellow", l = 20, d = "medium", r = {}, t = {} },
}}
CraftHouse.Show(); CraftHouse.view.prof = "Test"; CraftHouse.view.stat = nil; CraftHouse.view.cat = "All"
CraftHouse.view.sort = "diff"; CraftHouse.Refresh()
function CraftHouse.SortedForTest()
  local t = {}
  for _, o in ipairs(ALL) do if o.rec and o.shown and o.kind == "Button" and o.points[1] then table.insert(t, { y = o.points[1][5], r = o.rec }) end end
  table.sort(t, function(a, b) return a.y > b.y end)
  local out = {} for _, x in ipairs(t) do table.insert(out, x.r) end
  return out
end''')
check(order(A) == ['B10 orange', 'C20 yellow', 'A30 green'], "colour sort: orange, yellow, green")
A.execute('CraftHouse.view.sort = "level"; CraftHouse.view.asc = true; CraftHouse.Refresh()')
check(order(A) == ['B10 orange', 'C20 yellow', 'A30 green'], "level sort ascending")
A.execute('CraftHouse.view.asc = nil; CraftHouse.Refresh()')
check(order(A) == ['A30 green', 'C20 yellow', 'B10 orange'], "level sort descending, independent of colour")

# empty received list disappears, sent draft is removed
A.execute('CraftHouse.lists.inc.Zed = { time = time(), items = {} }; CraftHouse.view.list = { kind = "in", name = "Zed" }; CraftHouse.Refresh()')
check(A.eval('CraftHouse.lists.inc.Zed') is None and A.eval('CraftHouse.view.list') is None, "empty received list is removed")

# name suggestions
A.execute('Fire("CHAT_MSG_WHISPER_INFORM", "hi", "Whisperguy"); GetNumFriends = function() return 1 end; GetFriendInfo = function() return "Friendo", 60, "Mage", "Org", 1 end')
sug = A.eval('(function() local t = {} for _, x in ipairs(CraftHouse.NameSuggestions("")) do table.insert(t, x.name .. ":" .. x.tag) end return table.concat(t, ",") end)()')
check("Whisperguy:whisper" in sug and "Friendo:friend" in sug and "Altie:your alt" in sug, "name suggestions: %s" % sug)
sug = A.eval('(function() local t = {} for _, x in ipairs(CraftHouse.NameSuggestions("fr")) do table.insert(t, x.name) end return table.concat(t, ",") end)()')
check(sug == "Friendo", "suggestions filter by typed prefix")

# selection survives profession updates (regression: click deselected itself)
A.execute('''TS.list = { TS.list[1], TS.list[2], TS.list[3] }
Fire("TRADE_SKILL_SHOW"); Tick(0.1, 2)
CraftHouse.Show(); CraftHouse.view.prof = "Tailoring"; CraftHouse.view.cat = "All"; CraftHouse.view.stat = nil; CraftHouse.Refresh()
for _, o in ipairs(ALL) do if o.rec and o.shown and o.rec.n == "Mystic Robe" then this = o; arg1 = "LeftButton"; o.scripts.OnClick() end end
SCANS = 0
local orig = CraftHouse.ScanTradeSkill
CraftHouse.ScanTradeSkill = function() SCANS = SCANS + 1; orig() end
for i = 1, 5 do Fire("TRADE_SKILL_UPDATE"); Tick(0.2, 3) end''')
check(A.eval('SCANS') == 0, "update events without changes do not rescan")
check(A.eval('CraftHouse.view.sel and CraftHouse.view.sel.n') == 'Mystic Robe', "selection kept after update events")
A.execute('TS.line[2] = 151; Fire("TRADE_SKILL_UPDATE"); Tick(0.2, 3)')
check(A.eval('SCANS') == 1 and A.eval('CraftHouse.view.sel and CraftHouse.view.sel.n') == 'Mystic Robe', "skill-up rescans once and keeps the selection")

# missing tool (e.g. no Cooking Fire nearby): no craft call, clear message
A.execute('''UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame")
GetTradeSkillTools = function(i) return "Cooking Fire", nil end
DONE = nil
local robe = CraftHouse.view.sel
CraftHouse.Craft(robe, 1)''')
check(A.eval('DONE') is None and 'needs: Cooking Fire' in list(A.eval('OUT').values())[-1], "missing Cooking Fire blocks the craft with a message")
A.execute('GetTradeSkillTools = function(i) return "Cooking Fire", 1 end; CraftHouse.Craft(CraftHouse.view.sel, 1)')
check(A.eval('DONE') is not None, "with the fire nearby it crafts")
A.execute('GetTradeSkillTools = nil')

# whisper share under the server chat limit (regression: receiver ended up empty)
D = client("Dora")
def deliver_pair(src, dst, srcname, dstname):
    sent = [list(m.values()) for m in src.eval('SENT').values()]
    src.execute('SENT = {}')
    for m in sent:
        if m[0] == 'WHISPER' and m[2] == dstname:
            dst.execute(f'Fire("CHAT_MSG_WHISPER", {lua_str(m[1])}, "{srcname}")')
A.execute('''local recs = {}
for i = 1, 124 do table.insert(recs, { n = "Big Recipe Name Number " .. i, id = 7000 + i, q = 2, l = 30, c = "Hands",
  t = { agi = 3, sta = 4, armor = 60 }, r = { {2997, 2, "Bolt of Wool"}, {2320, 1, "Thread"} } }) end
local p = CraftHouse.me.profs.Tailoring
p.recipes, p.count, p.hash = recs, 124, "bigsynthetic"''')
A.execute('LIMIT = true; DROPPED = 0; WHISPERS = {}; SENT = {}')
D.execute('LIMIT = true; DROPPED = 0; WHISPERS = {}')
A.execute('CraftHouse.SendKeyTo("Dora", { Tailoring = true })')
for _ in range(1500):
    A.execute('Tick(0.4)'); D.execute('Tick(0.4)')
    deliver_pair(A, D, "Henry", "Dora"); deliver_pair(D, A, "Dora", "Henry")
dropped = A.eval('DROPPED') + D.eval('DROPPED')
got = D.eval('CraftHouse.others.Henry and CraftHouse.others.Henry.profs.Tailoring and CraftHouse.others.Henry.profs.Tailoring.count')
check(dropped > 0, "chat limit was hit in the simulation (%d whispers dropped)" % dropped)
check(got == 124, "all 124 recipes arrive despite the chat limit (got %s)" % got)
A.execute('LIMIT = nil'); D.execute('LIMIT = nil')

# silent drops (no server message): missing chunks are requested again
E = client("Emma")
A.execute('CraftHouse.me.profs.Tailoring.hash = "bigsynthetic2"; CraftHouse.SetWhisperDelay(0.5); LIMITN = 2; LIMIT = true; SILENT = true; DROPPED = 0; WHISPERS = {}; SENT = {}')
E.execute('LIMIT = true; SILENT = true; DROPPED = 0; WHISPERS = {}')
A.execute('CraftHouse.SendKeyTo("Emma", { Tailoring = true })')
for _ in range(3000):
    A.execute('Tick(0.4)'); E.execute('Tick(0.4)')
    deliver_pair(A, E, "Henry", "Emma"); deliver_pair(E, A, "Emma", "Henry")
got = E.eval('CraftHouse.others.Henry and CraftHouse.others.Henry.profs.Tailoring and CraftHouse.others.Henry.profs.Tailoring.count')
check(A.eval('DROPPED') > 0 and got == 124, "silently dropped chunks are re-requested (%d dropped, got %s)" % (A.eval('DROPPED'), got))
A.execute('LIMIT = nil; SILENT = nil'); E.execute('LIMIT = nil; SILENT = nil')

# a key with many professions is split so whispers stay below 255 chars
A.execute('''for i = 1, 9 do CraftHouse.me.profs["Profession Number " .. i] = { rank = 300, max = 300, hash = "abcdefg", count = 120, recipes = {} } end
SENT = {}; CraftHouse.SendKeyTo("Zed"); Tick(2, 10)''')
lens = [len(list(m.values())[1]) for m in A.eval('SENT').values()]
check(len(lens) > 1 and max(lens) <= 255, "long key split into %d whispers, longest %d chars" % (len(lens), max(lens)))

print("\n%d failures" % fails)
print("--- Henry chat:")
print("\n".join(list(A.eval('OUT').values())[-4:]))
print("--- Bob chat:")
print("\n".join(list(B.eval('OUT').values())[-4:]))
sys.exit(1 if fails else 0)
