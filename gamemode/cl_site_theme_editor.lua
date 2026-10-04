--[[---------------------------------------------------------
	Site Theme Editor - owner-only in-game editor for the whole game's
	colour palette (PDCity.THEME, cl_theme.lua), font family (every
	PDCity_* font, PDCity.RebuildFonts), and branding (server name, logo
	image). A single global config (core/sv_site_theme.lua), edited from
	the Site Admin panel's "Site Theme" tab (cl_site_admin.lua), saved
	once, broadcast to every client the same way the HUD Card settings
	are (cl_hud_editor.lua's own header explains that shape in full).

	Colour/branding edits only take effect on "Save Changes" (same "edit
	in the form, commit on submit" pattern as every other admin form in
	this gamemode) - EXCEPT the font family, which previews live the
	moment it's picked (PDCity.RebuildFonts is cheap and instant, and
	seeing a font choice applied immediately is worth the one exception).
	Closing without saving reverts that live font preview back to
	whatever's actually saved/synced, via PDCity.ApplySiteTheme
	(cl_site_theme.lua) - otherwise an owner previewing fonts and then
	backing out would be stuck seeing an unsaved font everywhere until
	their next reconnect.
-----------------------------------------------------------]]

local function SendSiteTheme(theme)
	net.Start("pdcity_site_theme_admin")
		net.WriteString(util.TableToJSON(theme))
	net.SendToServer()
end

local function ColorToTable(c)
	return { r = c.r, g = c.g, b = c.b, a = c.a }
end

local function TableToColor(t, fallback)
	if not istable(t) then return fallback end
	return Color(t.r or fallback.r, t.g or fallback.g, t.b or fallback.b, t.a or fallback.a)
end

local COLOR_FIELDS = {
	{ Key = "Background", Label = "Background" },
	{ Key = "TitleBar",   Label = "Title Bar" },
	{ Key = "Panel",      Label = "Panel" },
	{ Key = "PanelHover", Label = "Panel (Hover)" },
	{ Key = "Accent",     Label = "Accent" },
	{ Key = "AccentDim",  Label = "Accent (Dim)" },
	{ Key = "Accent2",    Label = "Accent 2" },
	{ Key = "PriceGreen", Label = "Price Green" },
	{ Key = "Text",       Label = "Text" },
	{ Key = "TextDim",    Label = "Text (Dim)" },
	{ Key = "Border",     Label = "Border" },
}

-- core/sv_site_theme.lua's DefaultTheme() mirrored client-side - both the
-- form's starting point before anything's synced yet, and what "Reset to
-- Defaults" sends.
local function DefaultTheme()
	return {
		Colors = {
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
		},
		FontFamily = "Roboto",
		BrandName = "",
		LogoImage = "",
	}
end

-- A small popout mixer rather than 11 permanently-expanded DColorMixers
-- stacked in the form (each one's tall enough that 11 of them would make
-- this an enormous scroll) - click a swatch, adjust, close; the swatch
-- itself always shows the live result.
local function OpenColorPopup(current, onChange)
	local frame = PDCity.OpenPicker("Choose a Colour", 360, 380)

	local mixer = vgui.Create("DColorMixer", frame)
	mixer:SetPos(16, 48)
	mixer:SetSize(frame:GetWide() - 32, frame:GetTall() - 64)
	mixer:SetPalette(true)
	mixer:SetAlphaBar(true)
	mixer:SetWangs(false)
	mixer:SetColor(current)
	mixer.ValueChanged = function(self, col) onChange(col) end
end

function PDCity.BuildSiteThemeEditorTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local formHolder = vgui.Create("DPanel", root)
	formHolder:Dock(FILL)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(14, 14, 14, 14)
	PDCity.ApplyFastScroll(form)

	local intro = vgui.Create("DLabel", form)
	intro:Dock(TOP)
	intro:SetTall(36)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetText("Global for every player on the server, not a personal preference. Colours/branding save on \"Save Changes\"; the font family previews live as you pick it.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	-- Working copy - matches core/sv_site_theme.lua's own shape exactly,
	-- so it can be sent back verbatim via SendSiteTheme.
	local working = DefaultTheme()

	local function LoadWorkingFrom(theme)
		working = DefaultTheme()
		if not istable(theme) then return end

		if istable(theme.Colors) then
			for key in pairs(working.Colors) do
				if istable(theme.Colors[key]) then working.Colors[key] = theme.Colors[key] end
			end
		end
		if isstring(theme.FontFamily) then working.FontFamily = theme.FontFamily end
		if isstring(theme.BrandName) then working.BrandName = theme.BrandName end
		if isstring(theme.LogoImage) then working.LogoImage = theme.LogoImage end
	end
	LoadWorkingFrom(PDCity.SITE_THEME)

	--[[-------------------------------------------------------
		Branding - server name + logo image.
	---------------------------------------------------------]]
	local brandLabel = vgui.Create("DLabel", form)
	brandLabel:Dock(TOP)
	brandLabel:SetTall(18)
	brandLabel:DockMargin(0, 10, 0, 0)
	brandLabel:SetText("Server Name (blank = the default from core/sh_brand.lua)")
	brandLabel:SetTextColor(PDCity.THEME.TextDim)

	local brandEntry = vgui.Create("DTextEntry", form)
	brandEntry:Dock(TOP)
	brandEntry:SetTall(28)
	brandEntry:DockMargin(0, 4, 0, 0)
	brandEntry:SetPlaceholderText(PDCity.BRAND_NAME)

	local logoLabel = vgui.Create("DLabel", form)
	logoLabel:Dock(TOP)
	logoLabel:SetTall(18)
	logoLabel:DockMargin(0, 14, 0, 0)
	logoLabel:SetText("Logo Image (blank = the built-in logo) - a path under materials/ (with extension), or a full http(s) URL")
	logoLabel:SetTextColor(PDCity.THEME.TextDim)

	local logoRow = vgui.Create("DPanel", form)
	logoRow:Dock(TOP)
	logoRow:SetTall(48)
	logoRow:DockMargin(0, 4, 0, 0)
	logoRow.Paint = function() end

	local logoPreview = vgui.Create("DPanel", logoRow)
	logoPreview:Dock(LEFT)
	logoPreview:SetWide(48)
	logoPreview.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Background)
		local path = string.Trim(working.LogoImage or "")
		local mat = path ~= "" and PDCity.GetIconMaterial(path) or PDCity.LOGO_MAT
		if mat and not mat:IsError() then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(mat)
			surface.DrawTexturedRect(4, 4, w - 8, h - 8)
		end
	end

	local logoEntry = vgui.Create("DTextEntry", logoRow)
	logoEntry:Dock(FILL)
	logoEntry:DockMargin(8, 0, 0, 0)
	logoEntry:SetPlaceholderText("pdcity_custom/mylogo.png, or https://...")
	logoEntry.OnValueChange = function(self, val) working.LogoImage = val end

	--[[-------------------------------------------------------
		Font family - previews live via PDCity.RebuildFonts the moment a
		choice is picked, reverted on close if never saved (see this
		file's own header).
	---------------------------------------------------------]]
	local fontLabel = vgui.Create("DLabel", form)
	fontLabel:Dock(TOP)
	fontLabel:SetTall(18)
	fontLabel:DockMargin(0, 14, 0, 0)
	fontLabel:SetText("Font Family (previews immediately)")
	fontLabel:SetTextColor(PDCity.THEME.TextDim)

	local fontCombo = vgui.Create("DComboBox", form)
	fontCombo:Dock(TOP)
	fontCombo:SetTall(28)
	fontCombo:DockMargin(0, 4, 0, 0)
	for _, family in ipairs(PDCity.FONT_CHOICES) do
		fontCombo:AddChoice(family)
	end
	fontCombo.OnSelect = function(self, index, family)
		working.FontFamily = family
		PDCity.RebuildFonts(family)
	end

	--[[-------------------------------------------------------
		Colours - one compact swatch row per palette field.
	---------------------------------------------------------]]
	local colorsLabel = vgui.Create("DLabel", form)
	colorsLabel:Dock(TOP)
	colorsLabel:SetTall(18)
	colorsLabel:DockMargin(0, 14, 0, 0)
	colorsLabel:SetText("Colour Palette")
	colorsLabel:SetTextColor(PDCity.THEME.TextDim)

	for _, fieldData in ipairs(COLOR_FIELDS) do
		local row = vgui.Create("DPanel", form)
		row:Dock(TOP)
		row:SetTall(32)
		row:DockMargin(0, 4, 0, 0)
		row.Paint = function() end

		local rowLabel = vgui.Create("DLabel", row)
		rowLabel:Dock(LEFT)
		rowLabel:SetWide(150)
		rowLabel:SetText(fieldData.Label)
		rowLabel:SetTextColor(PDCity.THEME.Text)

		local swatch = vgui.Create("DButton", row)
		swatch:Dock(FILL)
		swatch:SetText("")

		local key = fieldData.Key
		swatch.Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Background)
			draw.RoundedBox(3, 3, 3, w - 6, h - 6, TableToColor(working.Colors[key], PDCity.THEME.Panel))
		end
		swatch.DoClick = function()
			OpenColorPopup(TableToColor(working.Colors[key], PDCity.THEME.Panel), function(col)
				working.Colors[key] = ColorToTable(col)
			end)
		end
	end

	--[[-------------------------------------------------------
		Load current values into every control above.
	---------------------------------------------------------]]
	local function LoadIntoForm()
		LoadWorkingFrom(PDCity.SITE_THEME)
		brandEntry:SetValue(working.BrandName or "")
		logoEntry:SetValue(working.LogoImage or "")
		fontCombo:SetValue(working.FontFamily or "Roboto")
	end
	LoadIntoForm()

	--[[-------------------------------------------------------
		Save / Reset
	---------------------------------------------------------]]
	local btnRow = vgui.Create("DPanel", form)
	btnRow:Dock(TOP)
	btnRow:SetTall(28)
	btnRow:DockMargin(0, 16, 0, 0)
	btnRow.Paint = function() end

	local saveBtn = vgui.Create("DButton", btnRow)
	saveBtn:Dock(FILL)
	PDCity.StyleButton(saveBtn, "Save Changes")
	saveBtn.DoClick = function()
		working.BrandName = brandEntry:GetValue()
		working.LogoImage = logoEntry:GetValue()
		SendSiteTheme(working)
	end

	local resetBtn = vgui.Create("DButton", btnRow)
	resetBtn:Dock(RIGHT)
	resetBtn:SetWide(140)
	resetBtn:DockMargin(8, 0, 0, 0)
	PDCity.StyleButton(resetBtn, "Reset to Defaults", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	resetBtn.DoClick = function()
		SendSiteTheme(DefaultTheme())
		timer.Simple(0.2, function() if IsValid(form) then LoadIntoForm() end end)
	end

	-- Reverts any live font preview that never got saved - see this
	-- file's own header for why the font family is the one field that
	-- previews before Save at all.
	root.OnRemove = function()
		if isfunction(PDCity.ApplySiteTheme) then PDCity.ApplySiteTheme(PDCity.SITE_THEME) end
	end

	root.PDCityRefresh = LoadIntoForm

	return root

end
