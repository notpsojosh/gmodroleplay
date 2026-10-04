--[[---------------------------------------------------------
	Developer Console - "!devcode" opens this. The one thing a developer
	(core/sv_developers.lua's owner-editable list - narrower than staff,
	narrower than admin) can actually do: write the Lua code behind
	either a Job Activity's trigger (core/sv_activities.lua's "set_code"/
	"get_code") or a Custom NPC's use (core/sv_npc_classes.lua's own
	identical pair) - the sidebar below lists both kinds together.

	No client-side permission check here at all, deliberately - this
	panel only ever opens because the server already decided to send
	"pdcity_devconsole_open" (core/sv_activities.lua's own !devcode
	handler, gated on PDCity.IsDeveloper there), same as every other
	server-authoritative-gate panel in this gamemode (F1/F4, Staff Menu,
	tickets...). Every action this sends is re-checked server-side
	regardless.
-----------------------------------------------------------]]

-- Both kinds' admin net messages take the exact same {Action, Payload}
-- shape, just on different net strings - one send helper, kind picks
-- which string.
local NET_STRING_FOR_KIND = {
	activity = "pdcity_activity_admin",
	npc = "pdcity_customnpc_admin",
}

local function SendAction(kind, action, payload)
	net.Start(NET_STRING_FOR_KIND[kind])
		net.WriteString(util.TableToJSON({ Action = action, Payload = payload or {} }))
	net.SendToServer()
end

--[[---------------------------------------------------------
	Entity lookup - "Find Entity..." button below. Code you write here
	almost always needs to reference SOME other entity by its exact class
	string (ents.Create("pdcity_customprop_3"), PDCity.InventoryAdd(ply,
	"pdcity_customprop_5", 1)...) - before this, the only way to find one
	was scrolling back through chat to find where Prop Copier printed it.
	This just lists everything with a known Name+Class - Custom Props
	(core/sh_custom_props.lua) and every Job Activity's own Class
	(core/sh_activities.lua), deduplicated by class since an Activity is
	very often tied to a Custom Prop already in the first list - and
	copies the class to the clipboard on click.
-----------------------------------------------------------]]
local function GetKnownEntities()
	local seen = {}
	local list = {}

	local function Add(name, class)
		if not class or class == "" or seen[class] then return end
		seen[class] = true
		table.insert(list, { Name = name, Class = class })
	end

	for _, def in ipairs(PDCity.CUSTOM_PROPS or {}) do
		Add(def.Name, PDCity.CustomPropClass(def.ID))
	end
	for _, activity in ipairs(PDCity.ACTIVITIES or {}) do
		Add(activity.Name, activity.Class)
	end

	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end

local function OpenEntityLookup()

	local frame = PDCity.OpenPicker("Find Entity", 480, 480)

	local top = 48

	local filterEntry = vgui.Create("DTextEntry", frame)
	filterEntry:SetPos(16, top + 10)
	filterEntry:SetSize(448, 26)
	filterEntry:SetPlaceholderText("Search by name or class...")

	local hint = vgui.Create("DLabel", frame)
	hint:SetPos(16, top + 40)
	hint:SetSize(448, 18)
	hint:SetFont("PDCity_Small")
	hint:SetText("Click a row to copy its class to your clipboard.")
	hint:SetTextColor(PDCity.THEME.TextDim)

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(16, top + 64)
	scroll:SetSize(448, 480 - top - 74)
	PDCity.ApplyFastScroll(scroll)

	local entities = GetKnownEntities()

	local function RefreshList(filter)
		scroll:Clear()
		filter = filter and filter:lower() or ""

		for _, entry in ipairs(entities) do
			if filter == "" or entry.Name:lower():find(filter, 1, true) or entry.Class:lower():find(filter, 1, true) then
				local row = vgui.Create("DButton", scroll)
				row:Dock(TOP)
				row:SetTall(40)
				row:DockMargin(0, 0, 4, 4)
				row:SetText("")
				row.Paint = function(self, w, h)
					draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
					draw.SimpleText(entry.Name, "PDCity_Small", 8, 10, PDCity.THEME.Text, TEXT_ALIGN_LEFT)
					draw.SimpleText(entry.Class, "PDCity_Small", 8, 24, PDCity.THEME.TextDim, TEXT_ALIGN_LEFT)
				end
				row.DoClick = function()
					SetClipboardText(entry.Class)
					PDCity.ShowToast("Copied " .. entry.Class .. " to clipboard.")
				end
			end
		end

		if #entities == 0 then
			local empty = vgui.Create("DLabel", scroll)
			empty:Dock(TOP)
			empty:SetTall(40)
			empty:SetFont("PDCity_Small")
			empty:SetWrap(true)
			empty:SetText("Nothing to list yet - make a Custom Prop (Prop Copier tool) or an Activity first.")
			empty:SetTextColor(PDCity.THEME.TextDim)
		end
	end
	RefreshList("")

	filterEntry.OnValueChange = function(self, val) RefreshList(val) end
	filterEntry:RequestFocus()

