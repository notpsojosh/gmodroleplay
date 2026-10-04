--[[---------------------------------------------------------
	Staff Menu - owner/superadmin only. Every connected player listed as
	a row card (same wide-short-row layout as the F4 menu's job/entity
	cards, cl_f4_menu.lua/cl_theme.lua) - click one to slide out a detail
	panel with ban/gag/mute/jail actions and, for the owner only, a staff
	role dropdown.

	Every action here is re-checked server-side (core/sv_staff_menu.lua) -
	this file only builds the UI and sends the request; the gate below is
	just so a non-eligible player doesn't even see an empty shell.

	Every action pops out its own reason prompt (PromptReason below)
	rather than reading from one persistent box sitting in the menu the
	whole time - harder to leave blank/stale, and it's re-required fresh
	for each action rather than trusting whatever was typed earlier.

	Opened with the "staffmenu" keybind (core/sh_keybinds.lua) via the
	"pdcity_staffmenu" concommand, same ConCommand-relay pattern as F1/F4
	(gm_showspare2/gm_showhelp -> GM:ShowSpare2/ShowHelp -> ply:ConCommand).
-----------------------------------------------------------]]

local ROW_WIDE, ROW_TALL, PORTRAIT_SIZE = 300, 68, 52

local function SendStaffAction(action, target, extra, reason)
	net.Start("pdcity_staff_action")
		net.WriteString(action)
		net.WriteEntity(target)
		net.WriteString(extra or "")
		net.WriteString(reason or "")
	net.SendToServer()
end

