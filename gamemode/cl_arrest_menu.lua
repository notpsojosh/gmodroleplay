--[[---------------------------------------------------------
	Officer-side arrest menu, opened by the server (core/sv_arrests.lua)
	the moment a cuff attempt succeeds. Submit is disabled until both a
	law and a duration are picked; closing the window without submitting
	tells the server to uncuff the target (see PDCity_CancelArrest).

	The duration dropdown depends on which law is selected - each law
	(core/sh_laws.lua) has its own valid range - so it stays disabled
	until a law is picked, then repopulates with just that law's range.
	Displayed as "years" rather than "minutes" (pure RP flavour - 1 year
	= 1 real minute, the server-side math is unchanged), see sh_laws.lua.

	Built on PDCity.CreateModernFrame (cl_theme.lua) - a Derma DFrame for
	its dragging/focus/input plumbing, but with every pixel hand-painted
	rather than any stock Derma skin, same as every other menu in this
	gamemode. A DHTML/CSS/JS version of this exact menu was tried as a
	proof of concept and reverted - it worked, but cost native window
	dragging and fought the native 3D portrait for z-order on every
	click, for no real gain over this approach.
-----------------------------------------------------------]]

local function SendCancel()
	net.Start("PDCity_CancelArrest")
	net.SendToServer()
end

net.Receive("PDCity_OpenArrestMenu", function()

	local target = net.ReadEntity()
	if not IsValid(target) then return end

	if IsValid(GAMEMODE.PDCityArrestFrame) then
		GAMEMODE.PDCityArrestFrame.pdcity_Submitted = true -- replacing it isn't "closing without submitting"
		GAMEMODE.PDCityArrestFrame:Remove()
	end

	-- 560 x 360 is PDCity.CreateModernFrame's minimum size. Everything
	-- below is docked rather than placed at fixed positions, so it fills
	-- the frame whatever size it ends up.
	local frame = PDCity.CreateModernFrame("Arrest: " .. PDCity.GetDisplayName(target), 560, 360)
	frame:DockPadding(20, 62, 20, 20)
	GAMEMODE.PDCityArrestFrame = frame

	frame.OnRemove = function(self)
		if not self.pdcity_Submitted then SendCancel() end
	end

	-- Created first: a BOTTOM dock must come before the FILL one.
	local submitBtn = vgui.Create("DButton", frame)
	submitBtn:Dock(BOTTOM)
	submitBtn:SetTall(40)
	submitBtn:DockMargin(0, 16, 0, 0)

	local body = vgui.Create("DPanel", frame)
	body:Dock(FILL)
	body.Paint = function() end

	-- Portrait - the target's actual current model, same framing helper
	-- the F4/Staff menus use.
	local portraitHolder = vgui.Create("DPanel", body)
	portraitHolder:Dock(LEFT)
	portraitHolder:SetWide(160)
	portraitHolder.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
	end
	PDCity.BuildPortrait(portraitHolder, target:GetModel())

	local column = vgui.Create("DPanel", body)
	column:Dock(FILL)
	column:DockMargin(20, 0, 0, 0)
	column.Paint = function() end

	local function FieldLabel(text, topMargin)
		local label = vgui.Create("DLabel", column)
		label:Dock(TOP)
		label:SetTall(22)
		label:DockMargin(0, topMargin, 0, 4)
		label:SetFont("PDCity_Body")
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.Text)
		return label
	end

	FieldLabel("Law broken", 0)

	local lawCombo = vgui.Create("DComboBox", column)
	lawCombo:Dock(TOP)
	lawCombo:SetTall(30)
	lawCombo:SetValue("Select a law...")
	lawCombo:SetSortItems(false) -- DComboBox defaults to sorting choices by label text; keep the owner's own order
	for i, law in ipairs(PDCity.LAWS) do
		lawCombo:AddChoice(law.Name, i)
	end

	-- No laws ship by default - the owner adds them in F1 > Site Admin.
	if #PDCity.LAWS == 0 then
		lawCombo:SetValue("No laws set up yet - ask the server owner")
		lawCombo:SetEnabled(false)
	end

	FieldLabel("Sentence", 16)

	local durationCombo = vgui.Create("DComboBox", column)
	durationCombo:Dock(TOP)
	durationCombo:SetTall(30)
	durationCombo:SetValue("Select a law first...")
	durationCombo:SetSortItems(false) -- otherwise it sorts "1","10","2"... as strings, not numbers
	durationCombo:SetEnabled(false)

	-- What the officer is about to submit, and what they'll be paid for it.
	local summary = vgui.Create("DLabel", column)
	summary:Dock(FILL)
	summary:DockMargin(0, 16, 0, 0)
	summary:SetFont("PDCity_Small")
	summary:SetWrap(true)
	summary:SetContentAlignment(7)
	summary:SetTextColor(PDCity.THEME.TextDim)

	local selectedLaw, selectedDuration

	local function UpdateSubmit()
		submitBtn:SetEnabled(selectedLaw ~= nil and selectedDuration ~= nil)

		local law = selectedLaw and PDCity.LAWS[selectedLaw]
		if #PDCity.LAWS == 0 then
			summary:SetText("The server owner hasn't added any laws yet, so this arrest can't be processed. Closing this window releases the suspect.")
		elseif law and selectedDuration then
			summary:SetText(PDCity.GetDisplayName(target) .. " will be jailed for " .. selectedDuration .. " year"
				.. (selectedDuration > 1 and "s" or "") .. " for " .. law.Name .. ". You'll be paid $"
				.. string.Comma(selectedDuration * PDCity.LAW_REWARDS.PayPerMinute) .. ".")
		elseif law then
			summary:SetText(law.Name .. " carries " .. law.MinMinutes .. " to " .. law.MaxMinutes .. " years. Pick a sentence.")
		else
			summary:SetText("Pick the law broken, then the sentence. Closing this window without submitting releases the suspect.")
		end
	end

	lawCombo.OnSelect = function(self, index, value, data)
		selectedLaw = data
		selectedDuration = nil

		local law = PDCity.LAWS[selectedLaw]

		durationCombo:Clear()
		for years = law.MinMinutes, law.MaxMinutes do
			durationCombo:AddChoice(years .. " year" .. (years > 1 and "s" or "") .. " ($" .. (years * PDCity.LAW_REWARDS.PayPerMinute) .. ")", years)
		end
		durationCombo:SetValue("Select duration...")
		durationCombo:SetEnabled(true)

		UpdateSubmit()
	end

	durationCombo.OnSelect = function(self, index, value, data)
		selectedDuration = data
		UpdateSubmit()
	end

	submitBtn:SetText("")
	submitBtn:SetEnabled(false)
	UpdateSubmit()
	submitBtn.Paint = function(self, w, h)
		local enabled = self:IsEnabled()
		local col = PDCity.THEME.Border
		if enabled then
			col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
		end
		draw.RoundedBox(5, 0, 0, w, h, col)
		local label = enabled and "SUBMIT ARREST" or "SELECT LAW AND DURATION"
		draw.SimpleText(label, "PDCity_Body", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	submitBtn.DoClick = function()
		if not selectedLaw or not selectedDuration then return end

		frame.pdcity_Submitted = true

		net.Start("PDCity_SubmitArrest")
		net.WriteEntity(target)
		net.WriteUInt(selectedLaw, 8)
		net.WriteUInt(selectedDuration, 8)
		net.SendToServer()

		frame:Close()
	end

end)
