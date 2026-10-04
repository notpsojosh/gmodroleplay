--[[---------------------------------------------------------
	Flowchart editor - the owner-accessible, no-Lua alternative to the
	Developer Console's raw code (core/sv_activities.lua's Flow field).
	Opened from the F4 admin editor's Activities tab (cl_f4_admin.lua)
	via PDCity.OpenFlowEditor(activityID, activityName), owner-only same
	as everything else in that editor - this file adds no permission
	check of its own, PDCity_OpenF4AdminEditor's own gate is what stops
	a non-owner from ever reaching the button that opens this.

	Deliberately a straight top-to-bottom node LIST, not a real branching
	graph - every node runs, in order, unless one of them (currently only
	"Charge Player", if the player can't afford it) stops the chain
	outright. A full branch/condition system (an "if" node with two
	paths) is real, wanted future work, but a linear chain already covers
	a solid chunk of what a job activity needs (charge for equipment,
	wait for a timer, give the result, message the player) without
	needing a true drag-and-wire canvas - see core/sv_activities.lua's
	own Flow section for exactly how each node type runs server-side.
-----------------------------------------------------------]]

local NODE_LABELS = {
	charge = "Charge Player",
	give_money = "Give Player Money",
	give_item = "Give Item",
	chat = "Chat Message",
	wait = "Wait",
	remove_other = "Remove Touching Item",
	remove_self = "Remove This Entity",
	spawn_entity = "Spawn Entity",
	run_code_tag = "Run Code Tag (Developer)",
	open_interface = "Open Interface",
	give_currency = "Give Currency",
	charge_currency = "Charge Currency",
}

-- Order matters here (this drives the "+ Add Node" menu's order) -
-- FLOW_NODE_TYPES itself (core/sv_activities.lua) is an unordered table,
-- fine for validation but not for a stable menu.
local NODE_ORDER = { "charge", "give_money", "give_item", "give_currency", "charge_currency", "spawn_entity", "run_code_tag", "open_interface", "chat", "wait", "remove_other", "remove_self" }

local function DefaultNode(nodeType)
	if nodeType == "charge" or nodeType == "give_money" then return { Type = nodeType, Amount = 10 } end
	if nodeType == "give_item" or nodeType == "spawn_entity" then return { Type = nodeType, Class = "" } end
	if nodeType == "give_currency" or nodeType == "charge_currency" then return { Type = nodeType, Currency = nil, Amount = 10 } end
	if nodeType == "chat" then return { Type = nodeType, Text = "" } end
	if nodeType == "wait" then return { Type = nodeType, Seconds = 5, Label = "" } end
	if nodeType == "run_code_tag" then return { Type = nodeType, Tag = "" } end
	if nodeType == "open_interface" then return { Type = nodeType, Interface = "" } end
	return { Type = nodeType }
end

local function SummaryFor(node)
	if node.Type == "charge" or node.Type == "give_money" then return "$" .. tostring(node.Amount or 0) end
	if node.Type == "give_item" or node.Type == "spawn_entity" then return (node.Class ~= "" and node.Class) or "(no class set)" end
	if node.Type == "give_currency" or node.Type == "charge_currency" then
		local currency = node.Currency and PDCity.GetCurrencyByID(node.Currency)
		return tostring(node.Amount or 0) .. " " .. (currency and currency.Symbol or "(no currency set)")
	end
	if node.Type == "chat" then return (node.Text ~= "" and ("\"" .. node.Text .. "\"")) or "(no text set)" end
	if node.Type == "wait" then return tostring(node.Seconds or 0) .. "s" .. ((node.Label and node.Label ~= "") and (" (\"" .. node.Label .. "\")") or "") end
	if node.Type == "run_code_tag" then return (node.Tag ~= "" and ("#" .. node.Tag)) or "(no tag set)" end
	if node.Type == "open_interface" then return (node.Interface ~= "" and node.Interface) or "(no interface set)" end
	return ""
end

-- Layout constants - PAD is the frame's own left/right/top breathing room,
-- BOTTOM_BAR_H/BOTTOM_GAP size the fixed Add Node/Save Flowchart row so its
-- height can be subtracted from the scroll panel's own (previously this
-- wasn't subtracted at all - the scroll extended a good 70px past where
-- the button row started, so the last couple of cards sat UNDER the
-- buttons, unreachable - "the buttons cover the bottom nodes").
local PAD = 16
local HINT_TOP = 54
local HINT_H = 40
local SCROLL_TOP = HINT_TOP + HINT_H + 10
local BOTTOM_BAR_H = 32
local BOTTOM_GAP = 16 -- above the button row, and below it to the frame edge

