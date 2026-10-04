--[[---------------------------------------------------------
	Bail menu, opened by pressing E on a Bail Bondsman
	(entities/entities/ent_pdcity_bail.lua). Lists everyone currently
	jailed (yourself included, if you are) with their remaining time and
	cost; paying sends PDCity_PayBail, which the server fully
	re-validates (core/sv_arrests.lua) rather than trusting this list.
-----------------------------------------------------------]]

net.Receive("PDCity_OpenBailMenu", function()

	local count = net.ReadUInt(8)
	local entries = {}
	for i = 1, count do
		entries[i] = {
			ply = net.ReadEntity(),
			minutes = net.ReadUInt(16),
			cost = net.ReadUInt(32),
		}
	end

	if IsValid(GAMEMODE.PDCityBailFrame) then
		GAMEMODE.PDCityBailFrame:Remove()
	end

	local frame = PDCity.CreateModernFrame("Bail Bondsman", 420, 400)
	GAMEMODE.PDCityBailFrame = frame

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(16, 58)
	scroll:SetSize(frame:GetWide() - 32, frame:GetTall() - 74)

	local me = LocalPlayer()

	for _, entry in ipairs(entries) do
		if IsValid(entry.ply) then

			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(64)
			row:DockMargin(0, 0, 0, 8)
			row.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
			end

			local isSelf = entry.ply == me
			local label = PDCity.GetDisplayName(entry.ply) .. (isSelf and " (you)" or "")

			local payBtn = vgui.Create("DButton", row)
			payBtn:SetText("")
			payBtn:Dock(RIGHT)
			payBtn:DockMargin(0, 12, 12, 12)
			payBtn:SetWide(110)
			payBtn.Paint = function(self, w, h)
				local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
				draw.RoundedBox(5, 0, 0, w, h, col)
				draw.SimpleText("PAY $" .. entry.cost, "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			payBtn.DoClick = function()
				net.Start("PDCity_PayBail")
				net.WriteEntity(entry.ply)
				net.SendToServer()
				frame:Close()
			end

			local textPanel = vgui.Create("DPanel", row)
			textPanel:Dock(FILL)
			textPanel:DockMargin(12, 8, 8, 8)
			textPanel.Paint = function() end

			local nameLabel = vgui.Create("DLabel", textPanel)
			nameLabel:Dock(TOP)
			nameLabel:SetFont("PDCity_Heading")
			nameLabel:SetText(label)
			nameLabel:SetTextColor(PDCity.THEME.Text)
			nameLabel:SizeToContents()

			local detailLabel = vgui.Create("DLabel", textPanel)
			detailLabel:Dock(TOP)
			detailLabel:DockMargin(0, 4, 0, 0)
			detailLabel:SetFont("PDCity_Small")
			detailLabel:SetText(entry.minutes .. " year(s) left - bail $" .. entry.cost)
			detailLabel:SetTextColor(PDCity.THEME.TextDim)
			detailLabel:SizeToContents()

		end
	end

end)