--[[---------------------------------------------------------
	Reason prompt - a small popup with its own text entry, rather than one
	persistent box sitting in the menu the whole time (easy to leave
	blank/stale, or type once and forget is even there). Pops out fresh
	for whichever action was just clicked; Confirm is a no-op (just
	re-focuses the entry) until something's actually typed, so an action
	can't go through with an empty reason.
-----------------------------------------------------------]]
local function PromptReason(promptText, onConfirm)

	local pw, ph = 380, 156

	local popup = vgui.Create("DFrame")
	popup:SetSize(pw, ph)
	popup:Center()
	popup:SetTitle("")
	popup:ShowCloseButton(false)
	popup:MakePopup()
	popup:SetAlpha(0)
	popup:AlphaTo(255, 0.12, 0)
	popup.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Background)
		draw.RoundedBoxEx(8, 0, 0, w, 36, PDCity.THEME.TitleBar, true, true, false, false)
		draw.SimpleText("Reason Required", "PDCity_Heading", 14, 18, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local closeBtn = vgui.Create("DLabel", popup)
	closeBtn:SetPos(pw - 28, 9)
	closeBtn:SetSize(18, 18)
	closeBtn:SetFont("PDCity_Heading")
	closeBtn:SetText("x")
	closeBtn:SetTextColor(PDCity.THEME.TextDim)
	closeBtn:SetContentAlignment(5)
	closeBtn:SetCursor("hand")
	closeBtn:SetMouseInputEnabled(true)
	closeBtn.OnMousePressed = function(self, mcode)
		if mcode == MOUSE_LEFT then popup:Close() end
	end

	local promptLabel = vgui.Create("DLabel", popup)
	promptLabel:SetPos(14, 44)
	promptLabel:SetSize(pw - 28, 36)
	promptLabel:SetFont("PDCity_Small")
	promptLabel:SetWrap(true)
	promptLabel:SetText(promptText)
	promptLabel:SetTextColor(PDCity.THEME.TextDim)

	local entry = vgui.Create("DTextEntry", popup)
	entry:SetPos(14, 84)
	entry:SetSize(pw - 28, 28)
	entry:SetPlaceholderText("Reason...")

	local confirmBtn = vgui.Create("DButton", popup)
	confirmBtn:SetPos(14, 120)
	confirmBtn:SetSize(pw - 28, 26)
	confirmBtn:SetText("")
	confirmBtn.Paint = function(self, w, h)
		draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim)
		draw.SimpleText("CONFIRM", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local function TrySubmit()
		local reason = string.Trim(entry:GetValue() or "")
		if reason == "" then
			entry:SetPlaceholderText("Reason required - type something first")
			entry:RequestFocus()
			return
		end
		popup:Close()
		onConfirm(reason)
	end

	confirmBtn.DoClick = TrySubmit
	entry.OnEnter = TrySubmit

	entry:RequestFocus()

end

--[[---------------------------------------------------------
	Player row card
-----------------------------------------------------------]]

local function BuildPlayerRow(grid, target, ShowDetail)

	local card = vgui.Create("PDCityJobCard", grid)
	card:SetSize(ROW_WIDE, ROW_TALL)
	card:SetMouseInputEnabled(true)
	card.JobColor = PDCity.THEME.Accent

	local portraitHolder = vgui.Create("DPanel", card)
	portraitHolder:Dock(LEFT)
	portraitHolder:SetWide(PORTRAIT_SIZE)
	portraitHolder:SetTall(ROW_TALL - 16)
	portraitHolder:DockMargin(8, 8, 0, 8)
	portraitHolder.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.TitleBar)
	end
	PDCity.BuildPortrait(portraitHolder, target:GetModel())

	-- Status badge: jailed beats muted/gagged as the headline state (the
	-- one that actually stops them playing at all), which can still be
	-- true alongside a mute/gag - the detail panel shows all three states
	-- individually regardless of which one wins the badge here.
	local badgeText, badgeColor
	if target:GetNWBool("PDCity_IsJailed", false) then
		badgeText, badgeColor = "JAILED", Color(230, 120, 100)
	elseif target:GetNWBool("PDCity_Muted", false) or target:GetNWBool("PDCity_Gagged", false) then
		badgeText, badgeColor = "RESTRICTED", PDCity.THEME.TextDim
	end

	if badgeText then
		local badge = vgui.Create("DLabel", card)
		badge:Dock(RIGHT)
		badge:SetWide(80)
		badge:DockMargin(0, 8, 10, 8)
		badge:SetFont("PDCity_Small")
		badge:SetText(badgeText)
		badge:SetTextColor(badgeColor)
		badge:SetContentAlignment(6)
		badge:SetMouseInputEnabled(false)
	end

	local textHolder = vgui.Create("DPanel", card)
	textHolder:Dock(FILL)
	textHolder:DockMargin(10, 8, 8, 8)
	textHolder.Paint = function() end
	textHolder:SetMouseInputEnabled(false)

	local nameLabel = vgui.Create("DLabel", textHolder)
	nameLabel:Dock(TOP)
	nameLabel:SetTall(20)
	nameLabel:SetFont("PDCity_Heading")
	nameLabel:SetText(PDCity.GetDisplayName(target))
	nameLabel:SetTextColor(PDCity.THEME.Text)
	nameLabel:SetMouseInputEnabled(false)

	local job = PDCity.GetJob(target:Team())
	local subLabel = vgui.Create("DLabel", textHolder)
	subLabel:Dock(TOP)
	subLabel:SetFont("PDCity_Small")
	subLabel:SetText((job and job.Name or "Unknown job") .. "  -  " .. target:GetUserGroup())
	subLabel:SetTextColor(PDCity.THEME.TextDim)
	subLabel:SetMouseInputEnabled(false)

	card:SetCursor("hand")
	card.DoClick = function() ShowDetail(target) end

end

--[[---------------------------------------------------------
	Frame
-----------------------------------------------------------]]

