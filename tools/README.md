# Regenerating data.lua

Run from this folder (Python 3, `pip install lupa` for reading saved variables):

1. `python extract.py Spell.dbc SkillLineAbility.dbc SkillLine.dbc SpellFocusObject.dbc SpellCastTimes.dbc SpellDuration.dbc`
   reads the DBCs from the OctoWoW client MPQs (load order dbc, patch, patch-1..5, patch-A..Y).
2. `python gen_db.py ../data.lua "<WoW>/WTF/Account/<ACCOUNT>/SavedVariables/CraftHouse.lua"`
   writes data.lua: recipes from the DBCs, item names from pfQuest, stats learned from scans.

The recipe-copy version in data.lua only changes when the recipe list changes; share keys
between players with different versions fall back to sending the full lists.
