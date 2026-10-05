# Changelog

## 1.5.1
- Fix: a selected recipe got deselected right away while the profession was open. The profession update events (also fired by CraftHouse itself and by bag changes) triggered a rescan loop that replaced every recipe; now it only rescans when rank or recipe count changes, and the selection is kept by name.

## 1.5.0
- Level and skill-up colour are separate sort keys: Skill-up sorts by colour, clicking Lvl sorts by level (again: reverse).
- Empty received lists disappear; sent to-do lists are removed from your drafts; lists for/from others have a Delete button.
- Name suggestions when sharing (like the mailbox): group, whispers of this session, friends, your alts, players who shared with you. Type to filter or click v.
- Nothing syncs automatically any more: no guild announcement on login or after new recipes, no requests when you pick a player. Use Send, Guild and Update.

## 1.4.0
- Categories are dynamic: only categories with recipes in the current view are listed, with counts. New categories for items without a slot: Health, Mana, Health + Mana, Buff food, Buff, Bandage, Poison, Explosive, Material.
- Share only some professions: Send opens a picker, preselected with the open (or selected) profession. Requests for professions you did not share are ignored.
- Global search: source "Everyone" searches you, your alts and all shared players at once; the right column shows who can craft it, and right-click adds it to the to-do list for that player.

## 1.3.0
- To-do lists for your own alts: pick your main (or any alt) as source, build the list, Send list. It is stored locally and waits for that character; a chat notice on login points to it.
- Alts are marked (your alt) in the source menu; Ask to craft is only shown for other players.

## 1.2.0
- Delete button (bottom right) for saved players and alts, with confirmation; /ch forget also deletes alts.
- Profession tabs size to their text and use short names (Leather, Smithing, ...) when they do not fit; hover shows rank/max.
- Long texts no longer wrap into other rows; reagent and missing-reagent lists are capped so they stay inside their panels.

## 1.1.0
- Share to-do lists: browse another player's recipes, right-click to build a to-do list for them and send it. Received lists appear in the queue panel's list menu; Take over moves the recipes you know into your queue. Your own queue can be sent too (Send).

## 1.0.0
- First release: auction-house style search (name, level range, quality, stat, category), skill-up mode, crafting queue with missing reagents, recipe sharing via key + local cache.
