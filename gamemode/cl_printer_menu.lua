--[[---------------------------------------------------------
	Money printer interface, opened by pressing E on a printer you own
	(entities/entities/ent_pdcity_printer.lua). The server resends the
	full state (PDCity_OpenPrinterMenu) after every action, and this file
	just rebuilds the frame from whatever it's given - same pattern as
	cl_bail_menu.lua. All purchases are re-validated server-side
	(core/sv_printers.lua); nothing here is trusted.
-----------------------------------------------------------]]

local MAX_LEVEL = 5

-- cost comes over the wire (0 = maxed), read from the entity's own
-- profile server-side (core/sv_printers.lua's PDCity.PRINTER_TYPES)
-- rather than a client-side table.
local function UpgradeRow(parent, title, level, cost, effectText, onUpgrade)

	local row = vgui.Create("DPanel", parent)
	row:Dock(TOP)
	row:SetTall(60)
	row:DockMargin(0, 0, 0, 8)
	row.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
	end

	local maxed = level >= MAX_LEVEL or (cost or 0) <= 0

	local btn = vgui.Create("DButton", row)
	btn:SetText("")
	btn:Dock(RIGHT)
	btn:DockMargin(0, 10, 12, 10)
	btn:SetWide(110)
	btn:SetEnabled(not maxed)
	btn.Paint = function(self, w, h)
		local col
		if maxed then
			col = PDCity.THEME.Border
		else
			col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
		end
		draw.RoundedBox(5, 0, 0, w, h, col)
		draw.SimpleText(maxed and "MAXED" or ("$" .. cost), "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	if not maxed then
		btn.DoClick = onUpgrade
	end

	local textPanel = vgui.Create("DPanel", row)
	textPanel:Dock(FILL)
	textPanel:DockMargin(12, 8, 8, 8)
	textPanel.Paint = function() end

	local nameLabel = vgui.Create("DLabel", textPanel)
	nameLabel:Dock(TOP)
	nameLabel:SetFont("PDCity_Heading")
	nameLabel:SetText(title .. " (Level " .. level .. "/" .. MAX_LEVEL .. ")")
	nameLabel:SetTextColor(PDCity.THEME.Text)
	nameLabel:SizeToContents()

	local detailLabel = vgui.Create("DLabel", textPanel)
	detailLabel:Dock(TOP)
	detailLabel:DockMargin(0, 4, 0, 0)
	detailLabel:SetFont("PDCity_Small")
	detailLabel:SetText(effectText)
	detailLabel:SetTextColor(PDCity.THEME.TextDim)
	detailLabel:SizeToContents()

	return row

end

net.Receive("PDCity_OpenPrinterMenu", function()

	local ent = net.ReadEntity()
	local unlocked = net.ReadBool()
	local heldMoney = net.ReadUInt(32)
	local speedLevel = net.ReadUInt(8)
	local amountLevel = net.ReadUInt(8)
	local printInterval = net.ReadUInt(16)
	local printAmount = net.ReadUInt(32)
	local timeLeft = net.ReadFloat()
	local printerCount = net.ReadUInt(8)
	local maxPrinters = net.ReadUInt(8)
	local unlockCost = net.ReadUInt(32)
	local speedCost = net.ReadUInt(32)
	local amountCost = net.ReadUInt(32)

	if IsValid(GAMEMODE.PDCityPrinterFrame) then
		GAMEMODE.PDCityPrinterFrame:Remove()
	end

	if not IsValid(ent) then return end

	local frame = PDCity.CreateModernFrame("Money Printer", 440, unlocked and 460 or 220)
	GAMEMODE.PDCityPrinterFrame = frame

	local body = vgui.Create("DPanel", frame)
	body:SetPos(16, 58)
	body:SetSize(frame:GetWide() - 32, frame:GetTall() - 74)
	body.Paint = function() end

	if not unlocked then

		local infoLabel = vgui.Create("DLabel", body)
		infoLabel:Dock(TOP)
		infoLabel:SetFont("PDCity_Body")
		infoLabel:SetText("This printer is locked.")
		infoLabel:SetTextColor(PDCity.THEME.TextDim)
		infoLabel:SizeToContents()
		infoLabel:DockMargin(0, 0, 0, 16)

		local unlockBtn = vgui.Create("DButton", body)
		unlockBtn:SetText("")
		unlockBtn:Dock(TOP)
		unlockBtn:SetTall(44)
		unlockBtn.Paint = function(self, w, h)
			local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
			draw.RoundedBox(6, 0, 0, w, h, col)
			draw.SimpleText("Unlock this printer for $" .. unlockCost, "PDCity_Heading", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		unlockBtn.DoClick = function()
			net.Start("PDCity_PrinterUnlock")
			net.WriteEntity(ent)
			net.SendToServer()
		end

		return
	end

	-- Held money + collect
	local moneyRow = vgui.Create("DPanel", body)
	moneyRow:Dock(TOP)
	moneyRow:SetTall(56)
	moneyRow:DockMargin(0, 0, 0, 12)
	moneyRow.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
	end

	local collectBtn = vgui.Create("DButton", moneyRow)
	collectBtn:SetText("")
	collectBtn:Dock(RIGHT)
	collectBtn:DockMargin(0, 10, 12, 10)
	collectBtn:SetWide(110)
	collectBtn:SetEnabled(heldMoney > 0)
	collectBtn.Paint = function(self, w, h)
		local col = (heldMoney > 0) and (self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim) or PDCity.THEME.Border
		draw.RoundedBox(5, 0, 0, w, h, col)
		draw.SimpleText("COLLECT", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	collectBtn.DoClick = function()
		net.Start("PDCity_PrinterCollect")
		net.WriteEntity(ent)
		net.SendToServer()
	end

	local moneyText = vgui.Create("DPanel", moneyRow)
	moneyText:Dock(FILL)
	moneyText:DockMargin(12, 6, 8, 6)
	moneyText.Paint = function() end

	local heldLabel = vgui.Create("DLabel", moneyText)
	heldLabel:Dock(TOP)
	heldLabel:SetFont("PDCity_Heading")
	heldLabel:SetText("$" .. heldMoney .. " held")
	heldLabel:SetTextColor(PDCity.THEME.Text)
	heldLabel:SizeToContents()

	local printsAt = CurTime() + timeLeft
	local countdownLabel = vgui.Create("DLabel", moneyText)
	countdownLabel:Dock(TOP)
	countdownLabel:DockMargin(0, 4, 0, 0)
	countdownLabel:SetFont("PDCity_Small")
	countdownLabel:SetTextColor(PDCity.THEME.TextDim)
	countdownLabel:SetText("Printing $" .. printAmount .. " every " .. printInterval .. "s")
	countdownLabel.Think = function(self)
		local remaining = math.max(0, math.ceil(printsAt - CurTime()))
		self:SetText("Next $" .. printAmount .. " in " .. remaining .. "s")
	end

	-- Upgrades header
	local upgradesLabel = vgui.Create("DLabel", body)
	upgradesLabel:Dock(TOP)
	upgradesLabel:DockMargin(0, 4, 0, 8)
	upgradesLabel:SetFont("PDCity_Body")
	upgradesLabel:SetText("Upgrades")
	upgradesLabel:SetTextColor(PDCity.THEME.TextDim)
	upgradesLabel:SizeToContents()

	UpgradeRow(body, "Faster Printing", speedLevel, speedCost,
		"Print interval: " .. printInterval .. "s",
		function()
			net.Start("PDCity_PrinterUpgrade")
			net.WriteEntity(ent)
			net.WriteString("speed")
			net.SendToServer()
		end)

	UpgradeRow(body, "More Printing", amountLevel, amountCost,
		"Print amount: $" .. printAmount,
		function()
			net.Start("PDCity_PrinterUpgrade")
			net.WriteEntity(ent)
			net.WriteString("amount")
			net.SendToServer()
		end)

	-- Ownership caps are fixed per job and printer type now - the old
	-- purchasable "Additional Printers" row is gone (see
	-- PDCity.GetMaxPrinters in core/sv_printers.lua), so this is just
	-- a statement of fact.
	local ownLabel = vgui.Create("DLabel", body)
	ownLabel:Dock(TOP)
	ownLabel:DockMargin(0, 4, 0, 0)
	ownLabel:SetFont("PDCity_Small")
	ownLabel:SetText("You own " .. printerCount .. "/" .. maxPrinters .. " of this printer type.")
	ownLabel:SetTextColor(PDCity.THEME.TextDim)
	ownLabel:SizeToContents()

end)
