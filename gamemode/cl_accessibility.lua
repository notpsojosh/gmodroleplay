--[[---------------------------------------------------------
	Readable mode - a per-player, dyslexia-friendly display toggle (F1 >
	Accessibility). Purely client-side and saved in the player's own
	pdcity_readable_mode convar, so it only ever changes their screen.

	When on:
	  - every themed font (cl_theme.lua's PDCity.RebuildFonts), the HUD
	    card's fonts (cl_hud_card.lua) and GMod's own Derma fonts switch to
	    Verdana - a wide, open, evenly spaced system font often recommended
	    for dyslexic readers - about 15% larger
	  - colours shift to softer contrast: warm off-white text instead of
	    bright white, brighter secondary text, and near-solid backgrounds
	    instead of see-through ones, so the game behind menus doesn't
	    show through the text

	Layered on top of the owner's Site Theme (cl_site_theme.lua) rather
	than replacing it - the Site Theme's own colours are kept underneath
	and come back as soon as this is switched off.
-----------------------------------------------------------]]

PDCity.READABLE_FONT = "Verdana"
PDCity.READABLE_TEXT_SCALE = 1.15

local readableCvar = CreateClientConVar("pdcity_readable_mode", "0", true, false, "Dyslexia-friendly fonts, sizes and colours (only affects your own screen)")

function PDCity.IsReadableMode()
	return readableCvar:GetBool()
end

function PDCity.SetReadableMode(enabled)
	RunConsoleCommand("pdcity_readable_mode", enabled and "1" or "0")
end

--[[---------------------------------------------------------
	Colours. Accent colours are left alone (they're the server's identity
	and already high-visibility); only text and surfaces change.
-----------------------------------------------------------]]
local READABLE_COLORS = {
	Background = Color(42, 42, 46, 250),
	TitleBar   = Color(36, 36, 40, 250),
	Panel      = Color(56, 56, 61, 250),
	PanelHover = Color(72, 72, 78, 250),
	Border     = Color(112, 112, 118, 250),
	Text       = Color(240, 236, 224, 255),
	TextDim    = Color(212, 208, 196, 255),
}

-- PDCity.THEME as the Site Theme (or the built-in defaults) set it,
-- without the readable overlay.
local baseColors

local function SnapshotTheme()
	local copy = {}
	for key, col in pairs(PDCity.THEME) do copy[key] = col end
	return copy
end

local function ApplyColors()
	baseColors = baseColors or SnapshotTheme()

	for key, col in pairs(baseColors) do PDCity.THEME[key] = col end

	if PDCity.IsReadableMode() then
		for key, col in pairs(READABLE_COLORS) do PDCity.THEME[key] = col end
	end
end

-- Site Theme syncs restore the base colours first (so a field the theme
-- doesn't set falls back to the base, not the overlay), take a fresh
-- snapshot of what it applied, then re-apply the overlay on top.
local baseApplySiteTheme = PDCity.ApplySiteTheme
function PDCity.ApplySiteTheme(theme)
	if baseColors then
		for key, col in pairs(baseColors) do PDCity.THEME[key] = col end
	end

	baseApplySiteTheme(theme)

	baseColors = SnapshotTheme()
	ApplyColors()
end

--[[---------------------------------------------------------
	GMod's own Derma fonts - list rows, checkboxes, text boxes, tooltips
	and most stock controls use these rather than the themed fonts. The
	"off" specs are GMod's stock definitions, only restored once readable
	mode has actually replaced them.
-----------------------------------------------------------]]
local dermaFontsReplaced = false

local function ApplyDermaFonts(readable)
	if readable then
		surface.CreateFont("DermaDefault", { font = PDCity.READABLE_FONT, size = 14, weight = 500, extended = true })
		surface.CreateFont("DermaDefaultBold", { font = PDCity.READABLE_FONT, size = 14, weight = 800, extended = true })
		dermaFontsReplaced = true
	elseif dermaFontsReplaced then
		surface.CreateFont("DermaDefault", { font = "Tahoma", size = 13, weight = 500, extended = true })
		surface.CreateFont("DermaDefaultBold", { font = "Tahoma", size = 13, weight = 800, extended = true })
		dermaFontsReplaced = false
	end
end

local function Apply()
	local readable = PDCity.IsReadableMode()

	ApplyColors()
	PDCity.RebuildFonts(PDCity.FONT_FAMILY)
	ApplyDermaFonts(readable)

	hook.Run("PDCity_ReadableModeChanged", readable)
end

cvars.AddChangeCallback("pdcity_readable_mode", Apply, "pdcity_ReadableMode")

if PDCity.IsReadableMode() then Apply() end
