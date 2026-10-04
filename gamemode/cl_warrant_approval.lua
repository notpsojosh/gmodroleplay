--[[---------------------------------------------------------
	Warrant approval queue (core/sv_wanted.lua), for whoever qualifies as
	an approver (core/sv_warrant_perms.lua's PDCity.IsWarrantApprover -
	configurable via the F1 Site Admin panel, not fixed to one job/level
	anymore). Opened by the "warrants" keybind (core/sh_keybinds.lua) or
	the pdcity_warrants concommand, and refreshed automatically whenever
	the pending list changes anywhere - including live while already
	open, pushed by the server rather than only ever self-requested. That
	mirrors how the arrest menu (cl_arrest_menu.lua) is popped open by
	the server, not just something the officer opens themselves.

	A non-approver pressing the key/typing the concommand gets nothing
	here - PDCity.SendWarrantList (core/sv_wanted.lua) answers with a
	chat denial instead of ever sending this message.
-----------------------------------------------------------]]

local function BuildRow(parent, req)
	local row = vgui.Create("DPanel", parent)
	row:SetTall(90)
	row:Dock(TOP)
	row:DockMargin(0, 0, 0, 6)
	row.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Panel)
	end

	local info = vgui.Create("DLabel", row)
	info:SetPos(10, 8)
	info:SetFont("PDCity_Body")
	info:SetTextColor(PDCity.THEME.Text)
	info:SetText(req.Requester .. " -> " .. req.Target)
	info:SizeToContents()

	local reason = vgui.Create("DLabel", row)
	reason:SetPos(10, 28)
	reason:SetFont("PDCity_Small")
	reason:SetTextColor(PDCity.THEME.TextDim)
	reason:SetText("Reason: " .. req.Reason)
	reason:SetWrap(true)
	reason:SetAutoStretchVertical(true)

	local approveBtn = vgui.Create("DButton", row)
	approveBtn:SetText("")
	approveBtn:SetSize(70, 26)
	approveBtn:SetPos(10, 56)
	approveBtn.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim)
		draw.SimpleText("APPROVE", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	approveBtn.DoClick = function()
		net.Start("pdcity_warrant_decide")
			net.WriteUInt(req.ID, 32)
			net.WriteBool(true)
		net.SendToServer()
	end

	local denyBtn = vgui.Create("DButton", row)
	denyBtn:SetText("")
	denyBtn:SetSize(70, 26)
	denyBtn:SetPos(88, 56)
	denyBtn.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(200, 70, 60) or Color(140, 55, 50))
		draw.SimpleText("DENY", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	denyBtn.DoClick = function()
		net.Start("pdcity_warrant_decide")
			net.WriteUInt(req.ID, 32)
			net.WriteBool(false)
		net.SendToServer()
	end

	-- Deferred: row:GetWide() read immediately after Dock(TOP) is
	-- stale/unresolved until GMod's own layout pass runs (the same fix
	-- cl_f1_menu.lua's job-levels panel needed, and why).
	row.PerformLayout = function(self, w, h)
		reason:SetWide(w - 20)
	end
end

local function OpenOrRefresh(list)

	local frame = GAMEMODE.PDCityWarrantApprovalFrame

	if not IsValid(frame) then
		frame = PDCity.CreateModernFrame("Warrant Requests", 420, 420)
		GAMEMODE.PDCityWarrantApprovalFrame = frame

		local scroll = vgui.Create("DScrollPanel", frame)
		scroll:SetPos(10, 56)
		scroll:SetSize(400, 354)
		frame.pdcity_Scroll = scroll
	end

	local scroll = frame.pdcity_Scroll
	scroll:Clear()

	if #list == 0 then
		local empty = vgui.Create("DLabel", scroll)
		empty:SetText("No pending warrant requests.")
		empty:SetFont("PDCity_Body")
		empty:SetTextColor(PDCity.THEME.TextDim)
		empty:Dock(TOP)
		empty:DockMargin(0, 10, 0, 0)
	else
		for _, req in ipairs(list) do
			BuildRow(scroll, req)
		end
	end

end

net.Receive("pdcity_warrant_pending_sync", function()
	local list = util.JSONToTable(net.ReadString() or "") or {}
	OpenOrRefresh(list)
end)

concommand.Add("pdcity_warrants", function()
	net.Start("pdcity_warrant_list_request")
	net.SendToServer()
end)
