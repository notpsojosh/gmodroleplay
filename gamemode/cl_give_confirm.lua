--[[---------------------------------------------------------
	Confirmation dialog for /give (both forms - see core/sv_money.lua).
	The server sends the target's name and amount; nothing transfers
	until the player clicks YES, and closing the window declines.
-----------------------------------------------------------]]

local function SendAnswer(accepted)
	net.Start("PDCity_GiveConfirmed")
	net.WriteBool(accepted)
	net.SendToServer()
end

local function StyleButton(btn, text, accent)
	btn:SetText("")
	btn.Paint = function(self, w, h)
		local base = accent and PDCity.THEME.AccentDim or PDCity.THEME.Panel
		local hover = accent and PDCity.THEME.Accent or PDCity.THEME.PanelHover
		draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and hover or base)
		draw.SimpleText(text, "PDCity_Body", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

net.Receive("PDCity_ConfirmGive", function()

	local targetName = net.ReadString()
	local amount = net.ReadUInt(32)

	-- A newer request replaces any dialog still open; the server has
	-- already replaced the pending transfer it corresponds to.
	if IsValid(GAMEMODE.PDCityGiveConfirm) then
		GAMEMODE.PDCityGiveConfirm.pdcity_Answered = true -- don't decline the new pending give on removal
		GAMEMODE.PDCityGiveConfirm:Remove()
	end

	local frame = PDCity.CreateModernFrame("Confirm Transfer", 380, 170)
	GAMEMODE.PDCityGiveConfirm = frame

	-- Treat closing the window (X / anything but YES) as declining, so
	-- the server never sits on a stale pending transfer.
	frame.OnRemove = function(self)
		if not self.pdcity_Answered then
			SendAnswer(false)
		end
	end

	local question = vgui.Create("DLabel", frame)
	question:SetPos(24, 60)
	question:SetSize(frame:GetWide() - 48, 44)
	question:SetFont("PDCity_Body")
	question:SetText("Are you sure you wish to give " .. targetName .. " $" .. amount .. "?")
	question:SetTextColor(PDCity.THEME.Text)
	question:SetWrap(true)

	local yes = vgui.Create("DButton", frame)
	yes:SetSize(150, 34)
	yes:SetPos(24, frame:GetTall() - 50)
	StyleButton(yes, "YES, GIVE $" .. amount, true)
	yes.DoClick = function()
		frame.pdcity_Answered = true
		SendAnswer(true)
		frame:Close()
	end

	local no = vgui.Create("DButton", frame)
	no:SetSize(150, 34)
	no:SetPos(frame:GetWide() - 174, frame:GetTall() - 50)
	StyleButton(no, "CANCEL", false)
	no.DoClick = function()
		frame.pdcity_Answered = true
		SendAnswer(false)
		frame:Close()
	end

end)
