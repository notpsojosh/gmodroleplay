--[[---------------------------------------------------------
	Applies the owner-editable site theme (core/sv_site_theme.lua) the
	moment it syncs - colours straight into PDCity.THEME (cl_theme.lua),
	font family via PDCity.RebuildFonts (also cl_theme.lua), branding
	into PDCity.BRAND_NAME/PDCity.LOGO_MAT (core/sh_brand.lua/cl_theme.lua).

	Deliberately mutates PDCity.THEME's existing fields in place
	(PDCity.THEME.Panel = Color(...)) rather than replacing the whole
	table - every menu in the gamemode reads PDCity.THEME.WhateverField
	fresh on every Paint call (nothing caches a reference to the table
	itself at load time), so this takes effect immediately everywhere,
	same frame, with nothing needing to be rebuilt/reopened.
-----------------------------------------------------------]]

local ORIGINAL_BRAND_NAME = PDCity.BRAND_NAME -- core/sh_brand.lua's hardcoded default, captured before this file can ever override it

local function TableToColor(t, fallback)
	if not istable(t) then return fallback end
	return Color(t.r or fallback.r, t.g or fallback.g, t.b or fallback.b, t.a or fallback.a)
end

local function ApplyColors(colors)
	if not istable(colors) then return end
	for key, current in pairs(PDCity.THEME) do
		PDCity.THEME[key] = TableToColor(colors[key], current)
	end
end

local function ApplyBrandName(name)
	PDCity.BRAND_NAME = (isstring(name) and name ~= "") and name or ORIGINAL_BRAND_NAME
end

-- Retries a few times for a URL logo (PDCity.GetIconMaterial returns nil
-- until its async http.Fetch lands) rather than only ever trying once -
-- a materials/ path resolves instantly so this exits after the first
-- attempt for that case anyway.
local function ApplyLogo(path)
	timer.Remove("pdcity_ResolveSiteLogo")

	if not isstring(path) or path == "" then
		PDCity.LOGO_MAT = Material("pdcity/PDCity.png", "noclamp smooth")
		return
	end

	local function TryResolve()
		local mat = PDCity.GetIconMaterial(path)
		if mat then PDCity.LOGO_MAT = mat end
		return mat ~= nil
	end

	if not TryResolve() then
		timer.Create("pdcity_ResolveSiteLogo", 0.5, 10, function()
			if TryResolve() then timer.Remove("pdcity_ResolveSiteLogo") end
		end)
	end
end

-- Global (not local) - cl_site_theme_editor.lua calls this again on
-- close to revert its live font-family preview if it was never saved
-- (see that file's own header).
function PDCity.ApplySiteTheme(theme)
	if not istable(theme) then return end

	ApplyColors(theme.Colors)
	PDCity.RebuildFonts(isstring(theme.FontFamily) and theme.FontFamily or "Roboto")
	ApplyBrandName(theme.BrandName)
	ApplyLogo(theme.LogoImage)
end

net.Receive("pdcity_site_theme_sync", function()
	PDCity.SITE_THEME = util.JSONToTable(net.ReadString() or "{}") or {}
	PDCity.ApplySiteTheme(PDCity.SITE_THEME)
end)
