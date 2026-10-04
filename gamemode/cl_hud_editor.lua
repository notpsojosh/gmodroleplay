--[[---------------------------------------------------------
	HUD Card Editor - owner-only in-game editor for cl_hud_card.lua's
	colours, size, health/armor icons, and which custom currencies show
	on it. A single global config (core/sv_hud_settings.lua), not a
	per-player preference - edited from the Site Admin panel's "HUD Card"
	tab (cl_site_admin.lua), saved once, broadcast to every client so
	everyone's card matches whatever the owner picked.

	PDCity.HUD_SETTINGS itself is set by the sync receiver below - falls
	back to nil until the first sync arrives (just after joining), which
	cl_hud_card.lua's own defaults already handle gracefully.
-----------------------------------------------------------]]

net.Receive("pdcity_hud_settings_sync", function()
	PDCity.HUD_SETTINGS = util.JSONToTable(net.ReadString() or "{}") or {}
end)

local function SendHUDSettings(settings)
	net.Start("pdcity_hud_settings_admin")
		net.WriteString(util.TableToJSON(settings))
	net.SendToServer()
end

local function ColorToTable(c)
	return { r = c.r, g = c.g, b = c.b }
end

local function TableToColor(t, fallback)
	if not istable(t) then return fallback end
	return Color(t.r or fallback.r, t.g or fallback.g, t.b or fallback.b)
end

