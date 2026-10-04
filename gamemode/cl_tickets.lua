--[[---------------------------------------------------------
	Support ticket UI - opened by !report, !support, or !ticket
	(core/sv_tickets.lua, which relays them all to "pdcity_ticket_open").

	Everyone gets the "Submit" tab. Staff additionally get a "Tickets"
	tab listing everything anyone's submitted, with buttons to mark a
	ticket in progress or resolved - core/sv_tickets.lua does the actual
	status change and fires the hooks anything else (a future reward
	system) can build on; this only sends the request and redraws.
-----------------------------------------------------------]]

local STATUS_COLORS = {
	open = PDCity.THEME and PDCity.THEME.TextDim or Color(182, 182, 187),
	in_progress = Color(230, 165, 60),
	resolved = Color(90, 200, 120),
}

local STATUS_LABELS = {
	open = "OPEN",
	in_progress = "IN PROGRESS",
	resolved = "RESOLVED",
}

local function SendSetStatus(id, status)
	net.Start("pdcity_ticket_setstatus")
		net.WriteUInt(id, 32)
		net.WriteString(status)
	net.SendToServer()
end

--[[---------------------------------------------------------
	Submit tab
-----------------------------------------------------------]]
local function BuildSubmitTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root:DockPadding(4, 4, 4, 4)
	root.Paint = function() end

	local label = vgui.Create("DLabel", root)
	label:Dock(TOP)
	label:SetTall(36)
	label:SetFont("PDCity_Small")
	label:SetWrap(true)
	label:SetText("Describe your issue. This is sent to staff along with your SteamID - you'll be told in chat when it's picked up.")
	label:SetTextColor(PDCity.THEME.TextDim)

	local entry = vgui.Create("DTextEntry", root)
	entry:Dock(TOP)
	entry:SetTall(140)
	entry:DockMargin(0, 8, 0, 4)
	entry:SetMultiline(true)
	entry:SetMaximumCharCount(512)
	entry:SetPlaceholderText("What's going on?")

	local counter = vgui.Create("DLabel", root)
	counter:Dock(TOP)
	counter:SetTall(18)
	counter:SetFont("PDCity_Small")
	counter:SetContentAlignment(6)
	counter:SetTextColor(PDCity.THEME.TextDim)

	local function UpdateCounter()
		counter:SetText(#(entry:GetValue() or "") .. " / 512")
	end
	entry.OnValueChange = UpdateCounter
	UpdateCounter()

	local submitBtn = vgui.Create("DButton", root)
	submitBtn:Dock(TOP)
	submitBtn:SetTall(32)
	submitBtn:DockMargin(0, 8, 0, 0)
	PDCity.StyleButton(submitBtn, "SUBMIT TICKET")
	submitBtn.DoClick = function()
		local msg = string.Trim(entry:GetValue() or "")
		if msg == "" then
			entry:SetPlaceholderText("Type something first...")
			entry:RequestFocus()
			return
		end

		net.Start("pdcity_ticket_submit")
			net.WriteString(msg)
		net.SendToServer()

		entry:SetValue("")
		UpdateCounter()
		LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Ticket sent.")
	end

	entry:RequestFocus()

	return root

end

--[[---------------------------------------------------------
	Tickets tab - staff only
-----------------------------------------------------------]]
local function BuildTicketsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	PDCity.ApplyFastScroll(scroll)

	local list = vgui.Create("DIconLayout", scroll)
	list:Dock(TOP)
	list:SetSpaceY(8)

	local function BuildTicketCard(ticket)
		local card = vgui.Create("DPanel", list)
		card:SetWide(list:GetWide() - 4)
		card:SetTall(120)
		card:DockMargin(0, 0, 0, 0)
		card.Paint = function(self, w, h)
			draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
			surface.SetDrawColor(STATUS_COLORS[ticket.Status] or PDCity.THEME.Border)
			surface.DrawRect(0, 0, 4, h)
		end

		local header = vgui.Create("DLabel", card)
		header:SetPos(14, 8)
		header:SetSize(card:GetWide() - 160, 20)
		header:SetFont("PDCity_Heading")
		header:SetText("#" .. ticket.ID .. "  " .. (ticket.Name or "?"))
		header:SetTextColor(PDCity.THEME.Text)

		local sub = vgui.Create("DLabel", card)
		sub:SetPos(14, 28)
		sub:SetSize(card:GetWide() - 160, 16)
		sub:SetFont("PDCity_Small")
		sub:SetText((ticket.SteamID or "") .. "  -  " .. os.date("%Y-%m-%d %H:%M", ticket.CreatedAt or 0))
		sub:SetTextColor(PDCity.THEME.TextDim)

		local badge = vgui.Create("DLabel", card)
		badge:SetPos(card:GetWide() - 140, 10)
		badge:SetSize(126, 20)
		badge:SetFont("PDCity_Small")
		badge:SetContentAlignment(6)
		badge:SetText(STATUS_LABELS[ticket.Status] or ticket.Status)
		badge:SetTextColor(STATUS_COLORS[ticket.Status] or PDCity.THEME.TextDim)

		local msg = vgui.Create("DLabel", card)
		msg:SetPos(14, 48)
		msg:SetSize(card:GetWide() - 28, 44)
		msg:SetFont("PDCity_Small")
		msg:SetWrap(true)
		msg:SetText(ticket.Message or "")
		msg:SetTextColor(PDCity.THEME.Text)

		local function ActionButton(x, text, status)
			local btn = vgui.Create("DButton", card)
			btn:SetPos(x, card:GetTall() - 26)
			btn:SetSize(110, 20)
			local isCurrent = ticket.Status == status
			PDCity.StyleButton(btn, text, isCurrent and { Accent = PDCity.THEME.Border, AccentDim = PDCity.THEME.Border } or nil)
			btn:SetEnabled(not isCurrent)
			btn.DoClick = function() SendSetStatus(ticket.ID, status) end
		end

		ActionButton(14, "IN PROGRESS", "in_progress")
		ActionButton(130, "RESOLVED", "resolved")
		ActionButton(246, "REOPEN", "open")

		return card
	end

	local function Refresh()
		net.Start("pdcity_ticket_list")
		net.SendToServer()
	end

	root.PDCityTickets = {}

	root.PDCityApplyListing = function(tickets)
		root.PDCityTickets = tickets or {}

		list:Clear()

		-- Newest first, but open/in-progress ahead of resolved regardless
		-- of age - a staff member opening this tab wants unresolved work
		-- at the top, not buried under old closed tickets.
		local sorted = {}
		for _, t in ipairs(root.PDCityTickets) do sorted[#sorted + 1] = t end
		table.sort(sorted, function(a, b)
			local aOpen = a.Status ~= "resolved"
			local bOpen = b.Status ~= "resolved"
			if aOpen ~= bOpen then return aOpen end
			return (a.CreatedAt or 0) > (b.CreatedAt or 0)
		end)

		for _, ticket in ipairs(sorted) do
			BuildTicketCard(ticket)
		end

		if #sorted == 0 then
			local empty = vgui.Create("DLabel", list)
			empty:SetWide(list:GetWide() - 4)
			empty:SetTall(30)
			empty:SetFont("PDCity_Small")
			empty:SetText("No tickets yet.")
			empty:SetTextColor(PDCity.THEME.TextDim)
		end
	end

	root.PDCityRefresh = Refresh
	Refresh()

	return root

end

--[[---------------------------------------------------------
	Frame - simple two-button tab switcher (not the full sidebar F1/F4
	use, this only ever has one or two tabs).
-----------------------------------------------------------]]

local function OpenPDCityTickets()

	if IsValid(GAMEMODE.PDCityTicketFrame) then
		GAMEMODE.PDCityTicketFrame:Remove()
		return
	end

	local isStaff = PDCity.IsStaff(LocalPlayer())

	PDCity.PushMenuDim()

	local frameW, frameH = PDCity.ResponsiveFrameSize(680, 620)
	local frame = PDCity.CreateModernFrame("Support Tickets", frameW, frameH, function(newW, newH)
		if IsValid(frame.PDCityContent) then
			frame.PDCityContent:SetSize(newW - 20, newH - 90)
		end
	end)
	GAMEMODE.PDCityTicketFrame = frame
	frame.OnRemove = function() PDCity.PopMenuDim() end

	local tabBar = vgui.Create("DPanel", frame)
	tabBar:SetPos(10, 52)
	tabBar:SetSize(frame:GetWide() - 20, 30)
	tabBar.Paint = function() end

	local content = vgui.Create("DPanel", frame)
	content:SetPos(10, 90)
	content:SetSize(frame:GetWide() - 20, frame:GetTall() - 100)
	content.Paint = function() end
	frame.PDCityContent = content

	local panels = {}
	local buttons = {}

	local function SelectTab(index)
		for i, btn in ipairs(buttons) do
			btn.Active = (i == index)
		end
		for i, panel in ipairs(panels) do
			panel:SetVisible(i == index)
			if i == index and panel.PDCityRefresh then panel.PDCityRefresh() end
		end
	end

	local function AddTab(label, buildFn)
		local index = #panels + 1

		local panel = buildFn(content)
		panel:SetPos(0, 0)
		panel:SetSize(content:GetWide(), content:GetTall())
		panel:SetVisible(false)
		panels[index] = panel

		local btn = vgui.Create("DButton", tabBar)
		btn:SetPos((index - 1) * 120, 0)
		btn:SetSize(114, 28)
		btn:SetText("")
		btn.Active = false
		btn.Paint = function(self, w, h)
			draw.RoundedBox(5, 0, 0, w, h, self.Active and PDCity.THEME.Accent or (self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel))
			draw.SimpleText(label, "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		btn.DoClick = function() SelectTab(index) end
		buttons[index] = btn

		return index
	end

	AddTab("Submit", BuildSubmitTab)
	if isStaff then
		AddTab("Tickets", BuildTicketsTab)
	end

	SelectTab(1)

	-- Live refresh while the Tickets tab is open - a new ticket coming in,
	-- or another staff member changing a status, shouldn't need a
	-- close/reopen to see.
	if isStaff then
		timer.Create("pdcity_TicketFrameRefresh", 5, 0, function()
			if not IsValid(frame) then
				timer.Remove("pdcity_TicketFrameRefresh")
				return
			end
			local panel = panels[2]
			if IsValid(panel) and panel:IsVisible() and panel.PDCityRefresh then
				panel.PDCityRefresh()
			end
		end)
		frame.OnRemove = function()
			PDCity.PopMenuDim()
			timer.Remove("pdcity_TicketFrameRefresh")
		end
	end

end

net.Receive("pdcity_ticket_open", function()
	OpenPDCityTickets()
end)

net.Receive("pdcity_ticket_listing", function()
	local tickets = util.JSONToTable(net.ReadString() or "[]") or {}

	if IsValid(GAMEMODE.PDCityTicketFrame) then
		local content = GAMEMODE.PDCityTicketFrame.PDCityContent
		if IsValid(content) then
			for _, panel in ipairs(content:GetChildren()) do
				if panel.PDCityApplyListing then
					panel.PDCityApplyListing(tickets)
				end
			end
		end
	end
end)

net.Receive("pdcity_ticket_alert", function()
	if IsValid(GAMEMODE.PDCityTicketFrame) then
		net.Start("pdcity_ticket_list")
		net.SendToServer()
	end
end)

concommand.Add("pdcity_tickets", OpenPDCityTickets)