local function OpenPDCityStaffMenu()

	if not PDCity.IsSuperAdminPlus(LocalPlayer()) then return end

	if IsValid(GAMEMODE.PDCityStaffFrame) then
		GAMEMODE.PDCityStaffFrame:Remove()
		return
	end

	local DETAIL_WIDE = 260
	local DETAIL_MARGIN = 18
	local TOP_Y = 48
	local content, grid, detail

	PDCity.PushMenuDim()

	local frameW, frameH = PDCity.ResponsiveFrameSize(1100, 850)
	local frame = PDCity.CreateModernFrame("Staff Menu", frameW, frameH, function(newW, newH)
		if IsValid(content) then content:SetSize(newW, newH - 48) end

		if IsValid(detail) then
			detail:SetTall(newH - TOP_Y - DETAIL_MARGIN * 2)
			detail.TargetX = detail.IsOpen and (newW - DETAIL_WIDE - DETAIL_MARGIN) or newW
			detail.CurX = detail.TargetX
			detail:SetPos(detail.CurX, TOP_Y + DETAIL_MARGIN)
		end
	end)
	GAMEMODE.PDCityStaffFrame = frame

	frame.OnRemove = function()
		PDCity.PopMenuDim()
		timer.Remove("pdcity_StaffMenuRefresh")
	end

	-- Closing via the same key that opened this: F1/F4 get this for free
	-- (native engine binds fire regardless of VGUI focus), but this menu
	-- is opened via our OWN keybind system (core/sh_keybinds.lua), which
	-- listens server-side for PlayerButtonDown - and GMod suppresses most
	-- game-button transmission from the client while ANY panel holds
	-- keyboard focus, which this frame does the moment it opens (MakePopup,
	-- inside PDCity.CreateModernFrame). So the second press of "K" (or
	-- whatever it's bound to) never reaches that server hook at all while
	-- this is open - has to be caught client-side instead, against
	-- whatever key the player has THIS actually bound to right now
	-- (PDCity.MY_KEYBINDS, kept in sync by core/sv_keybinds.lua).
	frame.OnKeyCodePressed = function(self, keyCode)
		if PDCity.MY_KEYBINDS and keyCode == PDCity.MY_KEYBINDS["staffmenu"] then
			self:Remove()
		end
	end

	content = vgui.Create("DPanel", frame)
	content:SetPos(0, 48)
	content:SetSize(frame:GetWide(), frame:GetTall() - 48)
	content.Paint = function() end

	local scroll = vgui.Create("DScrollPanel", content)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 12, 16, 12)
	PDCity.ApplyFastScroll(scroll)

	grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:SetSpaceX(10)
	grid:SetSpaceY(10)

	--[[-----------------------------------------------------
		Detail slide-out - same structure as the F4 job detail panel
		(cl_f4_menu.lua), parented to the frame so it overlays regardless
		of scroll position, wider than that one to fit several action
		rows rather than one Become button. Wrapped in its own
		DScrollPanel so however many controls end up in it, it never
		overflows/clips - see cl_f4_admin.lua's forms for the same idea.
	-------------------------------------------------------]]
	detail = vgui.Create("DPanel", frame)
	detail:SetSize(DETAIL_WIDE, frame:GetTall() - TOP_Y - DETAIL_MARGIN * 2)
	detail.IsOpen = false
	detail.CurX = frame:GetWide()
	detail.TargetX = frame:GetWide()
	detail:SetPos(detail.CurX, TOP_Y + DETAIL_MARGIN)
	detail:SetMouseInputEnabled(false)
	detail.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(PDCity.THEME.TitleBar, 235))
	end
	detail.Think = function(self)
		if math.abs(self.CurX - self.TargetX) < 0.5 then
			self.CurX = self.TargetX
		else
			self.CurX = Lerp(FrameTime() * 9, self.CurX, self.TargetX)
		end
		self:SetPos(self.CurX, TOP_Y + DETAIL_MARGIN)
	end

	local function HideDetail()
		detail.IsOpen = false
		detail.TargetX = frame:GetWide()
		detail:SetMouseInputEnabled(false)
	end

	local ShowStaffDetail -- forward declared, refreshes itself on toggle actions

	ShowStaffDetail = function(target)
		if not IsValid(target) then HideDetail() return end

		detail:Clear()
		detail.IsOpen = true
		detail:SetMouseInputEnabled(true)
		detail.TargetX = frame:GetWide() - DETAIL_WIDE - DETAIL_MARGIN

		local closeBtn = vgui.Create("DLabel", detail)
		closeBtn:SetPos(DETAIL_WIDE - 26, 8)
		closeBtn:SetSize(18, 18)
		closeBtn:SetFont("PDCity_Heading")
		closeBtn:SetText("x")
		closeBtn:SetTextColor(PDCity.THEME.TextDim)
		closeBtn:SetContentAlignment(5)
		closeBtn:SetCursor("hand")
		closeBtn:SetMouseInputEnabled(true)
		closeBtn.OnMousePressed = function(self, mcode)
			if mcode == MOUSE_LEFT then HideDetail() end
		end

		local body = vgui.Create("DScrollPanel", detail)
		body:SetPos(10, 36)
		body:SetSize(DETAIL_WIDE - 20, detail:GetTall() - 46)

		local portraitHolder = vgui.Create("DPanel", body)
		portraitHolder:Dock(TOP)
		portraitHolder:SetTall(130)
		portraitHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end
		PDCity.BuildPortrait(portraitHolder, target:GetModel())

		local nameLabel = vgui.Create("DLabel", body)
		nameLabel:Dock(TOP)
		nameLabel:SetTall(24)
		nameLabel:DockMargin(0, 8, 0, 0)
		nameLabel:SetFont("PDCity_Heading")
		nameLabel:SetText(PDCity.GetDisplayName(target))
		nameLabel:SetTextColor(PDCity.THEME.Text)
		nameLabel:SetContentAlignment(5)

		local infoLabel = vgui.Create("DLabel", body)
		infoLabel:Dock(TOP)
		infoLabel:SetTall(18)
		infoLabel:SetFont("PDCity_Small")
		infoLabel:SetText(target:SteamID() .. "  -  " .. target:GetUserGroup())
		infoLabel:SetTextColor(PDCity.THEME.TextDim)
		infoLabel:SetContentAlignment(5)

		local function Divider()
			local d = vgui.Create("DPanel", body)
			d:Dock(TOP)
			d:SetTall(1)
			d:DockMargin(0, 10, 0, 6)
			d.Paint = function(self, w, h)
				surface.SetDrawColor(PDCity.THEME.Border)
				surface.DrawRect(0, 0, w, h)
			end
		end

		local function ActionButton(text, col, onClick)
			local btn = vgui.Create("DButton", body)
			btn:Dock(TOP)
			btn:SetTall(28)
			btn:DockMargin(0, 4, 0, 0)
			btn:SetText("")
			btn.Paint = function(self, w, h)
				draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and col or ColorAlpha(col, 210))
				draw.SimpleText(text, "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			btn.DoClick = onClick
			return btn
		end

		--[[-------------------------------------------------
			Ban
		---------------------------------------------------]]
		Divider()

		local banRow = vgui.Create("DPanel", body)
		banRow:Dock(TOP)
		banRow:SetTall(26)
		banRow.Paint = function() end

		local banDaysEntry = vgui.Create("DTextEntry", banRow)
		banDaysEntry:Dock(LEFT)
		banDaysEntry:SetWide(70)
		banDaysEntry:SetNumeric(true)
		banDaysEntry:SetPlaceholderText("Days")

		local banBtn = vgui.Create("DButton", banRow)
		banBtn:Dock(FILL)
		banBtn:DockMargin(6, 0, 0, 0)
		banBtn:SetText("")
		banBtn.Paint = function(self, w, h)
			draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and Color(210, 110, 60) or Color(180, 90, 50))
			draw.SimpleText("TEMP BAN", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		banBtn.DoClick = function()
			local days = tonumber(banDaysEntry:GetValue())
			if not days or days <= 0 then
				LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a number of days first.")
				return
			end
			PromptReason("Temp-ban " .. PDCity.GetDisplayName(target) .. " for " .. days .. " day(s) - why?",
				function(reason) SendStaffAction("ban", target, tostring(days), reason) end)
		end

		ActionButton("PERMANENT BAN", Color(190, 55, 55), function()
			PromptReason("Permanently ban " .. PDCity.GetDisplayName(target) .. " - why?",
				function(reason) SendStaffAction("permaban", target, nil, reason) end)
		end)

		--[[-------------------------------------------------
			Gag / Mute
		---------------------------------------------------]]
		Divider()

		local gagged = target:GetNWBool("PDCity_Gagged", false)
		ActionButton(gagged and "UNGAG (restore voice)" or "GAG (block voice)",
			gagged and PDCity.THEME.AccentDim or Color(160, 120, 40), function()
				PromptReason((gagged and "Ungag " or "Gag ") .. PDCity.GetDisplayName(target) .. " - why?", function(reason)
					SendStaffAction(gagged and "ungag" or "gag", target, nil, reason)
					ShowStaffDetail(target)
				end)
			end)

		local muted = target:GetNWBool("PDCity_Muted", false)
		ActionButton(muted and "UNMUTE (restore chat)" or "MUTE (block chat)",
			muted and PDCity.THEME.AccentDim or Color(160, 120, 40), function()
				PromptReason((muted and "Unmute " or "Mute ") .. PDCity.GetDisplayName(target) .. " - why?", function(reason)
					SendStaffAction(muted and "unmute" or "mute", target, nil, reason)
					ShowStaffDetail(target)
				end)
			end)

		--[[-------------------------------------------------
			Jail
		---------------------------------------------------]]
		Divider()

		local jailed = target:GetNWBool("PDCity_IsJailed", false)
		if jailed then
			ActionButton("RELEASE FROM JAIL", PDCity.THEME.AccentDim, function()
				PromptReason("Release " .. PDCity.GetDisplayName(target) .. " from staff jail - why?", function(reason)
					SendStaffAction("unjail", target, nil, reason)
					ShowStaffDetail(target)
				end)
			end)
		else
			local jailRow = vgui.Create("DPanel", body)
			jailRow:Dock(TOP)
			jailRow:SetTall(26)
			jailRow:DockMargin(0, 4, 0, 0)
			jailRow.Paint = function() end

			local jailMinEntry = vgui.Create("DTextEntry", jailRow)
			jailMinEntry:Dock(LEFT)
			jailMinEntry:SetWide(80)
			jailMinEntry:SetNumeric(true)
			jailMinEntry:SetPlaceholderText("Mins (0=indef.)")

			local jailBtn = vgui.Create("DButton", jailRow)
			jailBtn:Dock(FILL)
			jailBtn:DockMargin(6, 0, 0, 0)
			jailBtn:SetText("")
			jailBtn.Paint = function(self, w, h)
				draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim)
				draw.SimpleText("JAIL", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			jailBtn.DoClick = function()
				local mins = tonumber(jailMinEntry:GetValue()) or 0
				PromptReason("Jail " .. PDCity.GetDisplayName(target) .. " - why?", function(reason)
					SendStaffAction("jail", target, tostring(mins), reason)
					ShowStaffDetail(target)
				end)
			end
		end

		--[[-------------------------------------------------
			Staff role - owner only
		---------------------------------------------------]]
		-- Staff roles are stored by an admin mod; without ULX (the server
		-- reports it, core/sv_staff_menu.lua) there's nothing to save them to.
		if PDCity.IsOwner(LocalPlayer()) and not GetGlobalBool("PDCity_HasULX", false) then
			Divider()

			local noUlx = vgui.Create("DLabel", body)
			noUlx:Dock(TOP)
			noUlx:SetTall(32)
			noUlx:SetFont("PDCity_Small")
			noUlx:SetWrap(true)
			noUlx:SetText("Setting staff roles needs ULX installed. Without it, set user groups with your own admin mod or the server's settings/users.txt.")
			noUlx:SetTextColor(PDCity.THEME.TextDim)
		elseif PDCity.IsOwner(LocalPlayer()) then
			Divider()

			local rankLabel = vgui.Create("DLabel", body)
			rankLabel:Dock(TOP)
			rankLabel:SetTall(16)
			rankLabel:SetFont("PDCity_Small")
			rankLabel:SetText("Set staff role:")
			rankLabel:SetTextColor(PDCity.THEME.TextDim)

			local rankCombo = vgui.Create("DComboBox", body)
			rankCombo:Dock(TOP)
			rankCombo:SetTall(26)
			rankCombo:DockMargin(0, 4, 0, 0)
			for _, group in ipairs({ "user", "operator", "admin", "superadmin", "owner" }) do
				rankCombo:AddChoice(group)
			end

			ActionButton("SET ROLE", PDCity.THEME.Accent, function()
				-- GetSelected() returns (text, data) - AddChoice above never
				-- set a data value, so that second slot was always nil,
				-- which is why this rejected every pick with "please pick a
				-- role first" regardless. The text IS the group name here.
				local group = rankCombo:GetSelected()
				if not group or group == "" then
					LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Pick a role first.")
					return
				end
				PromptReason("Set " .. PDCity.GetDisplayName(target) .. "'s staff role to \"" .. group .. "\" - why?",
					function(reason) SendStaffAction("setrank", target, group, reason) end)
			end)
		end

	end

	local function RefreshGrid()
		grid:Clear()

		local players = player.GetAll()
		table.sort(players, function(a, b) return PDCity.GetDisplayName(a) < PDCity.GetDisplayName(b) end)

		for _, target in ipairs(players) do
			local ok, err = pcall(BuildPlayerRow, grid, target, ShowStaffDetail)
			if not ok then
				print("[" .. PDCity.BRAND_TAG .. "] ERROR building staff menu row for " .. tostring(target) .. ": " .. tostring(err))
			end
		end
	end
	RefreshGrid()

	-- Rebuilds the row list (and its badges) periodically while the menu
	-- is open, so a jail/mute/gag applied from another staff member's
	-- session, or a player joining/leaving, shows up without needing to
	-- close and reopen. The open row detail panel isn't touched by this -
	-- only the list behind it.
	timer.Create("pdcity_StaffMenuRefresh", 3, 0, function()
		if not IsValid(frame) then
			timer.Remove("pdcity_StaffMenuRefresh")
			return
		end
		RefreshGrid()
	end)

end

concommand.Add("pdcity_staffmenu", OpenPDCityStaffMenu)
