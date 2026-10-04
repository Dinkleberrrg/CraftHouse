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
pump(30)
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
pump(30)
check(B.eval('CraftHouse.others.Henry.profs.Tailoring.count') == 4, "Bob's cache updated after new key")

# many recipes -> chunking stays under 255
A.execute('''for i = 1, 120 do table.insert(TS.list, {name="Long Recipe Name Number " .. i, kind="easy",
  link="|cff1eff00|Hitem:" .. (5000+i) .. ":0:0:0|h[x]|h|r",
  reagents={{"Bolt of Wool", 2, "|cffffffff|Hitem:2997:0:0:0|h[Bolt of Wool]|h|r"},{"Thread", 1, "|cffffffff|Hitem:2320:0:0:0|h[Thread]|h|r"}},
  tip={{"x"},{"Hands","Leather"},{"+2 Agility"},{"+3 Stamina"},{"55 Armor"},{"Requires Level 40"}}}) end''')
A.execute('Fire("TRADE_SKILL_UPDATE"); Tick(0.4, 2)')
A.execute('SENT = {}; CraftHouse.SendKeyTo("Bob")')
pump(80)
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
pump(30)
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

print("\n%d failures" % fails)
print("--- Henry chat:")
print("\n".join(list(A.eval('OUT').values())[-4:]))
print("--- Bob chat:")
print("\n".join(list(B.eval('OUT').values())[-4:]))
sys.exit(1 if fails else 0)
