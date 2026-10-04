--[[---------------------------------------------------------
	Client side of Custom Currencies (core/sh_currencies.lua): keeps
	PDCity.CURRENCIES (definitions - name/symbol/icon, same for everyone)
	and PDCity.MY_CURRENCY_BALANCES (just the local player's own amounts)
	up to date. The HUD card (cl_hud_card.lua) reads both to draw whichever
	currencies the HUD settings (core/sv_hud_settings.lua) say to show.
-----------------------------------------------------------]]

PDCity.MY_CURRENCY_BALANCES = PDCity.MY_CURRENCY_BALANCES or {}

net.Receive("pdcity_currency_sync", function()
	PDCity.CURRENCIES = util.JSONToTable(net.ReadString() or "[]") or {}
	hook.Run("PDCity_CurrencyCatalogueUpdated")
end)

--[[---------------------------------------------------------
	Picker popup - the Flowchart's "Give Currency"/"Charge Currency" nodes
	(cl_flow_editor.lua) use this instead of typing a raw currency ID,
	same "pick, don't type" idea as PDCity.OpenEntityClassPicker/
	PDCity.OpenInterfacePicker. Hands back the whole currency def (`onPick`
	receives it), not just the ID, so the caller can show its name/symbol
	without a second lookup.
-----------------------------------------------------------]]
function PDCity.OpenCurrencyPicker(onPick)

	local frame = PDCity.OpenPicker("Choose a Currency", 380, 420)

	local top = 48

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(16, top + 10)
	scroll:SetSize(348, frame:GetTall() - top - 26)
	PDCity.ApplyFastScroll(scroll)

	if #PDCity.CURRENCIES == 0 then
		local empty = vgui.Create("DLabel", scroll)
		empty:Dock(TOP)
		empty:SetTall(40)
		empty:SetFont("PDCity_Small")
		empty:SetWrap(true)
		empty:SetText("No currencies defined yet - add one from the F4 Catalogue Admin's \"Currencies\" tab first.")
		empty:SetTextColor(PDCity.THEME.TextDim)
	end

	for _, currency in ipairs(PDCity.CURRENCIES) do
		local btn = vgui.Create("DButton", scroll)
		btn:Dock(TOP)
		btn:SetTall(32)
		btn:DockMargin(0, 0, 0, 6)
		PDCity.StyleButton(btn, currency.Name .. " (" .. currency.Symbol .. ")", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.Text })
		btn.DoClick = function()
			onPick(currency)
			frame:Close()
		end
	end

end

net.Receive("pdcity_currency_balance_sync", function()
	local raw = util.JSONToTable(net.ReadString() or "{}") or {}

	-- JSON object keys are always strings - fixed back to numbers the same
	-- way core/sv_currencies.lua's own GetBalances does server-side, so
	-- callers can index this by the currency's real numeric ID.
	local fixed = {}
	for key, amount in pairs(raw) do
		local id = tonumber(key)
		if id then fixed[id] = amount end
	end
	PDCity.MY_CURRENCY_BALANCES = fixed
end)
