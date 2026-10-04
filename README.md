# PD Roleplay

A police roleplay gamemode for Garry's Mod, built on Sandbox. Jobs, the shop,
laws, rules, door factions and the HUD are all set up from in-game editors -
no config files to edit. No Workshop content is required.

Also available for free on [gmodstore](https://www.gmodstore.com/).

## Features

- **Characters** - multiple characters per player, each with its own name, model and money
- **Jobs and XP** - create jobs and categories in-game with built-in model and weapon pickers; optional job levels
- **Shop** - add entities, weapons and shipments to the F4 shop from the Catalogue
- **Justice** - cuffs, taser, arrest menu with laws and sentences, jail, bail and warrants
- **Doors** - ownership, keys, co-owners, battering ram, and owner-created door factions jobs can unlock
- **Staff tools** - staff menu, tickets, logs, built-in bans; ULX supported but optional
- **Customisation** - site theme, HUD card (colours, size, fonts, opacity), welcome screen, news posts, rules
- **Accessibility** - a per-player readable mode (larger, clearer text and higher contrast)

Everything starts empty - no default jobs, laws, rules or factions - so your
server is set up the way you want it.

## Installing

1. Download or clone this repository into `garrysmod/gamemodes/pdroleplay/`.
2. Start your server with `+gamemode pdroleplay`.
3. Make yourself owner: add your SteamID to `PDCity.OWNER_STEAMIDS` in
   `gamemode/core/sh_permissions.lua`, or give yourself the `owner` usergroup
   with ULX.
4. Join and press **F1** - Site Admin and Catalogue are at the bottom of the menu.

See [SETUP.md](SETUP.md) for renaming the gamemode, the logo, and the Site
Admin panel, and [XP_SYSTEM.md](XP_SYSTEM.md) for hooking into job XP.

## Credits

- Door system based on the Universal Door System by OPGman (MIT) - see `gamemode/doors/LICENSE`.
- Taser logic adapted from [JJL772's Garry's Mod Taser](https://github.com/JJL772/Garry-s-Mod-Taser).
- Built with the help of AI coding tools.

## Licence

[MIT](LICENSE) - free to use, modify and redistribute, including on your own
server or in your own projects. Keep the licence files with the code.
