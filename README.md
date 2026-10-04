# CraftHouse

Profession browser for WoW 1.12 (OctoWoW / Turtle-like servers), in the style of the auction house.

## Features

- **Search like the auction house:** search by name, required level range (e.g. 20–30), minimum quality, a stat with a minimum value (Int, Sta, Spell Power, Armor, resistances, ...), and a category (Head, Chest, ..., Bag, Enchant). A stat filter sorts by that stat, highest first.
- **Leveling mode (Skill-up):** hides grey recipes and sorts orange > yellow > green. The colour bar on each row shows the difficulty, and the "Can" column shows how many you can craft from your bags.
- **Craft from anywhere:** "Craft" also works when the profession window is closed. CraftHouse opens it first, then crafts.
- **Queue (to-do list):** right-click a recipe (or use "+ Queue") to add it. The queue shows which reagents are still missing, and "Craft next" works through it.
- **Share recipes:** "Send" sends your recipe *key* to a player. The key is a short summary (profession, rank and a hash of your recipe list). If they use CraftHouse, their addon checks its local cache and only downloads professions that changed, so they can browse and filter your recipes and click "Ask to craft". "Guild" shares the key with your guild; guild members load your recipes when they select you. Guild, party and raid members get hidden addon messages. Anyone else gets hidden whispers, and recipe data is only sent to players who ask for it with the addon.
- **Share to-do lists:** select another player as source, right-click their recipes to build a to-do list for them, then "Send to <name>" in the queue panel. They find it in the queue panel's list menu ("From <you>") and "Take over" moves it into their queue, with missing reagents. "Send" sends your own queue to the name under "Share with player".
- Your alts show up automatically once you have opened their professions.

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
