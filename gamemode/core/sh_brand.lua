--[[---------------------------------------------------------
	Rebranding. This is the ONLY file you need to touch to put your own
	name on this gamemode - every chat prefix ("[PD Roleplay] ..."), the
	F1 info menu title/welcome text, and the gamemode's own name (shown
	in the server browser, admin tools, etc.) all read from the two
	constants below instead of a hardcoded string.

	Included first (shared.lua) so every other file can rely on these
	being set by the time anything actually uses them.

	Two things this file CANNOT change (the engine reads them before any
	Lua runs, so there's no constant to hook into):
	  1. The gamemode's entry in the in-game "Create Server"/gamemode
	     picker - that's the "title" field in pdroleplay.txt, edit it
	     directly.
	  2. This gamemode's logo image (materials/pdcity/PDCity.png,
	     referenced from gamemode/cl_theme.lua) - swap the image file
	     itself, or point PDCity.LOGO_PATH below at your own.
-----------------------------------------------------------]]

PDCity.BRAND_NAME = "PD Roleplay"

-- Used for "[PD Roleplay] ..." chat prefixes. Defaults to the full name
-- above - only set this separately if you want a shorter tag than your
-- full display name (e.g. Name = "Riverside PD Roleplay", Tag = "RPD").
PDCity.BRAND_TAG = PDCity.BRAND_NAME

-- materials/<this>.png, no extension. Swap the file at
-- materials/pdcity/PDCity.png for your own art and this keeps working;
-- rename the folder too and update this path to match. Site Admin's
-- "Site Theme" tab (core/sv_site_theme.lua) can override this at runtime
-- with its own LogoImage instead, without touching this file.
PDCity.LOGO_PATH = "pdcity/PDCity"

-- Every font family the in-game Site Theme editor can pick for the whole
-- game's typography (core/sv_site_theme.lua, cl_site_theme_editor.lua) -
-- shared so both realms agree on the same list (the server validates an
-- admin's submitted choice against it; the client populates its
-- dropdown from it). Restricted to a curated list rather than free text
-- because there's no way to ask a client "do you have font X installed"
-- before picking one, and surface.CreateFont just silently falls back
-- to nothing recognisable if it doesn't. GMod bundles Roboto itself, so
-- it's guaranteed regardless of the player's OS; the rest are all
-- Windows-shipped fonts (GMod's playerbase is overwhelmingly Windows) -
-- Segoe UI in particular is the real native Windows 10/11 UI font, a
-- genuinely good "make it look like a native app" choice, not filler.
PDCity.FONT_CHOICES = { "Roboto", "Segoe UI", "Tahoma", "Verdana", "Trebuchet MS", "Arial", "Georgia", "Consolas", "Impact" }