function PDCity.OpenFlowEditor(activityID, activityName)

	if IsValid(GAMEMODE.PDCityFlowEditorFrame) then
		GAMEMODE.PDCityFlowEditorFrame:Remove()
	end

	PDCity.PushMenuDim()

	-- Noticeably roomier than the old 560x700 - cards now carry more
	-- breathing room per field (see BuildNodeCard below), so the old size
	-- packed everything in tight enough to read as "cramped".
	local frameW, frameH = PDCity.ResponsiveFrameSize(680, 820)
	local frame = PDCity.CreateModernFrame("Flowchart - " .. activityName, frameW, frameH, function(newW, newH)
		if IsValid(frame.PDCityHint) then frame.PDCityHint:SetWide(newW - PAD * 2) end
		if IsValid(frame.PDCityScroll) then
			frame.PDCityScroll:SetSize(newW - PAD * 2, newH - SCROLL_TOP - BOTTOM_BAR_H - BOTTOM_GAP * 2)
		end
		if IsValid(frame.PDCityAddBtn) then
			local btnW = (newW - PAD * 2 - 12) / 2
			frame.PDCityAddBtn:SetSize(btnW, BOTTOM_BAR_H)
			frame.PDCityAddBtn:SetPos(PAD, newH - BOTTOM_BAR_H - BOTTOM_GAP)
			frame.PDCitySaveBtn:SetSize(btnW, BOTTOM_BAR_H)
			frame.PDCitySaveBtn:SetPos(PAD + btnW + 12, newH - BOTTOM_BAR_H - BOTTOM_GAP)
		end
	end)
	GAMEMODE.PDCityFlowEditorFrame = frame
	frame.PDCityActivityID = activityID
	frame.OnRemove = function() PDCity.PopMenuDim() end

	local hint = vgui.Create("DLabel", frame)
	hint:SetPos(PAD, HINT_TOP)
	hint:SetSize(frame:GetWide() - PAD * 2, HINT_H)
	hint:SetFont("PDCity_Small")
	hint:SetWrap(true)
	hint:SetText("Runs top to bottom when this activity triggers. \"Charge Player\" stops the chain if they can't afford it - everything else always continues to the next node.")
	hint:SetTextColor(PDCity.THEME.TextDim)
	frame.PDCityHint = hint

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(PAD, SCROLL_TOP)
	scroll:SetSize(frame:GetWide() - PAD * 2, frame:GetTall() - SCROLL_TOP - BOTTOM_BAR_H - BOTTOM_GAP * 2)
	PDCity.ApplyFastScroll(scroll)
	frame.PDCityScroll = scroll

	local list = vgui.Create("DIconLayout", scroll)
	list:Dock(TOP)
	list:SetSpaceY(10)

	local nodes = {}
	local RefreshList -- forward declared, node cards call this on any edit

	local function ArrowSpacer(parent)
		local spacer = vgui.Create("DPanel", parent)
		spacer:SetWide(list:GetWide() - 4)
		spacer:SetTall(22)
		spacer.Paint = function(self, w, h)
			surface.SetDrawColor(PDCity.THEME.Border)
			surface.DrawLine(w / 2, 0, w / 2, h - 8)
			surface.DrawLine(w / 2 - 4, h - 12, w / 2, h - 4)
			surface.DrawLine(w / 2 + 4, h - 12, w / 2, h - 4)
		end
	end

	-- "Wait" carries two fields (Seconds + an optional display Label), so
	-- it gets a taller card than everything else's single field row.
	local CARD_H_NORMAL = 92
	local CARD_H_WAIT = 130

	local function BuildNodeCard(node, index, hasWarning)
		local card = vgui.Create("DPanel", list)
		card:SetWide(list:GetWide() - 4)
		local isTwoField = node.Type == "wait" or node.Type == "give_currency" or node.Type == "charge_currency"
		card:SetTall(isTwoField and CARD_H_WAIT or CARD_H_NORMAL)
		card.Paint = function(self, w, h)
			draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
			if hasWarning then
				surface.SetDrawColor(Color(210, 120, 60))
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
		end

		local title = vgui.Create("DLabel", card)
		title:SetPos(14, 12)
		title:SetSize(card:GetWide() - 100, 22)
		title:SetFont("PDCity_Heading")
		title:SetText(NODE_LABELS[node.Type] or node.Type)
		title:SetTextColor(PDCity.THEME.Text)

		local removeBtn = vgui.Create("DButton", card)
		removeBtn:SetPos(card:GetWide() - 82, 12)
		removeBtn:SetSize(68, 22)
		PDCity.StyleButton(removeBtn, "Remove", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })
		removeBtn.DoClick = function()
			table.remove(nodes, index)
			RefreshList()
		end

		local FIELD_TOP = 46
		local FIELD_H = 28

		-- One or two field rows per node type - kept inline on the card
		-- rather than a separate edit popup, since nothing here needs more
		-- than that.
		if node.Type == "charge" or node.Type == "give_money" then
			local amountEntry = vgui.Create("DTextEntry", card)
			amountEntry:SetPos(14, FIELD_TOP)
			amountEntry:SetSize(card:GetWide() - 28, FIELD_H)
			amountEntry:SetNumeric(true)
			amountEntry:SetPlaceholderText("Amount ($)")
			amountEntry:SetValue(tostring(node.Amount or 0))
			amountEntry.OnValueChange = function(self, val) node.Amount = tonumber(val) or 0 end

		elseif node.Type == "give_currency" or node.Type == "charge_currency" then
			local currency = node.Currency and PDCity.GetCurrencyByID(node.Currency)

			local currencyBtn = vgui.Create("DButton", card)
			currencyBtn:SetPos(14, FIELD_TOP)
			currencyBtn:SetSize(card:GetWide() - 28, FIELD_H)
			local label = currency and (currency.Name .. " (" .. currency.Symbol .. ")") or "Choose currency..."
			PDCity.StyleButton(currencyBtn, label, { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = currency and PDCity.THEME.Text or PDCity.THEME.TextDim })
			currencyBtn.DoClick = function()
				PDCity.OpenCurrencyPicker(function(picked)
					node.Currency = picked.ID
					RefreshList()
				end)
			end

			local amountEntry = vgui.Create("DTextEntry", card)
			amountEntry:SetPos(14, FIELD_TOP + FIELD_H + 8)
			amountEntry:SetSize(card:GetWide() - 28, FIELD_H)
			amountEntry:SetNumeric(true)
			amountEntry:SetPlaceholderText("Amount")
			amountEntry:SetValue(tostring(node.Amount or 0))
			amountEntry.OnValueChange = function(self, val) node.Amount = tonumber(val) or 0 end

		elseif node.Type == "give_item" or node.Type == "spawn_entity" then
			local classBtn = vgui.Create("DButton", card)
			classBtn:SetPos(14, FIELD_TOP)
			classBtn:SetSize(card:GetWide() - 28, FIELD_H)
			local label = (node.Class and node.Class ~= "") and node.Class
				or (node.Type == "spawn_entity" and "Choose entity to spawn..." or "Choose item class...")
			PDCity.StyleButton(classBtn, label, { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = (node.Class and node.Class ~= "") and PDCity.THEME.Text or PDCity.THEME.TextDim })
			classBtn.DoClick = function()
				PDCity.OpenEntityClassPicker(function(entry)
					node.Class = entry.Class
					RefreshList()
				end)
			end

		elseif node.Type == "chat" then
			local textEntry = vgui.Create("DTextEntry", card)
			textEntry:SetPos(14, FIELD_TOP)
			textEntry:SetSize(card:GetWide() - 28, FIELD_H)
			textEntry:SetPlaceholderText("Message text")
			textEntry:SetValue(node.Text or "")
			textEntry.OnValueChange = function(self, val) node.Text = val end

		elseif node.Type == "wait" then
			local secondsEntry = vgui.Create("DTextEntry", card)
			secondsEntry:SetPos(14, FIELD_TOP)
			secondsEntry:SetSize(card:GetWide() - 28, FIELD_H)
			secondsEntry:SetNumeric(true)
			secondsEntry:SetPlaceholderText("Seconds")
			secondsEntry:SetValue(tostring(node.Seconds or 0))
			secondsEntry.OnValueChange = function(self, val) node.Seconds = tonumber(val) or 0 end

			local labelEntry = vgui.Create("DTextEntry", card)
			labelEntry:SetPos(14, FIELD_TOP + FIELD_H + 8)
			labelEntry:SetSize(card:GetWide() - 28, FIELD_H)
			labelEntry:SetPlaceholderText("Countdown name shown in-game (optional, e.g. \"Processing\" - defaults to \"Waiting\")")
			labelEntry:SetValue(node.Label or "")
			labelEntry.OnValueChange = function(self, val) node.Label = val end

		elseif node.Type == "run_code_tag" then
			local tagEntry = vgui.Create("DTextEntry", card)
			tagEntry:SetPos(14, FIELD_TOP)
			tagEntry:SetSize(card:GetWide() - 28, FIELD_H)
			tagEntry:SetPlaceholderText("Tag name (must match PDCity.DefineCodeTag in the Developer Console code)")
			tagEntry:SetValue(node.Tag or "")
			tagEntry.OnValueChange = function(self, val) node.Tag = val end

		elseif node.Type == "open_interface" then
			local interfaceBtn = vgui.Create("DButton", card)
			interfaceBtn:SetPos(14, FIELD_TOP)
			interfaceBtn:SetSize(card:GetWide() - 28, FIELD_H)
			local label = (node.Interface and node.Interface ~= "") and node.Interface or "Choose interface..."
			PDCity.StyleButton(interfaceBtn, label, { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = (node.Interface and node.Interface ~= "") and PDCity.THEME.Text or PDCity.THEME.TextDim })
			interfaceBtn.DoClick = function()
				PDCity.OpenInterfacePicker(function(name)
					node.Interface = name
					RefreshList()
				end)
			end

		else
			local note = vgui.Create("DLabel", card)
			note:SetPos(14, FIELD_TOP + 4)
			note:SetSize(card:GetWide() - 28, 22)
			note:SetFont("PDCity_Small")
			note:SetText(node.Type == "remove_self"
				and "No settings - removes the entity this activity is on."
				or "No settings - removes whatever touched this activity (collide-trigger activities only).")
			note:SetTextColor(PDCity.THEME.TextDim)
			note:SetWrap(true)
		end

		return card
	end

	-- "Spawn Entity" reads the triggering entity's OWN position, so a
	-- "Remove This Entity" earlier in the chain leaves nothing there to
	-- read by the time Spawn Entity runs - not a crash, the chain just
	-- silently stops (RunFlowFrom's own IsValid(ent) check at the top of
	-- each node quietly ends it) once the entity's gone, so Spawn Entity
	-- never actually fires. Returns the index of the offending
	-- "Remove This Entity" node, or nil if the order's fine.
	local function FindOrderIssue(nodeList)
		local removedAt = nil
		for i, node in ipairs(nodeList) do
			if node.Type == "remove_self" and not removedAt then
				removedAt = i
			elseif node.Type == "spawn_entity" and removedAt then
				return removedAt
			end
		end
		return nil
	end

	RefreshList = function()
		list:Clear()

		local warnAt = FindOrderIssue(nodes)

		if warnAt then
			local warning = vgui.Create("DPanel", list)
			warning:SetWide(list:GetWide() - 4)
			warning:SetTall(48)
			warning:DockMargin(0, 0, 0, 8)
			warning.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
				surface.SetDrawColor(Color(210, 120, 60))
				surface.DrawRect(0, 0, 3, h)
			end

			local warnLabel = vgui.Create("DLabel", warning)
			warnLabel:SetPos(12, 6)
			warnLabel:SetSize(warning:GetWide() - 20, 36)
			warnLabel:SetFont("PDCity_Small")
			warnLabel:SetWrap(true)
			warnLabel:SetText("\"Remove This Entity\" (highlighted below) comes before a \"Spawn Entity\" node - Spawn Entity needs this entity to still exist, so it'll never actually run. Move Remove This Entity below it.")
			warnLabel:SetTextColor(Color(230, 170, 120))
		end

		local start = vgui.Create("DLabel", list)
		start:SetWide(list:GetWide() - 4)
		start:SetTall(24)
		start:SetFont("PDCity_Small")
		start:SetText("On Triggered")
		start:SetTextColor(PDCity.THEME.TextDim)
		start:SetContentAlignment(5)

		for i, node in ipairs(nodes) do
			ArrowSpacer(list)
			BuildNodeCard(node, i, i == warnAt)
		end

		if #nodes == 0 then
			local empty = vgui.Create("DLabel", list)
			empty:SetWide(list:GetWide() - 4)
			empty:SetTall(30)
			empty:SetFont("PDCity_Small")
			empty:SetText("No nodes yet - add one below.")
			empty:SetTextColor(PDCity.THEME.TextDim)
			empty:SetContentAlignment(5)
		end
	end

	local btnW = (frame:GetWide() - PAD * 2 - 12) / 2
	local btnY = frame:GetTall() - BOTTOM_BAR_H - BOTTOM_GAP

	local addBtn = vgui.Create("DButton", frame)
	addBtn:SetPos(PAD, btnY)
	addBtn:SetSize(btnW, BOTTOM_BAR_H)
	PDCity.StyleButton(addBtn, "+ Add Node")
	addBtn.DoClick = function()
		local menu = DermaMenu()
		for _, nodeType in ipairs(NODE_ORDER) do
			menu:AddOption(NODE_LABELS[nodeType], function()
				table.insert(nodes, DefaultNode(nodeType))
				RefreshList()
			end)
		end
		menu:Open()
	end
	frame.PDCityAddBtn = addBtn

	local saveBtn = vgui.Create("DButton", frame)
	saveBtn:SetPos(PAD + btnW + 12, btnY)
	saveBtn:SetSize(btnW, BOTTOM_BAR_H)
	PDCity.StyleButton(saveBtn, "Save Flowchart")
	saveBtn.DoClick = function()
		net.Start("pdcity_activity_admin")
			net.WriteString(util.TableToJSON({ Action = "set_flow", Payload = { ID = activityID, Flow = nodes } }))
		net.SendToServer()
	end
	frame.PDCitySaveBtn = saveBtn

	net.Start("pdcity_activity_admin")
		net.WriteString(util.TableToJSON({ Action = "get_flow", Payload = { ID = activityID } }))
	net.SendToServer()

	frame.PDCitySetNodes = function(loaded)
		nodes = loaded
		RefreshList()
	end

	RefreshList()

end

net.Receive("pdcity_activity_flow", function()
	local id = net.ReadUInt(32)
	local flow = util.JSONToTable(net.ReadString() or "[]") or {}

	local frame = GAMEMODE.PDCityFlowEditorFrame
	if not IsValid(frame) or frame.PDCityActivityID ~= id then return end

	frame.PDCitySetNodes(flow)
end)