function PDCity.BuildHUDEditorTab(parent)

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
	intro:SetText("Global for every player on the server, not a personal preference. Press Save Changes, then close F1 to see the result on your own HUD card.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	-- Working copy - only actually applied (sent + saved) when "Save
	-- Changes" is pressed, same "edit in the form, commit on submit"
	-- pattern as every other admin form in this gamemode. Seeded from
	-- whatever's currently live (or the same built-in defaults
	-- core/sv_hud_settings.lua falls back to if nothing's synced yet).
	local DEFAULTS = PDCity.DefaultHUDSettings() -- core/sh_hud_settings.lua

	local function CurrentOrDefault()
		local live = PDCity.HUD_SETTINGS or {}
		local out = {}
		for k, v in pairs(DEFAULTS) do
			if live[k] ~= nil then out[k] = live[k] else out[k] = v end
		end
		out.DisplayedCurrencies = {}
		for _, id in ipairs(live.DisplayedCurrencies or {}) do table.insert(out.DisplayedCurrencies, id) end
		return out
	end

	local function SectionLabel(text)
		local label = vgui.Create("DLabel", form)
		label:Dock(TOP)
		label:SetTall(18)
		label:DockMargin(0, 14, 0, 0)
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.TextDim)
		return label
	end

	local function Slider(labelText, min, max)
		local slider = vgui.Create("DNumSlider", form)
		slider:Dock(TOP)
		slider:SetTall(26)
		slider:DockMargin(0, 2, 0, 0)
		slider:SetText(labelText)
		slider:SetMin(min)
		slider:SetMax(max)
		slider:SetDecimals(0)
		slider.Label:SetTextColor(PDCity.THEME.Text)
		return slider
	end

	--[[-------------------------------------------------------
		Scale
	---------------------------------------------------------]]
	local scaleLabel = vgui.Create("DLabel", form)
	scaleLabel:Dock(TOP)
	scaleLabel:SetTall(18)
	scaleLabel:DockMargin(0, 10, 0, 0)
	scaleLabel:SetText("Card Scale (1.0 = current default size)")
	scaleLabel:SetTextColor(PDCity.THEME.TextDim)

	local scaleSlider = vgui.Create("DNumSlider", form)
	scaleSlider:Dock(TOP)
	scaleSlider:SetTall(28)
	scaleSlider:SetText("")
	scaleSlider:SetMin(0.6)
	scaleSlider:SetMax(1.8)
	scaleSlider:SetDecimals(2)

	SectionLabel("Card Size (% of normal - extra height goes to the portrait)")
	local widthSlider = Slider("Width", PDCity.HUD_WIDTH_MIN, PDCity.HUD_WIDTH_MAX)
	local heightSlider = Slider("Height", PDCity.HUD_HEIGHT_MIN, PDCity.HUD_HEIGHT_MAX)

	--[[-------------------------------------------------------
		Appearance - title, font, opacity, text sizes
	---------------------------------------------------------]]
	SectionLabel("Card Title (blank = your server name)")

	local titleEntry = vgui.Create("DTextEntry", form)
	titleEntry:Dock(TOP)
	titleEntry:SetTall(26)
	titleEntry:DockMargin(0, 4, 0, 0)
	titleEntry:SetPlaceholderText(PDCity.BRAND_NAME)

	SectionLabel("Font")

	local SITE_FONT_LABEL = "Same as Site Theme"
	local fontCombo = vgui.Create("DComboBox", form)
	fontCombo:Dock(TOP)
	fontCombo:SetTall(26)
	fontCombo:DockMargin(0, 4, 0, 0)
	fontCombo:SetSortItems(false) -- keep "Same as Site Theme" first
	fontCombo:AddChoice(SITE_FONT_LABEL, "")
	for _, family in ipairs(PDCity.FONT_CHOICES) do
		fontCombo:AddChoice(family, family)
	end

	local function SelectFont(family)
		if family == "" or not table.HasValue(PDCity.FONT_CHOICES, family) then
			fontCombo:ChooseOptionID(1)
			return
		end
		for i, choice in ipairs(PDCity.FONT_CHOICES) do
			if choice == family then fontCombo:ChooseOptionID(i + 1) return end
		end
	end

	SectionLabel("Opacity (%)")
	local cardOpacitySlider = Slider("Card background", 0, 100)
	local chipOpacitySlider = Slider("Inner boxes & bar tracks", 0, 100)

	SectionLabel("Text Sizes (pixels at Card Scale 1.0)")
	local textSizeSliders = {}
	for _, element in ipairs(PDCity.HUD_TEXT_ELEMENTS) do
		textSizeSliders[element.Key] = Slider(element.Label, PDCity.HUD_TEXT_SIZE_MIN, PDCity.HUD_TEXT_SIZE_MAX)
	end

	--[[-------------------------------------------------------
		Colours - health/armor low (empty) and high (full) shades, the
		same pair StatusBar (cl_hud_card.lua) Lerps between live.
	---------------------------------------------------------]]
	local function ColorRow(labelText)
		local rowLabel = vgui.Create("DLabel", form)
		rowLabel:Dock(TOP)
		rowLabel:SetTall(18)
		rowLabel:DockMargin(0, 14, 0, 0)
		rowLabel:SetText(labelText)
		rowLabel:SetTextColor(PDCity.THEME.TextDim)

		local row = vgui.Create("DPanel", form)
		row:Dock(TOP)
		row:SetTall(150)
		row:DockMargin(0, 4, 0, 0)
		row.Paint = function() end

		local lowHolder = vgui.Create("DPanel", row)
		lowHolder:Dock(LEFT)
		lowHolder:SetWide(170)
		lowHolder.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Background) end

		local lowSubLabel = vgui.Create("DLabel", lowHolder)
		lowSubLabel:Dock(TOP)
		lowSubLabel:SetTall(18)
		lowSubLabel:SetText("  Empty")
		lowSubLabel:SetTextColor(PDCity.THEME.TextDim)

		local lowMixer = vgui.Create("DColorMixer", lowHolder)
		lowMixer:Dock(FILL)
		lowMixer:SetPalette(false)
		lowMixer:SetAlphaBar(false)
		lowMixer:SetWangs(false)

		local highHolder = vgui.Create("DPanel", row)
		highHolder:Dock(FILL)
		highHolder:DockMargin(8, 0, 0, 0)
		highHolder.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Background) end

		local highSubLabel = vgui.Create("DLabel", highHolder)
		highSubLabel:Dock(TOP)
		highSubLabel:SetTall(18)
		highSubLabel:SetText("  Full")
		highSubLabel:SetTextColor(PDCity.THEME.TextDim)

		local highMixer = vgui.Create("DColorMixer", highHolder)
		highMixer:Dock(FILL)
		highMixer:SetPalette(false)
		highMixer:SetAlphaBar(false)
		highMixer:SetWangs(false)

		return lowMixer, highMixer
	end

	local healthLowMixer, healthHighMixer = ColorRow("Health Bar Colour")
	local armorLowMixer, armorHighMixer = ColorRow("Armor Bar Colour")

	--[[-------------------------------------------------------
		Icons - blank means "use the built-in hand-drawn cross/shield"
		(cl_hud_card.lua), same "empty = default" convention as every
		other optional Icon field in this gamemode (Jobs, F4 Entities).
	---------------------------------------------------------]]
	local function IconRow(labelText, placeholder)
		local rowLabel = vgui.Create("DLabel", form)
		rowLabel:Dock(TOP)
		rowLabel:SetTall(18)
		rowLabel:DockMargin(0, 14, 0, 0)
		rowLabel:SetText(labelText)
		rowLabel:SetTextColor(PDCity.THEME.TextDim)

		local row = vgui.Create("DPanel", form)
		row:Dock(TOP)
		row:SetTall(26)
		row:DockMargin(0, 4, 0, 0)
		row.Paint = function() end

		local entry = vgui.Create("DTextEntry", row)
		entry:Dock(FILL)
		entry:SetPlaceholderText(placeholder)

		local pickBtn = vgui.Create("DButton", row)
		pickBtn:Dock(RIGHT)
		pickBtn:SetWide(28)
		pickBtn:DockMargin(4, 0, 0, 0)
		pickBtn:SetText("")
		pickBtn.Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(Material("icon16/picture.png"))
			surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
		end
		pickBtn.DoClick = function()
			PDCity.OpenIconPicker(function(path) entry:SetValue(path) end)
		end

		local clearBtn = vgui.Create("DButton", row)
		clearBtn:Dock(RIGHT)
		clearBtn:SetWide(60)
		clearBtn:DockMargin(4, 0, 0, 0)
		PDCity.StyleButton(clearBtn, "Default", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
		clearBtn.DoClick = function() entry:SetValue("") end

		return entry
	end

	local healthIconEntry = IconRow("Health Icon (blank = built-in cross)", "icon16/heart.png, or blank")
	local armorIconEntry = IconRow("Armor Icon (blank = built-in shield)", "icon16/shield.png, or blank")

	--[[-------------------------------------------------------
		Displayed currencies - Money always shows (it's not part of this
		list, core/sh_currencies.lua's system is ADDITIONAL currencies
		only) - these are which of the owner-defined extra ones also get
		a chip on the card.
	---------------------------------------------------------]]
	local currenciesLabel = vgui.Create("DLabel", form)
	currenciesLabel:Dock(TOP)
	currenciesLabel:SetTall(18)
	currenciesLabel:DockMargin(0, 14, 0, 0)
	currenciesLabel:SetText("Displayed Currencies (Money always shows)")
	currenciesLabel:SetTextColor(PDCity.THEME.TextDim)

	local currenciesHolder = vgui.Create("DPanel", form)
	currenciesHolder:Dock(TOP)
	currenciesHolder:SetTall(math.max(30, #PDCity.CURRENCIES * 24 + 8))
	currenciesHolder:DockMargin(0, 4, 0, 0)
	currenciesHolder.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Background) end

	local currencyChecks = {}
	if #PDCity.CURRENCIES == 0 then
		local empty = vgui.Create("DLabel", currenciesHolder)
		empty:Dock(TOP)
		empty:SetTall(30)
		empty:DockMargin(8, 0, 0, 0)
		empty:SetFont("PDCity_Small")
		empty:SetText("No currencies defined yet - see the Catalogue's \"Currencies\" tab.")
		empty:SetTextColor(PDCity.THEME.TextDim)
	else
		for _, currency in ipairs(PDCity.CURRENCIES) do
			local chk = vgui.Create("DCheckBoxLabel", currenciesHolder)
			chk:Dock(TOP)
			chk:DockMargin(8, 2, 0, 0)
			chk:SetText(currency.Name .. " (" .. currency.Symbol .. ")")
			chk:SetTextColor(PDCity.THEME.Text)
			currencyChecks[currency.ID] = chk
		end
	end

	--[[-------------------------------------------------------
		Load current values into every control above.
	---------------------------------------------------------]]
	local function LoadIntoForm()
		local s = CurrentOrDefault()

		scaleSlider:SetValue(s.Scale)
		widthSlider:SetValue(tonumber(s.Width) or 100)
		heightSlider:SetValue(tonumber(s.Height) or 100)
		healthLowMixer:SetColor(TableToColor(s.HealthLow, DEFAULTS.HealthLow))
		healthHighMixer:SetColor(TableToColor(s.HealthHigh, DEFAULTS.HealthHigh))
		armorLowMixer:SetColor(TableToColor(s.ArmorLow, DEFAULTS.ArmorLow))
		armorHighMixer:SetColor(TableToColor(s.ArmorHigh, DEFAULTS.ArmorHigh))
		healthIconEntry:SetValue(s.HealthIcon or "")
		armorIconEntry:SetValue(s.ArmorIcon or "")

		titleEntry:SetValue(s.Title or "")
		SelectFont(s.Font or "")
		cardOpacitySlider:SetValue(tonumber(s.CardOpacity) or 100)
		chipOpacitySlider:SetValue(tonumber(s.ChipOpacity) or 100)
		for _, element in ipairs(PDCity.HUD_TEXT_ELEMENTS) do
			textSizeSliders[element.Key]:SetValue(PDCity.GetHUDTextSize(s, element))
		end

		local wanted = {}
		for _, id in ipairs(s.DisplayedCurrencies) do wanted[id] = true end
		for id, chk in pairs(currencyChecks) do
			chk:SetChecked(wanted[id] == true)
		end
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
		local displayed = {}
		for id, chk in pairs(currencyChecks) do
			if chk:GetChecked() then table.insert(displayed, id) end
		end

		local textSizes = {}
		for key, slider in pairs(textSizeSliders) do
			textSizes[key] = math.Round(slider:GetValue())
		end

		local _, font = fontCombo:GetSelected()

		SendHUDSettings({
			Title = titleEntry:GetValue(),
			Font = font or "",
			CardOpacity = math.Round(cardOpacitySlider:GetValue()),
			ChipOpacity = math.Round(chipOpacitySlider:GetValue()),
			TextSizes = textSizes,
			Scale = scaleSlider:GetValue(),
			Width = math.Round(widthSlider:GetValue()),
			Height = math.Round(heightSlider:GetValue()),
			HealthLow = ColorToTable(healthLowMixer:GetColor()),
			HealthHigh = ColorToTable(healthHighMixer:GetColor()),
			ArmorLow = ColorToTable(armorLowMixer:GetColor()),
			ArmorHigh = ColorToTable(armorHighMixer:GetColor()),
			HealthIcon = healthIconEntry:GetValue(),
			ArmorIcon = armorIconEntry:GetValue(),
			DisplayedCurrencies = displayed,
		})
	end

	local resetBtn = vgui.Create("DButton", btnRow)
	resetBtn:Dock(RIGHT)
	resetBtn:SetWide(140)
	resetBtn:DockMargin(8, 0, 0, 0)
	PDCity.StyleButton(resetBtn, "Reset to Defaults", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	resetBtn.DoClick = function()
		SendHUDSettings(DEFAULTS)
		timer.Simple(0.2, function() if IsValid(form) then LoadIntoForm() end end)
	end

	root.PDCityRefresh = LoadIntoForm

	return root

end
