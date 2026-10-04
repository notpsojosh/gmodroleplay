# PD Roleplay - setup

## Installing

1. Put this folder in your server's `garrysmod/gamemodes/` folder, named
   `pdroleplay` (so you have `garrysmod/gamemodes/pdroleplay/pdroleplay.txt`).
2. Add `+gamemode pdroleplay` to your server's launch options (and
   `+host_workshop_collection <id>` if you use a Workshop collection - see
   below).
3. Make yourself owner. Either:
   - open `gamemode/core/sh_permissions.lua` and add your SteamID to
     `PDCity.OWNER_STEAMIDS`:
     ```lua
     PDCity.OWNER_STEAMIDS = {
         ["STEAM_0:1:12345678"] = true,
     }
     ```
     (type `status` in your game console while on the server to see your
     SteamID), or
   - give yourself the `owner` usergroup with ULX, if you run it.
4. Start the server, join, and press **F1** - Site Admin and Catalogue are at
   the bottom of the sidebar. Everything else (jobs, shop, laws, rules, door
   factions, HUD, theme) is set up from there, live, with no restart.

## Renaming the gamemode

Almost everything the gamemode shows players - chat prefixes like
`[PD Roleplay] ...`, the F1 info menu, the gamemode's own name - comes from
one file:

**`gamemode/core/sh_brand.lua`**

Open it and change `PDCity.BRAND_NAME` (and `PDCity.BRAND_TAG` if you want a
shorter chat prefix than your full name). That's the whole rename.

Two things live outside Lua and need a manual edit each, because the engine
reads them before any gamemode script runs:

1. **The gamemode picker entry** - edit the `"title"` line in
   `pdroleplay.txt` (the file right next to this one).
2. **The logo image** - `gamemode/cl_theme.lua` loads it from
   `materials/pdcity/PDCity.png`. Replace that file with your own art (same
   path/name), or point `PDCity.LOGO_PATH` in `sh_brand.lua` at a different
   one you add.


If you also want the folder name itself changed (`gamemodes/pdroleplay/`),
rename the folder, rename `pdroleplay.txt` to match, and update the
`"pdroleplay"` key on its first line - GMod keys a gamemode off its `.txt`
file, not the folder name, but convention is to keep them matching.

## F1 Site Admin panel (in-game, no file editing)

Once you're the owner (see Installing above), open
F1 in-game and click "Site Admin" at the bottom of the sidebar. From there
you can edit, live, with no restart:

- **Workshop Link** - the URL opened by the welcome screen's "OPEN
  COLLECTION" button, the F1 Content tab, and `!content` in chat.
- **Welcome Screen** - the title/body/button text (and an optional image)
  on each of the three boxes shown when a player first joins.
- **News Posts** - write update/news cards for the F1 menu's "Welcome" tab -
  title, body, an optional image, an optional link button.
- **Warrant Approvers** - who can approve/deny warrant requests. Used to be
  hardcoded to "Government, level 5+"; now pick any mix of usergroups,
  specific jobs, or class+level rules - anyone matching ANY of them
  qualifies. Owner/superadmin can always approve regardless.
- **XP System** - one on/off switch for the whole job-class XP/levelling
  system. See **XP_SYSTEM.md** (next to this file) for how to wire up your
  own XP-earning activities or level-based rewards.

## Workshop content

The gamemode itself needs no Workshop content. If you want extra player
models, maps or props, make your own Workshop collection, add its ID to your
launch options with `+host_workshop_collection`, and paste its link into
Site Admin > Workshop Link so players can find it in-game (`!content`).

## Door system

Door ownership, keys and the battering ram are built into the gamemode
(`gamemode/doors/`, plus `weapon_keys` and `weapon_ram` in
`entities/weapons/`) - nothing to install separately. It's based on the
MIT-licensed Universal Door System by OPGman; keep `gamemode/doors/LICENSE`
with the files.

Upgrading from an older version that used a separate addon: delete
`garrysmod/addons/door_system/`, or the two copies will load on top of each
other. Your saved door data (`data/doorsystem/`) is unchanged and still used.

## What's NOT renamed, on purpose

Internal code - the `PDCity` Lua table every function and setting lives in
(`PDCity.GetJob`, `PDCity.THEME`, ...), hook names (`PDCity_...`), network
message names (`pdcity_...`), and the `data/pdcity/` save folder - all keep
their original names. None of that is ever shown to players, and renaming
it would break saved data and any custom code written against it.
