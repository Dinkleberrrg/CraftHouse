# CraftHouse

Profession browser for WoW 1.12 (OctoWoW / Turtle-like servers), in the style of the auction house.

## Features

- **Search like the auction house:** search by name, required level range (e.g. 20–30), minimum quality, a stat with a minimum value (Int, Sta, Spell Power, Armor, resistances, ...), and a category. Only categories that exist in the current view are listed (Head, Chest, ..., Bag, Enchant, and for consumables Health, Mana, Buff food, Buff, Bandage, Poison, Explosive, Material). A stat filter sorts by that stat, highest first.
- **Leveling mode (Skill-up):** hides grey recipes and sorts orange > yellow > green. The colour bar on each row shows the difficulty, and the "Can" column shows how many you can craft from your bags.
- **Craft from anywhere:** "Craft" also works when the profession window is closed. CraftHouse opens it first, then crafts.
- **Queue (to-do list):** right-click a recipe (or use "+ Queue") to add it. The queue shows which reagents are still missing, and "Craft next" works through it.
- **Global search:** pick "Everyone" as source to search your own characters and all shared players at once, e.g. healing gear from Leatherworking, Blacksmithing and Tailoring. The right column shows who can craft each item.
- **Share recipes:** "Send" lets you pick which professions to share (preselected: the open or selected one) and sends your recipe *key* to a player. The key is a short summary (profession, rank and a hash of your recipe list). If they use CraftHouse, their addon checks its local cache and only downloads professions that changed, so they can browse and filter your recipes and click "Ask to craft". "Guild" shares the key with your guild; guild members load your recipes when they select you. Guild, party and raid members get hidden addon messages. Anyone else gets hidden whispers, and recipe data is only sent to players who ask for it with the addon.
- **Share to-do lists:** select another player as source, right-click their recipes to build a to-do list for them, then "Send to <name>" in the queue panel. They find it in the queue panel's list menu ("From <you>") and "Take over" moves it into their queue, with missing reagents. "Send" sends your own queue to the name under "Share with player".
- **Chat links:** shift-click one of your profession tabs to put a code like `[CH:Enchanting:300:...]` into the chat line (e.g. "LFW Enchanter [CH:...]"). Other CraftHouse users see a clickable link that shows exactly your recipes; players without the addon only see the code.
- **Local recipe copy:** `data.lua` holds every profession recipe of the OctoWoW client (generated from the client files with `tools/gen_db.py` on branch `dev`, item names from pfQuest, stats learned from scans). It is regenerated after server patches.
- Your alts show up automatically once you have opened their professions, marked as (your alt). To-do lists for an alt work the same as for other players, but nothing is sent: the list waits for that character and is announced in chat when you log in with it.

## Usage

- Open a profession: CraftHouse opens instead of the Blizzard window (the Blizzard window stays open off-screen, because crafting needs it).
- `/ch` opens/closes the window anywhere (to browse your alts or shared recipes).
- Shift-click a recipe to link it in chat. Ctrl + mouse wheel scales the window.

| Command | |
|---|---|
| `/ch` | open/close |
| `/ch send <name>` | share your recipes with a player |
| `/ch guild` | share your recipes with your guild |
| `/ch replace` | toggle replacing the Blizzard profession window |
| `/ch autoopen` | toggle opening with the profession window |
| `/ch forget <name>` | delete a player's shared recipes |
| `/ch reset` | reset window position and scale |

Stats are read from the item tooltips of an **enUS** client.
