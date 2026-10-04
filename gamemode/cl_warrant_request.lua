--[[---------------------------------------------------------
	Warrant request form, opened client-side when someone uses
	weapon_pdcity_warrantrequest. Eligibility (holding that tool) is
	checked server-side when this actually submits (core/sv_wanted.lua) -
	this file only ever builds the form, so an ineligible holder just
	gets a polite chat denial on submit rather than a broken-looking UI.

	"Who" is a real search box + filtered list, not a DComboBox - a
	DComboBox doesn't filter its own choices as you type, it's just a
	static dropdown, which isn't what "searchable" (the original spec)
	actually meant.

	Auto-fills from whatever door the player is looking at, if any -
	the door system's own GetDoor()/DoorOwner NWEntity is a shared-realm
	lookup (lua/autorun/sh_doors.lua), so this needs no server round
	trip. Still changeable afterwards: it's a starting guess (the door's
	owner is presumably who to investigate), not a lock-in.
-----------------------------------------------------------]]

function PDCity.OpenWarrantRequest()

	if IsValid(GAMEMODE.PDCityWarrantRequestFrame) then
		GAMEMODE.PDCityWarrantRequestFrame:Remove()
	end

	local frame = PDCity.CreateModernFrame("Warrant Request", 380, 420)
	GAMEMODE.PDCityWarrantRequestFrame = frame

	local door = LocalPlayer():GetDoor()
	local doorOwner = IsValid(door) and door:GetNWEntity("DoorOwner") or nil
	local selectedTarget = (IsValid(doorOwner) and doorOwner ~= LocalPlayer()) and doorOwner or nil

	local whoLabel = vgui.Create("DLabel", frame)
	whoLabel:SetPos(20, 58)
	whoLabel:SetFont("PDCity_Body")
	whoLabel:SetText("Request warrant on:")
	whoLabel:SetTextColor(PDCity.THEME.Text)
	whoLabel:SizeToContents()

	local searchEntry = vgui.Create("DTextEntry", frame)
	searchEntry:SetPos(20, 80)
	searchEntry:SetSize(340, 28)
	searchEntry:SetPlaceholderText("Type a name to search...")

	local listPanel = vgui.Create("DScrollPanel", frame)
	listPanel:SetPos(20, 112)
	listPanel:SetSize(340, 120)

	local RefreshList -- forward declared, DoClick below needs to call it

	local function BuildRow(ply)
		local row = vgui.Create("DButton", listPanel)
		row:SetText("")
		row:SetTall(28)
		row:Dock(TOP)
		row:DockMargin(0, 0, 0, 4)

		row.Paint = function(self, w, h)
			local selected = selectedTarget == ply
			local col = selected and PDCity.THEME.Accent or (self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
			draw.RoundedBox(4, 0, 0, w, h, col)
			draw.SimpleText(PDCity.GetDisplayName(ply), "PDCity_Small", 8, h / 2, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end

		row.DoClick = function()
			selectedTarget = ply
			RefreshList()
		end
	end

	RefreshList = function()
		listPanel:Clear()

		local filter = string.lower(string.Trim(searchEntry:GetValue() or ""))

		for _, ply in ipairs(player.GetAll()) do
			if ply ~= LocalPlayer() then
				if filter == "" or string.find(string.lower(PDCity.GetDisplayName(ply)), filter, 1, true) then
					BuildRow(ply)
				end
			end
		end
	end

	searchEntry.OnValueChange = function()
		RefreshList()
	end

	RefreshList()

	local reasonLabel = vgui.Create("DLabel", frame)
	reasonLabel:SetPos(20, 246)
	reasonLabel:SetFont("PDCity_Body")
	reasonLabel:SetText("Reason:")
	reasonLabel:SetTextColor(PDCity.THEME.Text)
	reasonLabel:SizeToContents()

	local reasonEntry = vgui.Create("DTextEntry", frame)
	reasonEntry:SetPos(20, 268)
	reasonEntry:SetSize(340, 28)
	reasonEntry:SetPlaceholderText("Why does this player deserve a warrant?")

	local submitBtn = vgui.Create("DButton", frame)
	submitBtn:SetPos(20, 320)
	submitBtn:SetSize(340, 36)
	submitBtn:SetText("")
	submitBtn.Paint = function(self, w, h)
		draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim)
		draw.SimpleText("SUBMIT REQUEST", "PDCity_Body", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	submitBtn.DoClick = function()
		local reason = string.Trim(reasonEntry:GetValue())

		if not IsValid(selectedTarget) then
			reasonEntry:SetPlaceholderText("Pick a player from the list first!")
			return
		end

		if reason == "" then
			reasonEntry:SetPlaceholderText("Give a reason first!")
			return
		end

		net.Start("pdcity_warrant_submit")
			net.WriteEntity(selectedTarget)
			net.WriteString(reason)
		net.SendToServer()

		frame:Close()
	end

end
