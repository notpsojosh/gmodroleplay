--[[---------------------------------------------------------
	XP crate pickup menu - pick which job class to put the crate's XP
	into. The level/XP shown per class is exactly PDCity.MY_JOB_XP
	(synced by core/sv_job_xp.lua, same data the F1 "Job Levels" tab
	reads) - this menu doesn't ask the server for anything extra, it
	just needs to know which entity and how much XP is on offer.
-----------------------------------------------------------]]

local frame

net.Receive("pdcity_xpcrate_open", function()

	local ent = net.ReadEntity()
	local amount = net.ReadUInt(16)

	if not IsValid(ent) then return end

	if IsValid(frame) then frame:Remove() end

	frame = PDCity.CreateModernFrame("XP Crate - +" .. amount .. " XP", 460, 500)

	local intro = vgui.Create("DLabel", frame)
	intro:SetPos(20, 56)
	intro:SetSize(420, 36)
	intro:SetFont("PDCity_Small")
	intro:SetTextColor(PDCity.THEME.TextDim)
	intro:SetWrap(true)
	intro:SetText("Choose which job class gets the +" .. amount .. " XP. Every rank within a class shares one level, so it applies no matter which rank you're currently working.")

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(20, 96)
	scroll:SetSize(420, 384)

	for _, class in ipairs(PDCity.GetAllJobClasses()) do

		local xp = (PDCity.MY_JOB_XP or {})[class] or 0
		local level, into, span = PDCity.XPProgress(xp)

		local row = vgui.Create("DPanel", scroll)
		row:Dock(TOP)
		row:SetTall(64)
		row:DockMargin(0, 0, 0, 8)
		row:DockPadding(12, 8, 12, 8)
		row.Paint = function(self, w, h)
			draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
		end

		local depositBtn = vgui.Create("DButton", row)
		depositBtn:Dock(RIGHT)
		depositBtn:SetWide(110)
		depositBtn:SetText("")
		depositBtn.Paint = function(self, w, h)
			local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
			draw.RoundedBox(5, 0, 0, w, h, col)
			draw.SimpleText("DEPOSIT", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		depositBtn.DoClick = function()
			net.Start("pdcity_xpcrate_choose")
				net.WriteEntity(ent)
				net.WriteString(class)
			net.SendToServer()
			frame:Close()
		end

		local info = vgui.Create("DPanel", row)
		info:Dock(FILL)
		info:DockMargin(0, 0, 12, 0)
		info.Paint = function() end

		local title = vgui.Create("DLabel", info)
		title:Dock(TOP)
		title:SetTall(20)
		title:SetFont("PDCity_Body")
		title:SetText(class .. " - Level " .. level)
		title:SetTextColor(PDCity.THEME.Text)

		local barBack = vgui.Create("DPanel", info)
		barBack:Dock(TOP)
		barBack:SetTall(10)
		barBack:DockMargin(0, 4, 0, 4)
		barBack.Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Border)
			if span > 0 then
				draw.RoundedBox(4, 0, 0, w * math.Clamp(into / span, 0, 1), h, PDCity.THEME.Accent)
			else
				draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Accent)
			end
		end

		local progressLabel = vgui.Create("DLabel", info)
		progressLabel:Dock(TOP)
		progressLabel:SetTall(14)
		progressLabel:SetFont("PDCity_Small")
		progressLabel:SetTextColor(PDCity.THEME.TextDim)
		progressLabel:SetText(span > 0 and (into .. " / " .. span .. " xp to next level") or "Max level")

	end

end)
