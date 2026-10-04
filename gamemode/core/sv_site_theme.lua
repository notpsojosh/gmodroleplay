--[[---------------------------------------------------------
	Owner-editable site-wide theme: the PDCity.THEME colour palette
	(cl_theme.lua), which font family every PDCity_* font renders with
	(surface.CreateFont only takes a family it can find on the CLIENT's
	own system - see FONT_CHOICES below for the safe/known-installed
	list this is restricted to), and branding (server name, logo image).

	Same "single global config, edited in-game, persisted, broadcast to
	everyone" shape as core/sv_hud_settings.lua - see that file's own
	header for the reasoning; this is the same pattern one level up,
	covering the WHOLE game's look rather than just the HUD card.

	Deliberately global, not per-player - a server's branding/theme is a
	single shared identity, not a personal preference (core/sv_hud_settings.lua's
	Scale/colours are the one exception to that elsewhere, and even those
	are still one global config, not per-player).
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_site_theme_sync")
util.AddNetworkString("pdcity_site_theme_admin")

local SETTINGS_PATH = "pdcity/site_theme.json"

-- Mirrors cl_theme.lua's PDCity.THEME exactly - these ARE its defaults,
-- so a fresh install (no site_theme.json yet) looks identical to before
-- this system existed, and "Reset to Defaults" in the editor gets back
-- to the game's actual original look, not some separate placeholder one.
local function DefaultColors()
	return {
		Background  = { r = 58,  g = 58,  b = 61,  a = 230 },
		TitleBar    = { r = 48,  g = 48,  b = 51,  a = 230 },
		Panel       = { r = 72,  g = 72,  b = 76,  a = 230 },
		PanelHover  = { r = 86,  g = 86,  b = 91,  a = 230 },
		Accent      = { r = 100, g = 170, b = 255, a = 255 },
		AccentDim   = { r = 70,  g = 120, b = 180, a = 255 },
		Accent2     = { r = 150, g = 220, b = 235, a = 255 },
		PriceGreen  = { r = 80,  g = 210, b = 120, a = 255 },
		Text        = { r = 240, g = 240, b = 242, a = 255 },
		TextDim     = { r = 182, g = 182, b = 187, a = 255 },
		Border      = { r = 102, g = 102, b = 107, a = 230 },
	}
end

-- PDCity.FONT_CHOICES itself lives in core/sh_brand.lua (shared) - the
-- client-side Site Theme editor (cl_site_theme_editor.lua) needs the
-- exact same list to populate its dropdown.

local function DefaultTheme()
	return {
		Colors = DefaultColors(),
		FontFamily = "Roboto",
		BrandName = "", -- blank = core/sh_brand.lua's PDCity.BRAND_NAME, untouched
		LogoImage = "", -- blank = the built-in materials/pdcity/PDCity.png
	}
end

PDCity.SITE_THEME = DefaultTheme()

local function SaveTheme()
	file.CreateDir("pdcity")
	file.Write(SETTINGS_PATH, util.TableToJSON(PDCity.SITE_THEME, true))
end

local function LoadTheme()
	local raw = file.Read(SETTINGS_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not istable(data) then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SETTINGS_PATH .. " was unreadable - keeping the default site theme.\n")
		return
	end

	local defaults = DefaultTheme()

	local colors = DefaultColors()
	if istable(data.Colors) then
		for k, v in pairs(data.Colors) do colors[k] = v end
	end
	defaults.Colors = colors

	if isstring(data.FontFamily) then defaults.FontFamily = data.FontFamily end
	if isstring(data.BrandName) then defaults.BrandName = data.BrandName end
	if isstring(data.LogoImage) then defaults.LogoImage = data.LogoImage end

	PDCity.SITE_THEME = defaults
end

LoadTheme()

local function BroadcastTheme(ply)
	net.Start("pdcity_site_theme_sync")
		net.WriteString(util.TableToJSON(PDCity.SITE_THEME))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncSiteTheme", function(ply)
	BroadcastTheme(ply)
end)

local function IsValidColor(c)
	return istable(c) and isnumber(c.r) and isnumber(c.g) and isnumber(c.b)
end

local function IsValidFontChoice(family)
	for _, choice in ipairs(PDCity.FONT_CHOICES) do
		if choice == family then return true end
	end
	return false
end

net.Receive("pdcity_site_theme_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	local newTheme = DefaultTheme()

	local colors = DefaultColors()
	if istable(data.Colors) then
		for key in pairs(colors) do
			local c = data.Colors[key]
			if IsValidColor(c) then
				colors[key] = {
					r = math.Clamp(c.r, 0, 255),
					g = math.Clamp(c.g, 0, 255),
					b = math.Clamp(c.b, 0, 255),
					a = math.Clamp(tonumber(c.a) or 255, 0, 255),
				}
			end
		end
	end
	newTheme.Colors = colors

	if isstring(data.FontFamily) and IsValidFontChoice(data.FontFamily) then
		newTheme.FontFamily = data.FontFamily
	end

	newTheme.BrandName = isstring(data.BrandName) and string.sub(string.Trim(data.BrandName), 1, 40) or ""

	-- Same "URL or an already-uploaded materials/ path" convention as
	-- every other Icon field in this gamemode (core/sh_f4_catalogue.lua,
	-- core/sh_jobs.lua's job Icon, ...) - resolved client-side by the
	-- exact same PDCity.GetIconMaterial (cl_theme.lua) that already
	-- handles both cases, nothing new to build there.
	newTheme.LogoImage = isstring(data.LogoImage) and string.Trim(data.LogoImage) or ""

	PDCity.SITE_THEME = newTheme
	SaveTheme()
	BroadcastTheme()

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") updated the site theme")
end)