end

-- The page currently built (F1 menu), read by the net receivers below.
local activePage

--[[---------------------------------------------------------
	Page - built inside the F1 menu's content area (cl_f1_menu.lua) as the
	"Developer Console" page, shown to the owner and developers. "!devcode"
	in chat opens F1 straight onto it.
-----------------------------------------------------------]]
function PDCity.BuildDevConsolePanel(parent)

	local frame = vgui.Create("DPanel", parent)
	frame:Dock(FILL)
	frame:DockMargin(24, 18, 24, 18)
	frame.Paint = function() end
	frame.PDCitySelectedKind = nil -- "activity" or "npc" - read by both code-response net receivers, below
	frame.PDCitySelectedID = nil
	activePage = frame

	local sidebar = vgui.Create("DPanel", frame)
	sidebar:Dock(LEFT)
	sidebar:SetWide(260)
	sidebar:DockPadding(8, 44, 8, 8)
	sidebar.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel)
		draw.SimpleText("Developer Console", "PDCity_Heading", 16, 24, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	-- Before the editor: a BOTTOM dock must come before the FILL one.
	local console = PDCity.BuildMessageConsole(frame)
	console:DockMargin(16, 12, 0, 0)

	local list = vgui.Create("DScrollPanel", sidebar)
	list:Dock(FILL)
	PDCity.ApplyFastScroll(list)

	local editorHolder = vgui.Create("DPanel", frame)
	editorHolder:Dock(FILL)
	editorHolder:DockMargin(16, 0, 0, 0)
	editorHolder.Paint = function(self, w, h) draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel) end
	PDCity.RegisterPickerHost(editorHolder)

	local headerRow = vgui.Create("DPanel", editorHolder)
	headerRow:Dock(TOP)
	headerRow:SetTall(26)
	headerRow:DockMargin(10, 8, 10, 0)
	headerRow.Paint = function() end

	local nameLabel = vgui.Create("DLabel", headerRow)
	nameLabel:Dock(FILL)
	nameLabel:SetFont("PDCity_Heading")
	nameLabel:SetText("Pick something on the left")
	nameLabel:SetTextColor(PDCity.THEME.Text)

	local findEntityBtn = vgui.Create("DButton", headerRow)
	findEntityBtn:Dock(RIGHT)
	findEntityBtn:SetWide(120)
	PDCity.StyleButton(findEntityBtn, "Find Entity...", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	findEntityBtn.DoClick = function() OpenEntityLookup() end

	local hint = vgui.Create("DLabel", editorHolder)
	hint:Dock(TOP)
	hint:SetTall(46)
	hint:DockMargin(10, 2, 10, 0)
	hint:SetFont("PDCity_Small")
	hint:SetWrap(true)
	hint:SetText("Activities: runs when the trigger fires, receives (ent, player, activity). Custom NPCs: runs when the NPC is used, receives (ent, player, npc). Either way, use \"local a, b, c = ...\" to name them. A mistake here only errors this one trigger, not the rest of the gamemode.")
	hint:SetTextColor(PDCity.THEME.TextDim)

	local codeEntry = vgui.Create("DTextEntry", editorHolder)
	codeEntry:Dock(FILL)
	codeEntry:DockMargin(10, 6, 10, 6)
	codeEntry:SetMultiline(true)
	codeEntry:SetFont("DermaDefault")
	codeEntry:SetEnabled(false)
	codeEntry:SetPlaceholderText("-- Pick an activity or NPC first")
	frame.PDCityCodeEntry = codeEntry -- read/written by the net receivers, below

	local statusLabel = vgui.Create("DLabel", editorHolder)
	statusLabel:Dock(BOTTOM)
	statusLabel:SetTall(20)
	statusLabel:DockMargin(10, 0, 10, 4)
	statusLabel:SetFont("PDCity_Small")
	statusLabel:SetText("")
	statusLabel:SetTextColor(PDCity.THEME.TextDim)
	frame.PDCityStatusLabel = statusLabel

	local saveBtn = vgui.Create("DButton", editorHolder)
	saveBtn:Dock(BOTTOM)
	saveBtn:SetTall(28)
	saveBtn:DockMargin(10, 0, 10, 6)
	saveBtn:SetEnabled(false)
	PDCity.StyleButton(saveBtn, "Save Code")
	saveBtn.DoClick = function()
		if not frame.PDCitySelectedID then return end
		statusLabel:SetText("Saving...")
		statusLabel:SetTextColor(PDCity.THEME.TextDim)
		SendAction(frame.PDCitySelectedKind, "set_code", { ID = frame.PDCitySelectedID, Code = codeEntry:GetValue() })
	end
	frame.PDCitySaveBtn = saveBtn

	local rowButtons = {}

	local function SelectItem(kind, id, name)
		frame.PDCitySelectedKind = kind
		frame.PDCitySelectedID = id
		nameLabel:SetText(name .. (kind == "npc" and "  (NPC)" or ""))
		codeEntry:SetEnabled(true)
		codeEntry:SetValue("-- Loading...")
		saveBtn:SetEnabled(true)
		statusLabel:SetText("")

		for key, btn in pairs(rowButtons) do
			btn.Active = (key == kind .. "_" .. id)
		end

		SendAction(kind, "get_code", { ID = id })
	end

	local function AddRow(kind, id, name, subtitle)
		local btn = vgui.Create("DButton", list)
		btn:Dock(TOP)
		btn:SetTall(40)
		btn:DockMargin(0, 0, 4, 4)
		btn:SetText("")
		btn.Active = (frame.PDCitySelectedKind == kind and frame.PDCitySelectedID == id)
		btn.Paint = function(self, w, h)
			draw.RoundedBox(5, 0, 0, w, h, self.Active and PDCity.THEME.Accent or (self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel))
			draw.SimpleText((kind == "npc" and "[NPC] " or "") .. name, "PDCity_Small", 8, 10, PDCity.THEME.Text, TEXT_ALIGN_LEFT)
			draw.SimpleText(subtitle, "PDCity_Small", 8, 24, PDCity.THEME.TextDim, TEXT_ALIGN_LEFT)
		end
		btn.DoClick = function() SelectItem(kind, id, name) end
		rowButtons[kind .. "_" .. id] = btn
	end

	local function RefreshList()
		list:Clear()
		rowButtons = {}

		for _, activity in ipairs(PDCity.ACTIVITIES or {}) do
			AddRow("activity", activity.ID, activity.Name, activity.Class .. (activity.HasCode and "  [has code]" or ""))
		end

		for _, npc in ipairs(PDCity.CUSTOM_NPCS or {}) do
			AddRow("npc", npc.ID, npc.Name, "Custom NPC" .. (npc.HasCode and "  [has code]" or ""))
		end

		if #(PDCity.ACTIVITIES or {}) == 0 and #(PDCity.CUSTOM_NPCS or {}) == 0 then
			local empty = vgui.Create("DLabel", list)
			empty:Dock(TOP)
			empty:SetTall(50)
			empty:SetFont("PDCity_Small")
			empty:SetWrap(true)
			empty:SetText("Nothing yet - the owner creates Activities or NPCs from the F4 admin editor first.")
			empty:SetTextColor(PDCity.THEME.TextDim)
		end
	end
	RefreshList()

	-- Keyed on the panel, so the hooks remove themselves when F1 closes.
	hook.Add("PDCity_ActivityCatalogueUpdated", frame, function() RefreshList() end)
	hook.Add("PDCity_CustomNPCCatalogueUpdated", frame, function() RefreshList() end)

	return frame

end

-- "!devcode" (core/sv_activities.lua, developer-gated there).
net.Receive("pdcity_devconsole_open", function()
	PDCity.OpenF1Menu("Developer Console")
end)

-- Response to "get_code" - lands on the frame regardless of what's
-- selected BY THE TIME it arrives, so it's dropped unless it's still an
-- answer for the currently-selected item (both kind and ID have to
-- match - clicking a different activity or NPC while a slow response is
-- in flight shouldn't let a stale reply overwrite it).
local function HandleCodeResponse(kind)
	local id = net.ReadUInt(32)
	local code = net.ReadString()

	local frame = activePage
	if not IsValid(frame) or frame.PDCitySelectedKind ~= kind or frame.PDCitySelectedID ~= id then return end

	if IsValid(frame.PDCityCodeEntry) then
		frame.PDCityCodeEntry:SetValue(code)
	end
end

net.Receive("pdcity_activity_code", function() HandleCodeResponse("activity") end)
net.Receive("pdcity_customnpc_code", function() HandleCodeResponse("npc") end)

-- Response to "set_code" (success or a compile error) - core/sv_activities.lua
-- and core/sv_npc_classes.lua each send their own dedicated result
-- message rather than something parsed out of a generic chat toast.
local function HandleSetCodeResult()
	local ok = net.ReadBool()
	local err = net.ReadString()

	local frame = activePage
	if not IsValid(frame) or not IsValid(frame.PDCityStatusLabel) then return end

	if ok then
		frame.PDCityStatusLabel:SetText("Saved.")
		frame.PDCityStatusLabel:SetTextColor(PDCity.THEME.AccentDim)
	else
		frame.PDCityStatusLabel:SetText(err)
		frame.PDCityStatusLabel:SetTextColor(Color(230, 100, 100))
	end
end

net.Receive("pdcity_activity_setcode_result", HandleSetCodeResult)
net.Receive("pdcity_customnpc_setcode_result", HandleSetCodeResult)
