--[[---------------------------------------------------------
	HUD card settings - defaults and limits, shared by the card itself
	(cl_hud_card.lua), its editor (cl_hud_editor.lua, Site Admin > HUD
	Card) and the server that validates/saves them (core/sv_hud_settings.lua).
-----------------------------------------------------------]]

-- Every separately sizeable piece of text on the card. Size is in pixels
-- at Card Scale 1.0 (the card's scale multiplies it).
PDCity.HUD_TEXT_ELEMENTS = {
	{ Key = "Title",  Label = "Card title",             Default = 24, Weight = 900 },
	{ Key = "Job",    Label = "Job name",               Default = 17, Weight = 600 },
	{ Key = "Name",   Label = "Character name",         Default = 20, Weight = 700 },
	{ Key = "Amount", Label = "Money / currencies",     Default = 17, Weight = 600 },
	{ Key = "Stat",   Label = "Health / armor numbers", Default = 21, Weight = 800 },
}

PDCity.HUD_TEXT_SIZE_MIN = 10
PDCity.HUD_TEXT_SIZE_MAX = 40
PDCity.HUD_TITLE_MAX_LENGTH = 48

-- Card Width/Height, percent of the card's natural size (on top of Card
-- Scale). Width can shrink a little; height only grows - any taller and
-- the extra room goes to the portrait.
PDCity.HUD_WIDTH_MIN, PDCity.HUD_WIDTH_MAX = 70, 250
PDCity.HUD_HEIGHT_MIN, PDCity.HUD_HEIGHT_MAX = 100, 250

function PDCity.DefaultHUDSettings()
	local settings = {
		Scale = 1.0,
		Width = 100,  -- percent, see HUD_WIDTH_MIN/MAX
		Height = 100, -- percent, see HUD_HEIGHT_MIN/MAX
		HealthLow = { r = 230, g = 75, b = 75 },
		HealthHigh = { r = 80, g = 220, b = 125 },
		ArmorLow = { r = 60, g = 110, b = 190 },
		ArmorHigh = { r = 120, g = 190, b = 250 },
		HealthIcon = "",
		ArmorIcon = "",
		DisplayedCurrencies = {},
		CardOpacity = 100, -- percent, card background
		ChipOpacity = 100, -- percent, the boxes inside it (chips, icon boxes, bar tracks)
		Font = "",         -- "" = follow the Site Theme font
		Title = "",        -- "" = the server's brand name (core/sh_brand.lua)
		TextSizes = {},
	}

	for _, element in ipairs(PDCity.HUD_TEXT_ELEMENTS) do
		settings.TextSizes[element.Key] = element.Default
	end

	return settings
end

-- Pixel size (at scale 1.0) for one text element, falling back to its
-- default for missing/old saved settings.
function PDCity.GetHUDTextSize(settings, element)
	local size = tonumber(istable(settings.TextSizes) and settings.TextSizes[element.Key])
	return math.Clamp(math.Round(size or element.Default), PDCity.HUD_TEXT_SIZE_MIN, PDCity.HUD_TEXT_SIZE_MAX)
end
