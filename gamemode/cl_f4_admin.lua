--[[---------------------------------------------------------
	Owner-only F4 catalogue editor. Lets the owner (core/sh_permissions.lua's
	PDCity.IsOwner) add/remove/reorder both the custom entities and the
	subsections shown on the F4 menu's Entities page (cl_f4_menu.lua),
	without editing any Lua files or restarting the server.

	Every change is sent to the server as a single "pdcity_f4_admin" net
	message (see core/sv_f4_catalogue.lua for the actual validation and
	persistence - this file only builds the form and re-syncs from
	whatever the server broadcasts back).
-----------------------------------------------------------]]

net.Receive("pdcity_f4_sync", function()
	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	if istable(data.Sections) and #data.Sections > 0 then
		PDCity.F4_SECTIONS = data.Sections
	end

	if istable(data.Entities) then
		PDCity.F4_CUSTOM_ENTITIES = data.Entities
	end

	if istable(data.Overrides) then
		PDCity.F4_ENTITY_OVERRIDES = data.Overrides
	end

	hook.Run("PDCity_F4CatalogueUpdated")
end)

net.Receive("pdcity_job_sync", function()
	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	if istable(data.Sections) and #data.Sections > 0 then
		PDCity.SECTIONS = data.Sections
	end

	if istable(data.Jobs) then
		local jobs = {}
		for idStr, job in pairs(data.Jobs) do
			jobs[tonumber(idStr)] = job
		end
		PDCity.CUSTOM_JOBS = jobs
	end

	if istable(data.Overrides) then
		local overrides = {}
		for idStr, override in pairs(data.Overrides) do
			overrides[tonumber(idStr)] = override
		end
		PDCity.JOB_OVERRIDES = overrides
		-- Every merged PDCity.GetJob(id) result cached before this sync
		-- landed is now stale.
		for id in pairs(PDCity.JOBS) do
			PDCity.InvalidateJobCache(id)
		end
	end

	if istable(data.WhitelistOnlySections) then
		PDCity.SECTION_WHITELIST_ONLY = data.WhitelistOnlySections
	end

	-- Registers the GMod team for each custom job on this client too -
	-- needed for the job's name/color to render correctly (scoreboard,
	-- F4 job cards) without waiting for a reconnect.
	PDCity.RegisterCustomJobTeams()

	hook.Run("PDCity_JobCatalogueUpdated")
end)

net.Receive("pdcity_activity_sync", function()
	local data = util.JSONToTable(net.ReadString() or "")
	if istable(data) then PDCity.ACTIVITIES = data end
	hook.Run("PDCity_ActivityCatalogueUpdated")
end)

net.Receive("pdcity_customnpc_sync", function()
	local data = util.JSONToTable(net.ReadString() or "")
	if istable(data) then PDCity.CUSTOM_NPCS = data end
	hook.Run("PDCity_CustomNPCCatalogueUpdated")
end)

local function SendAdminAction(action, payload)
	net.Start("pdcity_f4_admin")
		net.WriteString(util.TableToJSON({ Action = action, Payload = payload or {} }))
	net.SendToServer()
end

local function SendCustomNPCAdminAction(action, payload)
	net.Start("pdcity_customnpc_admin")
		net.WriteString(util.TableToJSON({ Action = action, Payload = payload or {} }))
	net.SendToServer()
end

local function SendActivityAdminAction(action, payload)
	net.Start("pdcity_activity_admin")
		net.WriteString(util.TableToJSON({ Action = action, Payload = payload or {} }))
	net.SendToServer()
end

local function SendCurrencyAdminAction(action, payload)
	net.Start("pdcity_currency_admin")
		net.WriteString(util.TableToJSON({ Action = action, Payload = payload or {} }))
	net.SendToServer()
end

local function SendJobAdminAction(action, payload)
	net.Start("pdcity_job_admin")
		net.WriteString(util.TableToJSON({ Action = action, Payload = payload or {} }))
	net.SendToServer()
end

-- Inventory whitelist (core/sv_inventory.lua) uses a flatter message
-- than the other two - one class per action, no nested payload.
local function SendInventoryAdminAction(action, class)
	net.Start("pdcity_inv_admin")
		net.WriteString(util.TableToJSON({ Action = action, Class = class }))
	net.SendToServer()
end

-- Same flat shape, for the physgun whitelist (core/sv_physgun_whitelist.lua).
local function SendPhysgunAdminAction(action, class)
	net.Start("pdcity_physgun_admin")
		net.WriteString(util.TableToJSON({ Action = action, Class = class }))
	net.SendToServer()
end

--[[---------------------------------------------------------
	All registered weapon/entity classes, for the "Entity/SWEP to add"
	search list. Built once per editor open - the registries don't
	change mid-session.
-----------------------------------------------------------]]
local function GetAllClasses()
	local list = {}

	for _, swep in pairs(weapons.GetList()) do
		local class = swep.ClassName
		if class then
			table.insert(list, { Class = class, Print = (swep.PrintName or class) .. "  [weapon]" })
		end
	end

	for class, info in pairs(scripted_ents.GetList()) do
		local printName = info.t and info.t.PrintName
		table.insert(list, { Class = class, Print = (printName or class) .. "  [entity]" })
	end

	table.sort(list, function(a, b) return a.Class < b.Class end)
	return list
end

--[[---------------------------------------------------------
	Small reusable "list with up/down/remove buttons" used by the
	entities, sections, jobs, and job-category tabs. Pass onMove as nil
	to omit the Move Up/Down buttons (jobs don't support reordering -
	see BuildJobsTab).
-----------------------------------------------------------]]
local function BuildManagedList(parent, columns, onMove, onRemove)

	local holder = vgui.Create("DPanel", parent)
	holder:Dock(FILL)
	holder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end
	holder:DockPadding(10, 10, 10, 10)

	local listView = vgui.Create("DListView", holder)
	listView:Dock(FILL)
	listView:DockMargin(0, 0, 0, 8)
	listView:SetMultiSelect(false)
	for _, col in ipairs(columns) do
		listView:AddColumn(col)
	end

	local btnRow = vgui.Create("DPanel", holder)
	btnRow:Dock(BOTTOM)
	btnRow:SetTall(30)
	btnRow.Paint = function() end

	local function SelectedRow()
		local selected = listView:GetSelected()
		return selected and selected[1]
	end

	if onMove then
		local upBtn = vgui.Create("DButton", btnRow)
		upBtn:Dock(LEFT)
		upBtn:SetWide(90)
		PDCity.StyleButton(upBtn, "Move Up", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
		upBtn.DoClick = function()
			local row = SelectedRow()
			if row then onMove(row.pdcityID, -1) end
		end

		local downBtn = vgui.Create("DButton", btnRow)
		downBtn:Dock(LEFT)
		downBtn:SetWide(90)
		downBtn:DockMargin(6, 0, 0, 0)
		PDCity.StyleButton(downBtn, "Move Down", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
		downBtn.DoClick = function()
			local row = SelectedRow()
			if row then onMove(row.pdcityID, 1) end
		end
	end

	local removeBtn = vgui.Create("DButton", btnRow)
	removeBtn:Dock(RIGHT)
	removeBtn:SetWide(90)
	PDCity.StyleButton(removeBtn, "Remove", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })
	removeBtn.DoClick = function()
		local row = SelectedRow()
		if row then onRemove(row.pdcityID) end
	end

	return listView

end

--[[---------------------------------------------------------
	Shared frame for every picker grid built into a tab (entity class,
	player model, weapon): a darker shade of the Panel colour with a thin
	border, so it reads as its own area and its tiles stand out. `headerText` (optional) adds a heading, changeable later via
	root:SetHeader(text).

	root.PDCityPopulate (set by the caller) runs once, the first time the
	area is actually on screen - so a tab's grid of model thumbnails isn't
	built until someone opens that tab.
-----------------------------------------------------------]]
-- A shade darker than the theme's Panel colour (same hue, so it suits any
-- Site Theme), so the grid sits slightly recessed into the page.
local function PickerAreaColor()
	local p = PDCity.THEME.Panel
	return Color(p.r * 0.72, p.g * 0.72, p.b * 0.72, 255)
end

local function CreatePickerArea(parent, headerText)
	local root = vgui.Create("DPanel", parent)
	root:DockPadding(10, 10, 10, 10)
	root.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Border)
		draw.RoundedBox(6, 1, 1, w - 2, h - 2, PickerAreaColor())
	end

	local header
	if headerText then
		header = vgui.Create("DLabel", root)
		header:Dock(TOP)
		header:SetTall(20)
		header:DockMargin(0, 0, 0, 6)
		header:SetFont("PDCity_Heading")
		header:SetText(headerText)
		header:SetTextColor(PDCity.THEME.Text)
	end
	root.SetHeader = function(self, text)
		if IsValid(header) then header:SetText(text) end
	end

	root.Think = function(self)
		if self.PDCityPopulate and PDCity.IsShownOnScreen(self) then
			local populate = self.PDCityPopulate
			self.PDCityPopulate = nil
			populate()
		end
	end

	return root
end

--[[---------------------------------------------------------
	Entity/weapon class picker grid - search box, filters, and a grid of
	class tiles, built into `parent` (the caller docks/sizes the returned
	panel). Built straight into the Entities and Activities tabs, so
	there's no button or pop-out there; PDCity.OpenEntityClassPicker below
	wraps it in a picker panel for places with no room for it.

	`opts.Header` (optional) is a heading shown above the search box, and
	can be changed later with root:SetHeader(text).
-----------------------------------------------------------]]
function PDCity.BuildEntityClassPicker(parent, onPick, opts)
	opts = opts or {}

	local root = CreatePickerArea(parent, opts.Header)

	local filterEntry = vgui.Create("DTextEntry", root)
	filterEntry:Dock(TOP)
	filterEntry:SetTall(26)
	filterEntry:SetPlaceholderText("Search entity/weapon classes...")

	local optionsRow = vgui.Create("DPanel", root)
	optionsRow:Dock(TOP)
	optionsRow:SetTall(20)
	optionsRow:DockMargin(0, 6, 0, 0)
	optionsRow.Paint = function() end

	-- Custom Props (core/sh_custom_props.lua, the Prop Copier tool) are
	-- unambiguously identifiable by their class prefix - nothing else on
	-- the server registers a "pdcity_customprop_<id>" class - so this
	-- needs no separate tracked list, just a pattern match against the
	-- same allClasses this picker already built.
	local onlyCustomCheck = vgui.Create("DCheckBoxLabel", optionsRow)
	onlyCustomCheck:Dock(LEFT)
	onlyCustomCheck:SetWide(190)
	onlyCustomCheck:SetText("Only entities I've made")
	onlyCustomCheck:SetTextColor(PDCity.THEME.Text)

	local modelPictureCheck = vgui.Create("DCheckBoxLabel", optionsRow)
	modelPictureCheck:Dock(FILL)
	modelPictureCheck:SetText("Real model thumbnails (slower)")
	modelPictureCheck:SetTextColor(PDCity.THEME.Text)

	local gridScroll = vgui.Create("DScrollPanel", root)
	gridScroll:Dock(FILL)
	gridScroll:DockMargin(0, 8, 0, 0)
	PDCity.ApplyFastScroll(gridScroll)

	local grid = vgui.Create("DIconLayout", gridScroll)
	grid:Dock(TOP)
	grid:SetSpaceX(4)
	grid:SetSpaceY(4)

	local allClasses = GetAllClasses()
	-- Opt-in, not forced on the whole grid, for the same reason the
	-- inline version was: a live 3D model thumbnail per entry is slower
	-- to build than an icon16, and most classes here are point/logic
	-- entities with no obvious model to show even with this on.
	local useModelPictures = false
	local onlyCustom = false

	local function RefreshGrid(filter)
		grid:Clear()
		filter = filter and filter:lower() or ""
		local shown = 0
		for _, entry in ipairs(allClasses) do
			if shown >= 150 then break end

			local matchesCustom = not onlyCustom or entry.Class:find("^pdcity_customprop_") ~= nil
			-- Checks Print (the friendly name shown in the grid/tooltip),
			-- not just Class - a Custom Prop's class is an opaque
			-- "pdcity_customprop_<id>" string (core/sh_custom_props.lua),
			-- so searching by the name actually given to it here found
			-- nothing before this, even though it was right there in the
			-- (150-capped, unfiltered) grid the whole time.
			local matchesFilter = filter == "" or entry.Class:lower():find(filter, 1, true) or entry.Print:lower():find(filter, 1, true)

			if matchesCustom and matchesFilter then
				local model = useModelPictures and PDCity.GetItemModel(entry.Class)

				if model then
					local icon = vgui.Create("SpawnIcon", grid)
					icon:SetSize(64, 64)
					icon:SetModel(model)
					icon:SetTooltip(entry.Print)
					icon.DoClick = function() onPick(entry) end
				else
					local iconPath = "entities/" .. entry.Class .. ".png"
					local mat = Material(iconPath)
					if mat:IsError() then
						mat = Material("VGUI/entities/" .. entry.Class)
					end

					local btn = vgui.Create("DButton", grid)
					btn:SetSize(64, 64)
					btn:SetText("")
					btn:SetTooltip(entry.Print)
					btn.Paint = function(self, w, h)
						draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
						if not mat:IsError() then
							surface.SetDrawColor(255, 255, 255, 255)
							surface.SetMaterial(mat)
							surface.DrawTexturedRect(4, 4, w - 8, h - 20)
						end
						draw.SimpleText(entry.Class, "DermaDefault", w / 2, h - 8, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
					end
					btn.DoClick = function() onPick(entry) end
				end
				shown = shown + 1
			end
		end
	end
	root.PDCityPopulate = function() RefreshGrid("") end

	filterEntry.OnValueChange = function(self, val) RefreshGrid(val) end
	onlyCustomCheck.OnChange = function(self, checked)
		onlyCustom = checked
		RefreshGrid(filterEntry:GetValue())
	end
	modelPictureCheck.OnChange = function(self, checked)
		useModelPictures = checked
		RefreshGrid(filterEntry:GetValue())
	end

	return root

end

-- Global - cl_flow_editor.lua's Give Item/Spawn Entity node fields use
-- this, since its own window has no room for the grid built in.
function PDCity.OpenEntityClassPicker(onPick)
	local card = PDCity.OpenPicker("Choose an Entity/Weapon Class", 560, 520)
	card:DockPadding(8, 54, 8, 8)

	local picker = PDCity.BuildEntityClassPicker(card, function(entry)
		onPick(entry)
		card:Close()
	end)
	picker:Dock(FILL)
end

--[[---------------------------------------------------------
	Sections popup - the subsections shown on the F4 menu's Entities page
	(cl_f4_menu.lua) exist purely to group entries within that same page,
	so this is opened from a button on the Entities tab below (its
	"Manage Sections..." next to the subsection dropdown it feeds) rather
	than living as its own separate top-level sidebar tab - same pop-out-
	window treatment as the other pickers.

	Self-refreshes via the same "PDCity_F4CatalogueUpdated" hook the main
	admin frame uses (fired on every server sync, including this popup's
	own add/remove/reorder actions) - removed again on close so it doesn't
	keep firing into a panel that no longer exists.
-----------------------------------------------------------]]
local function OpenSectionsManager()

	local frame = PDCity.OpenPicker("Manage Sections", 420, 480)
	frame.OnRemove = function()
		hook.Remove("PDCity_F4CatalogueUpdated", frame)
	end

	local top = 48

	local root = vgui.Create("DPanel", frame)
	root:SetPos(16, top)
	root:SetSize(388, frame:GetTall() - top - 16)
	root.Paint = function() end

	local addRow = vgui.Create("DPanel", root)
	addRow:Dock(TOP)
	addRow:SetTall(30)
	addRow:DockMargin(0, 0, 0, 8)
	addRow.Paint = function() end

	local nameEntry = vgui.Create("DTextEntry", addRow)
	nameEntry:Dock(FILL)
	nameEntry:DockMargin(0, 0, 6, 0)
	nameEntry:SetPlaceholderText("New subsection name")

	local addBtn = vgui.Create("DButton", addRow)
	addBtn:Dock(RIGHT)
	addBtn:SetWide(100)
	PDCity.StyleButton(addBtn, "Add Section")
	addBtn.DoClick = function()
		local name = nameEntry:GetValue()
		if name == "" then return end
		SendAdminAction("add_section", { Name = name })
		nameEntry:SetValue("")
	end

	local listView = BuildManagedList(root, { "Section" },
		function(id, dir)
			local order = table.Copy(PDCity.F4_SECTIONS)

			local from
			for i, name in ipairs(order) do
				if name == id then from = i break end
			end
			if not from then return end

			local to = from + dir
			if to < 1 or to > #order then return end

			order[from], order[to] = order[to], order[from]
			SendAdminAction("reorder_sections", { Order = order })
		end,
		function(id)
			SendAdminAction("remove_section", { Name = id })
		end
	)

	local function RefreshSectionList()
		listView:Clear()
		for _, name in ipairs(PDCity.F4_SECTIONS) do
			local line = listView:AddLine(name)
			line.pdcityID = name
		end
	end
	RefreshSectionList()

	hook.Add("PDCity_F4CatalogueUpdated", frame, RefreshSectionList)

end

local function BuildEntitiesTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	-- Left/right split instead of stacking the form on top of the entity
	-- list - same reasoning as the Jobs tab's identical split: a fixed-
	-- height form competing with the list and "Removed built-in items"
	-- panel for the same vertical space could starve them both, and a
	-- form stretched across the FULL width for just a few narrow fields
	-- wasted the width a responsive frame now actually has.
	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(620)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	-- Scrollable canvas inside, so the form can never overlap/clip itself
	-- no matter how much this grows later - it just scrolls instead.
	local formHolder = vgui.Create("DPanel", leftPane)
	formHolder:Dock(TOP)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(10, 10, 10, 10)

	-- Sized to fit the form's contents, leaving the rest of the column to
	-- the class grid and the Add/Cancel bar below (the grid never gets
	-- less than MIN_GRID_TALL).
	local MIN_GRID_TALL = 220
	local SUBMIT_BAR_TALL = 42 -- bar height + its top margin
	formHolder.Think = function(self)
		local wanted = math.min(form:GetCanvas():GetTall() + 20, leftPane:GetTall() - MIN_GRID_TALL - SUBMIT_BAR_TALL)
		if wanted > 0 and math.abs(self:GetTall() - wanted) > 1 then self:SetTall(wanted) end
	end

	local selectedClass = nil

	local nameEntry -- forward declared, filled in by the class picker below
	local selectedLabel -- forward declared, filled in by the class picker below
	local modelEntry, modelPreview -- forward declared, filled in by the class picker below
	local iconEntry, iconPreview -- forward declared, filled in below (used when no model is set)
	local whitelistCheck -- forward declared, filled in below

	local function OnClassPicked(entry)
		selectedClass = entry.Class
		selectedLabel:SetText("Selected class: " .. selectedClass)
		if nameEntry and nameEntry:GetValue() == "" then
			nameEntry:SetValue(PDCity.PrettifyClassName(selectedClass))
		end
		-- Reflects whatever the CURRENT whitelist state already is for
		-- this class - purely informational until submit, which only
		-- ever adds (see whitelistCheck's own creation comment below).
		if whitelistCheck then
			whitelistCheck:SetChecked(PDCity.CanStoreItem(selectedClass))
		end
		-- Best-effort auto-fill, same lookup the shop card itself falls
		-- back to (PDCity.GetItemModel) - only overwrites an EMPTY model
		-- box, never clobbers one already set/edited by hand.
		if modelEntry and modelEntry:GetValue() == "" then
			local model = PDCity.GetItemModel(selectedClass)
			if model then
				modelEntry:SetValue(model)
				modelPreview:SetModel(model)
			end
		end
	end

	-- Add/Cancel live under the class grid (created further down) - this
	-- bar is docked first since a BOTTOM dock must come before the FILL one.
	local submitBar = vgui.Create("DPanel", leftPane)
	submitBar:Dock(BOTTOM)
	submitBar:SetTall(30)
	submitBar:DockMargin(0, 12, 0, 0)
	submitBar.Paint = function() end

	local classPicker = PDCity.BuildEntityClassPicker(leftPane, OnClassPicked, { Header = "Entity / Weapon Class" })
	classPicker:Dock(FILL)
	classPicker:DockMargin(0, 12, 0, 0)

	selectedLabel = vgui.Create("DLabel", form)
	selectedLabel:Dock(TOP)
	selectedLabel:SetTall(20)
	selectedLabel:SetText("Selected class: (none) - pick one from the grid below")
	selectedLabel:SetTextColor(PDCity.THEME.TextDim)

	local row1 = vgui.Create("DPanel", form)
	row1:Dock(TOP)
	row1:SetTall(26)
	row1:DockMargin(0, 4, 0, 0)
	row1.Paint = function() end

	nameEntry = vgui.Create("DTextEntry", row1)
	nameEntry:Dock(LEFT)
	nameEntry:SetWide(220)
	nameEntry:SetPlaceholderText("Display name")

	local priceEntry = vgui.Create("DTextEntry", row1)
	priceEntry:Dock(RIGHT)
	priceEntry:SetWide(120)
	priceEntry:SetNumeric(true)
	priceEntry:SetPlaceholderText("Price ($)")
	-- SetNumeric still allows a decimal point / minus sign; strip
	-- anything that isn't a plain digit so only whole numbers land here.
	priceEntry.OnValueChange = function(self, val)
		local cleaned = val:gsub("[^%d]", "")
		if cleaned ~= val then
			self:SetText(cleaned)
			self:SetCaretPos(#cleaned)
		end
	end

	--[[-----------------------------------------------------
		Model shown on the F4 shop card (cl_f4_menu.lua's BuildEntityCard) -
		auto-filled from the class's own model (PDCity.GetItemModel,
		core/sh_inventory.lua) when picking a class above resolves one, but
		that's only best-effort: a SENT that sets its model in Initialize()
		rather than a static ENT.Model (several of this gamemode's own
		entities do) has nothing to auto-detect, and shows its icon16
		instead until a model is set here manually.
	-------------------------------------------------------]]
	local modelRow = vgui.Create("DPanel", form)
	modelRow:Dock(TOP)
	modelRow:SetTall(54)
	modelRow:DockMargin(0, 6, 0, 0)
	modelRow.Paint = function() end

	modelPreview = vgui.Create("SpawnIcon", modelRow)
	modelPreview:Dock(LEFT)
	modelPreview:SetWide(54)

	modelEntry = vgui.Create("DTextEntry", modelRow)
	modelEntry:Dock(FILL)
	modelEntry:DockMargin(6, 14, 0, 14)
	modelEntry:SetPlaceholderText("Model shown on the shop card (auto-filled if available)")
	modelEntry.OnValueChange = function(self, val)
		modelPreview:SetModel(val)
	end

	--[[-----------------------------------------------------
		Fallback icon, used ONLY when no model is set above
		(cl_f4_menu.lua's BuildEntityCard already prefers the model over
		this whenever both are present). Accepts either a silkicon-style
		local path ("icon16/whatever.png") or a pasted http(s) image URL -
		there's no real file upload from a GMod client, so a URL is the
		practical equivalent of "upload an image" here; PDCity.GetIconMaterial
		(cl_theme.lua) fetches and caches it to disk the first time it's seen.
	-------------------------------------------------------]]
	local iconRow = vgui.Create("DPanel", form)
	iconRow:Dock(TOP)
	iconRow:SetTall(54)
	iconRow:DockMargin(0, 6, 0, 0)
	iconRow.Paint = function() end

	local iconPreviewHolder = vgui.Create("DPanel", iconRow)
	iconPreviewHolder:Dock(LEFT)
	iconPreviewHolder:SetWide(54)
	iconPreviewHolder.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.TitleBar)
		local mat = iconEntry and iconEntry:GetValue() ~= "" and PDCity.GetIconMaterial(iconEntry:GetValue())
		if mat and not mat:IsError() then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(mat)
			surface.DrawTexturedRect(w / 2 - 16, h / 2 - 16, 32, 32)
		end
	end

	iconEntry = vgui.Create("DTextEntry", iconRow)
	iconEntry:Dock(FILL)
	iconEntry:DockMargin(6, 14, 0, 14)
	iconEntry:SetPlaceholderText("Fallback icon if no model is set - silkicon path or an image URL")

	-- Same convenience the Jobs tab's weapon picker offers (core/sh_inventory.lua's
	-- PDCity.INVENTORY_ALLOWED, otherwise only manageable via the
	-- separate "Inventory Items" tab) - one less trip to a different tab
	-- for the common case of "add this to the shop AND let people pick
	-- it up into their inventory". Only ever ADDS on submit (never
	-- removes on uncheck) - unchecking something that was already
	-- whitelisted leaves it whitelisted; use the Inventory Items tab to
	-- actually remove one.
	whitelistCheck = vgui.Create("DCheckBoxLabel", form)
	whitelistCheck:Dock(TOP)
	whitelistCheck:SetTall(20)
	whitelistCheck:DockMargin(0, 6, 0, 0)
	whitelistCheck:SetText("Whitelist this class for inventory pickup?")
	whitelistCheck:SetTextColor(PDCity.THEME.Text)

	local row2 = vgui.Create("DPanel", form)
	row2:Dock(TOP)
	row2:SetTall(26)
	row2:DockMargin(0, 6, 0, 0)
	row2.Paint = function() end

	local subsectionCombo = vgui.Create("DComboBox", row2)
	subsectionCombo:Dock(LEFT)
	subsectionCombo:SetWide(180)
	local function RefreshSubsectionCombo()
		subsectionCombo:Clear()
		for _, name in ipairs(PDCity.F4_SECTIONS) do
			subsectionCombo:AddChoice(name)
		end
		if PDCity.F4_SECTIONS[1] then subsectionCombo:ChooseOptionID(1) end
	end
	RefreshSubsectionCombo()

	-- Sections only exist to group entries on this same page (see
	-- OpenSectionsManager's own header comment) - managed from here
	-- rather than as a separate top-level tab.
	local manageSectionsBtn = vgui.Create("DButton", row2)
	manageSectionsBtn:Dock(LEFT)
	manageSectionsBtn:SetWide(120)
	manageSectionsBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(manageSectionsBtn, "Manage Sections...", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	manageSectionsBtn.DoClick = function() OpenSectionsManager() end

	local rankCombo = vgui.Create("DComboBox", row2)
	rankCombo:Dock(RIGHT)
	rankCombo:SetWide(140)
	rankCombo:AddChoice("Normal", "normal")
	rankCombo:AddChoice("Supporter", "supporter")
	rankCombo:AddChoice("GOAT", "goat")
	rankCombo:ChooseOptionID(1)

	-- Turns this entry into a shipment: buying it drops a crate holding
	-- this many, instead of the item itself (ent_pdcity_shipment).
	local row3 = vgui.Create("DPanel", form)
	row3:Dock(TOP)
	row3:SetTall(26)
	row3:DockMargin(0, 6, 0, 0)
	row3.Paint = function() end

	local shipmentLabel = vgui.Create("DLabel", row3)
	shipmentLabel:Dock(LEFT)
	shipmentLabel:SetWide(210)
	shipmentLabel:SetText("Sell as a shipment crate of:")
	shipmentLabel:SetTextColor(PDCity.THEME.TextDim)

	local shipmentEntry = vgui.Create("DTextEntry", row3)
	shipmentEntry:Dock(LEFT)
	shipmentEntry:SetWide(110)
	shipmentEntry:SetNumeric(true)
	shipmentEntry:SetPlaceholderText("blank/1 = single")
	shipmentEntry.OnValueChange = function(self, val)
		local cleaned = val:gsub("[^%d]", "")
		if cleaned ~= val then
			self:SetText(cleaned)
			self:SetCaretPos(#cleaned)
		end
	end

	local jobsLabel = vgui.Create("DLabel", form)
	jobsLabel:Dock(TOP)
	jobsLabel:SetTall(18)
	jobsLabel:DockMargin(0, 8, 0, 0)
	jobsLabel:SetText("Job roles allowed to buy (none checked = everyone):")
	jobsLabel:SetTextColor(PDCity.THEME.TextDim)

	local jobsScroll = vgui.Create("DScrollPanel", form)
	jobsScroll:Dock(TOP)
	jobsScroll:SetTall(110)
	jobsScroll:DockMargin(0, 4, 0, 0)

	local jobCheckboxes = {}
	for _, id in ipairs(PDCity.GetSortedJobIDs()) do
		local job = PDCity.GetJob(id)
		if job then
			local chk = vgui.Create("DCheckBoxLabel", jobsScroll)
			chk:SetText(job.Name)
			chk:Dock(TOP)
			chk:DockMargin(2, 2, 0, 0)
			chk:SetTextColor(PDCity.THEME.Text)
			jobCheckboxes[id] = chk
		end
	end

	-- Set while an existing entity is loaded into the form for editing
	-- (clicking its row in the list below) - nil means the form is
	-- building a brand new entity. Same pattern as the Jobs tab's
	-- editingJobID/editingBuiltin.
	local editingID = nil
	local editingBuiltin = false -- true when editingID points at a PDCity.F4_ENTITIES entry, not a custom one

	local function IsBuiltinEntity(id)
		for _, cfg in ipairs(PDCity.F4_ENTITIES) do
			if cfg.ID == id then return true end
		end
		return false
	end

	local cancelEditBtn = vgui.Create("DButton", submitBar)
	cancelEditBtn:Dock(RIGHT)
	cancelEditBtn:SetWide(260)
	cancelEditBtn:DockMargin(8, 0, 0, 0)
	PDCity.StyleButton(cancelEditBtn, "Cancel Edit (Start a New Entity Instead)", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelEditBtn:SetVisible(false)

	local addBtn = vgui.Create("DButton", submitBar)
	addBtn:Dock(FILL)
	local addBtnLabel = "Add Entity"
	PDCity.StyleButton(addBtn, addBtnLabel)

	local function ResetForm()
		editingID = nil
		editingBuiltin = false
		selectedClass = nil
		selectedLabel:SetText("Selected class: (none) - pick one from the grid below")
		nameEntry:SetValue("")
		priceEntry:SetValue("")
		shipmentEntry:SetValue("")
		modelEntry:SetValue("")
		modelPreview:SetModel("")
		iconEntry:SetValue("")
		whitelistCheck:SetChecked(false)
		for _, chk in pairs(jobCheckboxes) do chk:SetChecked(false) end
		addBtnLabel = "Add Entity"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(false)
	end

	cancelEditBtn.DoClick = ResetForm

	addBtn.DoClick = function()
		if not selectedClass then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Pick a class from the grid first.")
			return
		end

		local price = tonumber(priceEntry:GetValue())
		if not price or price < 0 then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Price must be a whole number, 0 or more.")
			return
		end

		if whitelistCheck:GetChecked() then
			SendInventoryAdminAction("add", selectedClass)
		end

		local jobs = {}
		for id, chk in pairs(jobCheckboxes) do
			if chk:GetChecked() then table.insert(jobs, id) end
		end

		local payload = {
			Class = selectedClass,
			Name = nameEntry:GetValue() ~= "" and nameEntry:GetValue() or PDCity.PrettifyClassName(selectedClass),
			Model = modelEntry:GetValue() ~= "" and modelEntry:GetValue() or nil,
			Icon = iconEntry:GetValue() ~= "" and iconEntry:GetValue() or nil,
			Subsection = subsectionCombo:GetSelected() or PDCity.F4_SECTIONS[1],
			Rank = select(2, rankCombo:GetSelected()) or "normal",
			Price = math.floor(price),
			Jobs = #jobs > 0 and jobs or nil,
			ShipmentCount = math.floor(tonumber(shipmentEntry:GetValue()) or 0),
		}

		if editingID then
			payload.ID = editingID
			SendAdminAction(editingBuiltin and "edit_builtin_entity" or "edit_entity", payload)
		else
			SendAdminAction("add_entity", payload)
		end

		ResetForm()
	end

	--[[-----------------------------------------------------
		Removed built-in items - Money Printer (or anything else hardcoded
		later) taken out via the Remove button below still
		exist in code, just hidden (core/sh_f4_entities.lua's Removed
		override flag) - listed here so there's a way back without a
		console command. Only visible at all when something actually is
		removed.

		Created (and Dock(BOTTOM)'d) BEFORE the main entity list below -
		GMod's docking allocates space in DOCK ORDER, not creation order
		vs. Dock type: a FILL panel docked first claims everything still
		available at that point, leaving nothing for a BOTTOM panel
		docked afterward - this has to reserve its slice of `root` before
		the FILL list gets a chance to take all of it.
	-------------------------------------------------------]]
	local removedHolder = vgui.Create("DPanel", rightPane)
	removedHolder:Dock(BOTTOM)
	removedHolder:SetTall(140)
	removedHolder:DockMargin(0, 8, 0, 0)
	removedHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end
	removedHolder:SetVisible(false)

	local removedLabel = vgui.Create("DLabel", removedHolder)
	removedLabel:Dock(TOP)
	removedLabel:SetTall(20)
	removedLabel:DockMargin(8, 6, 8, 0)
	removedLabel:SetFont("PDCity_Small")
	removedLabel:SetTextColor(PDCity.THEME.TextDim)
	removedLabel:SetText("Removed built-in items:")

	local restoreBtn = vgui.Create("DButton", removedHolder)
	restoreBtn:Dock(BOTTOM)
	restoreBtn:SetTall(24)
	restoreBtn:DockMargin(8, 4, 8, 6)
	PDCity.StyleButton(restoreBtn, "Restore Selected")

	local removedList = vgui.Create("DListView", removedHolder)
	removedList:Dock(FILL)
	removedList:DockMargin(8, 4, 8, 0)
	removedList:SetMultiSelect(false)
	removedList:AddColumn("Name")
	removedList:AddColumn("Class")

	restoreBtn.DoClick = function()
		local selected = removedList:GetSelected()
		local row = selected and selected[1]
		if not row then return end
		SendAdminAction("restore_builtin_entity", { ID = row.pdcityID })
	end

	local function RefreshRemovedList()
		removedList:Clear()
		local removed = PDCity.GetRemovedBuiltinF4Entities()
		for _, cfg in ipairs(removed) do
			local line = removedList:AddLine(cfg.Name, cfg.Class)
			line.pdcityID = cfg.ID
		end
		removedHolder:SetVisible(#removed > 0)
	end

	-- Move Up/Down only ever reorders custom entries (built-in ones have
	-- no configurable position - they were never orderable before this
	-- tab could show them at all) - a no-op if the selected row is one.
	local listView = BuildManagedList(rightPane, { "Name", "Class", "Subsection", "Price", "Shipment" },
		function(id, dir)
			if IsBuiltinEntity(id) then return end

			local order = {}
			for i, cfg in ipairs(PDCity.F4_CUSTOM_ENTITIES) do order[i] = cfg.ID end

			local from
			for i, existingID in ipairs(order) do
				if existingID == id then from = i break end
			end
			if not from then return end

			local to = from + dir
			if to < 1 or to > #order then return end

			order[from], order[to] = order[to], order[from]
			SendAdminAction("reorder_entities", { Order = order })
		end,
		function(id)
			if editingID == id then ResetForm() end
			if IsBuiltinEntity(id) then
				SendAdminAction("remove_builtin_entity", { ID = id })
			else
				SendAdminAction("remove_entity", { ID = id })
			end
		end
	)

	-- Clicking a row loads that entity back into the form above for
	-- editing rather than adding a new one - addBtn (relabelled) then
	-- sends edit_entity/edit_builtin_entity instead of add_entity. Same
	-- pattern as the Jobs tab's listView.OnRowSelected. Uses
	-- PDCity.GetF4Entity so a built-in entity's CURRENT (possibly already
	-- overridden) values load, not always its original hardcoded ones.
	listView.OnRowSelected = function(self, index, row)
		local cfg = PDCity.GetF4Entity(row.pdcityID)
		if not cfg then return end

		editingID = cfg.ID
		editingBuiltin = IsBuiltinEntity(cfg.ID)
		selectedClass = cfg.Class
		selectedLabel:SetText("Selected class: " .. cfg.Class .. (editingBuiltin and "  (fixed - built-in entity)" or ""))
		nameEntry:SetValue(cfg.Name or "")
		priceEntry:SetValue(tostring(cfg.Price or 0))
		shipmentEntry:SetValue(cfg.ShipmentCount and tostring(cfg.ShipmentCount) or "")
		modelEntry:SetValue(cfg.Model or "")
		modelPreview:SetModel(cfg.Model or "")
		-- "icon16/box.png" is the server's own generic default
		-- (core/sv_f4_catalogue.lua) for an entity that never had a custom
		-- one set - shown as blank/placeholder here rather than as if it
		-- were a deliberately-chosen icon.
		iconEntry:SetValue((cfg.Icon and cfg.Icon ~= "icon16/box.png") and cfg.Icon or "")
		whitelistCheck:SetChecked(PDCity.CanStoreItem(cfg.Class))

		for i, name in ipairs(PDCity.F4_SECTIONS) do
			if name == cfg.Subsection then
				subsectionCombo:ChooseOptionID(i)
				break
			end
		end

		-- Added in this fixed order below (Normal/Supporter/GOAT = IDs 1-3) -
		-- DComboBox has no public getter for an option's data by value, so
		-- matching against that fixed order is simpler than round-tripping
		-- through GetOptionText.
		local RANK_TO_ID = { normal = 1, supporter = 2, goat = 3 }
		rankCombo:ChooseOptionID(RANK_TO_ID[cfg.Rank or "normal"] or 1)

		local wanted = {}
		for _, id in ipairs(cfg.Jobs or {}) do wanted[id] = true end
		for id, chk in pairs(jobCheckboxes) do
			chk:SetChecked(wanted[id] == true)
		end

		addBtnLabel = "Save Changes"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(true)
	end

	local function RefreshEntityList()
		listView:Clear()
		for _, cfg in ipairs(PDCity.GetAllF4Entities()) do
			local line = listView:AddLine(cfg.Name, cfg.Class, cfg.Subsection or "General", "$" .. (cfg.Price or 0),
				cfg.ShipmentCount and ("x" .. cfg.ShipmentCount) or "-")
			line.pdcityID = cfg.ID
		end
		RefreshSubsectionCombo()
		RefreshRemovedList()
	end
	RefreshEntityList()

	root.PDCityRefresh = function()
		RefreshEntityList()
	end

	return root

end

--[[---------------------------------------------------------
	Weapon picker grid, built into the Jobs tab's picker column: a grid of
	weapon thumbnails, a filter box, an optional per-weapon nickname
	(shown instead of the raw class name wherever a job's loadout is
	displayed), and a checkbox that also whitelists the weapon for
	inventory pickup (core/sh_inventory.lua's PDCity.INVENTORY_ALLOWED -
	the same list the "Inventory Items" tab manages) - one less trip to a
	different tab for "give this job a gun AND let people pick it up".

	onAdd(class, nickname) is called once per confirmed weapon.
-----------------------------------------------------------]]
local function BuildWeaponPicker(parent, onAdd, opts)
	opts = opts or {}

	local root = CreatePickerArea(parent, opts.Header)
	local selectedClass

	local filterEntry = vgui.Create("DTextEntry", root)
	filterEntry:Dock(TOP)
	filterEntry:SetTall(26)
	filterEntry:SetPlaceholderText("Filter weapons...")

	-- The confirm section is docked BOTTOM up (lowest first), all before
	-- the grid's FILL dock.
	local confirmBtn = vgui.Create("DButton", root)
	confirmBtn:Dock(BOTTOM)
	confirmBtn:SetTall(28)
	confirmBtn:DockMargin(0, 6, 0, 0)
	PDCity.StyleButton(confirmBtn, "Add Weapon to Job")

	local nicknameEntry = vgui.Create("DTextEntry", root)
	nicknameEntry:Dock(BOTTOM)
	nicknameEntry:SetTall(26)
	nicknameEntry:DockMargin(0, 6, 0, 0)
	nicknameEntry:SetPlaceholderText("Nickname shown on the job's weapon list (optional)")

	local whitelistCheck = vgui.Create("DCheckBoxLabel", root)
	whitelistCheck:Dock(BOTTOM)
	whitelistCheck:SetTall(20)
	whitelistCheck:DockMargin(0, 6, 0, 0)
	whitelistCheck:SetText("Whitelist for inventory pickup?")
	whitelistCheck:SetTextColor(PDCity.THEME.Text)

	local selectedLabel = vgui.Create("DLabel", root)
	selectedLabel:Dock(BOTTOM)
	selectedLabel:SetTall(20)
	selectedLabel:DockMargin(0, 8, 0, 0)
	selectedLabel:SetFont("PDCity_Small")
	selectedLabel:SetTextColor(PDCity.THEME.TextDim)
	selectedLabel:SetText("Selected: none - click a weapon above")

	local gridScroll = vgui.Create("DScrollPanel", root)
	gridScroll:Dock(FILL)
	gridScroll:DockMargin(0, 8, 0, 0)
	PDCity.ApplyFastScroll(gridScroll)

	local grid = vgui.Create("DIconLayout", gridScroll)
	grid:Dock(TOP)
	grid:SetSpaceX(6)
	grid:SetSpaceY(6)
	confirmBtn.DoClick = function()
		if not selectedClass then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Pick a weapon from the grid first.")
			return
		end

		if whitelistCheck:GetChecked() then
			SendInventoryAdminAction("add", selectedClass)
		end

		onAdd(selectedClass, nicknameEntry:GetValue())

		selectedClass = nil
		selectedLabel:SetText("Selected: none - click a weapon above")
		whitelistCheck:SetChecked(false)
		nicknameEntry:SetValue("")
	end

	local function GetAllWeaponClasses()
		local list = {}
		for _, swep in pairs(weapons.GetList()) do
			local class = swep.ClassName
			if class then
				table.insert(list, { Class = class, Print = swep.PrintName or class, WorldModel = swep.WorldModel })
			end
		end
		table.sort(list, function(a, b) return a.Print < b.Print end)
		return list
	end
	local allWeaponClasses = GetAllWeaponClasses()

	local function RefreshGrid(filter)
		grid:Clear()
		filter = filter and filter:lower() or ""
		local shown = 0

		for _, entry in ipairs(allWeaponClasses) do
			if shown >= 150 then break end
			if filter == "" or entry.Class:lower():find(filter, 1, true) or entry.Print:lower():find(filter, 1, true) then

				local cell = vgui.Create("DPanel", grid)
				cell:SetSize(72, 86)
				cell.Paint = function(self, w, h)
					if selectedClass == entry.Class then
						draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.AccentDim)
					elseif self:IsHovered() then
						draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.PanelHover)
					end
				end
				cell:SetCursor("hand")
				cell:SetMouseInputEnabled(true)

				-- Same "real 3D preview via the weapon's own WorldModel,
				-- icon16 fallback" technique the F4 shop's entity cards
				-- already use (cl_f4_menu.lua's BuildEntityCard) - reused
				-- rather than guessing at a spawnicon PNG path, which
				-- isn't reliably present for addon weapons.
				if entry.WorldModel and entry.WorldModel ~= "" then
					local icon = vgui.Create("SpawnIcon", cell)
					icon:SetPos(4, 4)
					icon:SetSize(64, 64)
					icon:SetModel(entry.WorldModel)
					icon:SetMouseInputEnabled(false)
				else
					local fallback = vgui.Create("DPanel", cell)
					fallback:SetPos(4, 4)
					fallback:SetSize(64, 64)
					fallback:SetMouseInputEnabled(false)
					fallback.Paint = function(self, w, h)
						draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.TitleBar)
						surface.SetDrawColor(255, 255, 255, 255)
						surface.SetMaterial(Material("icon16/gun.png"))
						surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
					end
				end

				local label = vgui.Create("DLabel", cell)
				label:SetPos(0, 70)
				label:SetSize(72, 16)
				label:SetFont("PDCity_Small")
				label:SetTextColor(PDCity.THEME.TextDim)
				label:SetContentAlignment(5)
				label:SetText(entry.Print)
				label:SetMouseInputEnabled(false)

				cell.OnMousePressed = function(self, mcode)
					if mcode ~= MOUSE_LEFT then return end
					selectedClass = entry.Class
					selectedLabel:SetText("Selected: " .. entry.Print .. "  (" .. entry.Class .. ")")
				end

				shown = shown + 1
			end
		end
	end
	root.PDCityPopulate = function() RefreshGrid("") end

	filterEntry.OnValueChange = function(self, val) RefreshGrid(val) end

	return root

end

--[[---------------------------------------------------------
	Player model picker grid, built into the Jobs and NPCs tabs and Site
	Admin's Character Models tab (cl_character_models_admin.lua).
	onPick(model) runs on every click, so several models can be added in
	a row.
-----------------------------------------------------------]]
function PDCity.BuildPlayerModelPicker(parent, onPick, opts)
	opts = opts or {}

	local root = CreatePickerArea(parent, opts.Header)

	local filterEntry = vgui.Create("DTextEntry", root)
	filterEntry:Dock(TOP)
	filterEntry:SetTall(26)
	filterEntry:SetPlaceholderText("Filter player models...")

	local gridScroll = vgui.Create("DScrollPanel", root)
	gridScroll:Dock(FILL)
	gridScroll:DockMargin(0, 8, 0, 0)
	PDCity.ApplyFastScroll(gridScroll)

	local grid = vgui.Create("DIconLayout", gridScroll)
	grid:Dock(TOP)
	grid:SetSpaceX(6)
	grid:SetSpaceY(6)

	-- Same source sandbox's own "Player" spawnmenu tab uses
	-- (gamemodes/sandbox/gamemode/editor_player.lua) - list.Get("PlayerModels")
	-- isn't a real populated list in this codebase, despite the name
	-- suggesting otherwise.
	local function GetPlayerModelList()
		local out = {}
		for name, model in pairs(player_manager.AllValidModels()) do
			table.insert(out, { Model = model, Name = name })
		end
		table.sort(out, function(a, b) return a.Name < b.Name end)
		return out
	end
	local allPlayerModels = GetPlayerModelList()

	local function RefreshGrid(filter)
		grid:Clear()
		filter = filter and filter:lower() or ""
		local shown = 0
		for _, entry in ipairs(allPlayerModels) do
			if shown >= 150 then break end
			if filter == "" or entry.Name:lower():find(filter, 1, true) or entry.Model:lower():find(filter, 1, true) then
				local icon = vgui.Create("SpawnIcon", grid)
				icon:SetSize(64, 64)
				icon:SetModel(entry.Model)
				icon:SetTooltip(entry.Name)
				icon.DoClick = function() onPick(entry.Model) end
				shown = shown + 1
			end
		end
	end
	root.PDCityPopulate = function() RefreshGrid("") end

	filterEntry.OnValueChange = function(self, val) RefreshGrid(val) end

	return root

end

local function BuildJobsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	--[[-----------------------------------------------------
		Left/right split instead of stacking the form on top of the job
		list - the form (a fixed-height block, however tall it needs to
		be) and the list of existing jobs + "Removed built-in jobs" were
		previously all fighting over the SAME vertical space in `root`,
		which is exactly why the job list could end up all but invisible
		(reported as "I can't see any of the jobs I've added at all") -
		whatever was left over after the form's fixed height and the
		removed-jobs panel could be nearly nothing. Splitting them into
		separate columns means the list gets root's FULL height to
		itself, and doing it this way (rather than just shrinking the
		form) actually uses the width a responsive frame now has plenty
		of, instead of a form stretched edge-to-edge with mostly empty
		space around a few narrow fields (reported as "the flags shown
		section is way too big").
	-------------------------------------------------------]]
	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(620)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	--[[-----------------------------------------------------
		Picker column, between the form and the job list: the player
		model and weapon grids, one at a time, switched by the two tabs at
		its top (or the form's own "Choose a Player Model" / "Add A
		Weapon" buttons). Their callbacks are filled in once the form's
		model/weapon lists exist further down.
	-------------------------------------------------------]]
	local OnModelPicked, OnWeaponPicked

	local pickerPane = vgui.Create("DPanel", root)
	pickerPane:Dock(LEFT)
	pickerPane:SetWide(380)
	pickerPane:DockMargin(0, 0, 12, 0)
	pickerPane.Paint = function() end

	local pickerTabs = vgui.Create("DPanel", pickerPane)
	pickerTabs:Dock(TOP)
	pickerTabs:SetTall(28)
	pickerTabs:DockMargin(0, 0, 0, 8)
	pickerTabs.Paint = function() end

	local modelPicker = PDCity.BuildPlayerModelPicker(pickerPane, function(model) OnModelPicked(model) end, { Header = "Player Models" })
	modelPicker:Dock(FILL)

	local weaponPicker = BuildWeaponPicker(pickerPane, function(class, nickname) OnWeaponPicked(class, nickname) end, { Header = "Weapons" })
	weaponPicker:Dock(FILL)

	local modelTabBtn = vgui.Create("DButton", pickerTabs)
	local weaponTabBtn = vgui.Create("DButton", pickerTabs)

	local INACTIVE_TAB = { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim }
	local function ShowPicker(showWeapons)
		modelPicker:SetVisible(not showWeapons)
		weaponPicker:SetVisible(showWeapons)
		PDCity.StyleButton(modelTabBtn, "Player Models", (not showWeapons) and nil or INACTIVE_TAB)
		PDCity.StyleButton(weaponTabBtn, "Weapons", showWeapons and nil or INACTIVE_TAB)
		pickerPane:InvalidateLayout()
	end

	pickerTabs.PerformLayout = function(self, w, h)
		modelTabBtn:SetSize(w / 2 - 3, h)
		modelTabBtn:SetPos(0, 0)
		weaponTabBtn:SetSize(w / 2 - 3, h)
		weaponTabBtn:SetPos(w / 2 + 3, 0)
	end

	modelTabBtn.DoClick = function() ShowPicker(false) end
	weaponTabBtn.DoClick = function() ShowPicker(true) end
	ShowPicker(false)

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	local formHolder = vgui.Create("DPanel", leftPane)
	formHolder:Dock(FILL)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(10, 10, 10, 10)
	PDCity.ApplyFastScroll(form)

	local header = vgui.Create("DLabel", form)
	header:Dock(TOP)
	header:SetTall(26)
	header:SetFont("PDCity_Title")
	header:SetText("Job Editor")
	header:SetTextColor(PDCity.THEME.Text)
	header:SetContentAlignment(5)

	-- Player models: added one at a time to a plain Lua list (not read
	-- back from the DListView later - simpler and doesn't depend on any
	-- particular way of introspecting its rows) and shown below for
	-- review/removal before the job itself is submitted.
	local pendingModels = {}

	-- {Class, Nickname} entries - see core/sv_job_catalogue.lua's own
	-- NormalizeWeaponList for why Nickname is optional/may be nil.
	local pendingWeapons = {}

	-- Set while an existing custom job is loaded into the form for
	-- editing (clicking its row in the list below) - nil means the form
	-- is building a brand new job. Forward declared: referenced by
	-- ResetForm/addBtn below but only ever assigned once the job list
	-- itself is built further down.
	local editingJobID = nil
	local editingBuiltin = false -- true when editingJobID points at a PDCity.JOBS entry, not a PDCity.CUSTOM_JOBS one
	local listView

	--[[-----------------------------------------------------
		Row A: Title | Category
	-------------------------------------------------------]]
	local rowA = vgui.Create("DPanel", form)
	rowA:Dock(TOP)
	rowA:SetTall(26)
	rowA:DockMargin(0, 12, 0, 0)
	rowA.Paint = function() end

	local nameEntry = vgui.Create("DTextEntry", rowA)
	nameEntry:Dock(LEFT)
	nameEntry:SetWide(240)
	nameEntry:SetPlaceholderText("Job Title")

	local categoryCombo = vgui.Create("DComboBox", rowA)
	categoryCombo:Dock(FILL)
	categoryCombo:DockMargin(8, 0, 0, 0)
	local function RefreshCategoryCombo()
		categoryCombo:Clear()
		for _, name in ipairs(PDCity.SECTIONS) do
			categoryCombo:AddChoice(name)
		end
		if PDCity.SECTIONS[1] then categoryCombo:ChooseOptionID(1) end
	end
	RefreshCategoryCombo()

	--[[-----------------------------------------------------
		Row B: Description | Level Requirement
	-------------------------------------------------------]]
	local rowB = vgui.Create("DPanel", form)
	rowB:Dock(TOP)
	rowB:SetTall(26)
	rowB:DockMargin(0, 8, 0, 0)
	rowB.Paint = function() end

	local descEntry = vgui.Create("DTextEntry", rowB)
	descEntry:Dock(LEFT)
	descEntry:SetWide(240)
	descEntry:SetPlaceholderText("Card Description")

	-- Class-level requirement (core/sv_jobs.lua's RequiredLevel gate) -
	-- e.g. "Police Sergeant needs Police level 4", checked against
	-- whatever level the player has in the JOB'S OWN Section (the combo
	-- above), not a separate class picker. 0 means no requirement, same
	-- convention as Salary.
	local requiredLevelEntry = vgui.Create("DTextEntry", rowB)
	requiredLevelEntry:Dock(FILL)
	requiredLevelEntry:DockMargin(8, 0, 0, 0)
	requiredLevelEntry:SetNumeric(true)
	requiredLevelEntry:SetPlaceholderText("Required Level (0 = none)")
	requiredLevelEntry.OnValueChange = function(self, val)
		local cleaned = val:gsub("[^%d]", "")
		if cleaned ~= val then
			self:SetText(cleaned)
			self:SetCaretPos(#cleaned)
		end
	end

	--[[-----------------------------------------------------
		Row B2: whitelist level - only actually means anything for a job
		in a category marked "Whitelist Only?" (Job Categories tab), where
		it completely REPLACES Required Level above (core/sv_jobs.lua's
		PDCity.ApplyJob) - left visible either way rather than hidden/
		disabled, since which categories are whitelist-only can change
		after this job was created.
	-------------------------------------------------------]]
	local rowB2 = vgui.Create("DPanel", form)
	rowB2:Dock(TOP)
	rowB2:SetTall(26)
	rowB2:DockMargin(0, 8, 0, 0)
	rowB2.Paint = function() end

	local requiredWhitelistLevelEntry = vgui.Create("DTextEntry", rowB2)
	requiredWhitelistLevelEntry:Dock(LEFT)
	requiredWhitelistLevelEntry:SetWide(240)
	requiredWhitelistLevelEntry:SetNumeric(true)
	requiredWhitelistLevelEntry:SetPlaceholderText("Required Whitelist Level (only in whitelist-only categories)")
	requiredWhitelistLevelEntry.OnValueChange = function(self, val)
		local cleaned = val:gsub("[^%d]", "")
		if cleaned ~= val then
			self:SetText(cleaned)
			self:SetCaretPos(#cleaned)
		end
	end

	--[[-----------------------------------------------------
		Row C: Salary | Icon picker
	-------------------------------------------------------]]
	local rowC = vgui.Create("DPanel", form)
	rowC:Dock(TOP)
	rowC:SetTall(26)
	rowC:DockMargin(0, 8, 0, 0)
	rowC.Paint = function() end

	local salaryEntry = vgui.Create("DTextEntry", rowC)
	salaryEntry:Dock(LEFT)
	salaryEntry:SetWide(160)
	salaryEntry:SetNumeric(true)
	salaryEntry:SetPlaceholderText("Salary ($)")
	-- Same whole-numbers-only cleanup as the entity price field.
	salaryEntry.OnValueChange = function(self, val)
		local cleaned = val:gsub("[^%d]", "")
		if cleaned ~= val then
			self:SetText(cleaned)
			self:SetCaretPos(#cleaned)
		end
	end

	-- Icon accepts EITHER a silkicon path (picked from the popout below)
	-- OR a pasted http(s) image URL - cl_f4_menu.lua's BuildCard detects
	-- which at render time and fetches/caches URLs to
	-- data/pdcity_jobicons/ the first time each one is seen. Originally
	-- offered a hand-typed emoji as a third option too, but Source's
	-- text rendering can't draw color emoji at all - they came out as
	-- empty tofu boxes in the F4 menu grid - so the picker below only
	-- ever inserts a real (guaranteed-to-render) silkicon path now.
	local iconEntry = vgui.Create("DTextEntry", rowC)
	iconEntry:Dock(FILL)
	iconEntry:DockMargin(8, 0, 0, 0)
	iconEntry:SetPlaceholderText("Icon: pick one, or an image URL")

	-- A curated subset of GMod's bundled silk icon set (materials/icon16/
	-- - confirmed present via vpk.exe against garrysmod_dir.vpk) that
	-- actually suits a police-RP job list, rather than every one of the
	-- ~1000 available.
	local ICON16_CHOICES = {
		"icon16/car.png", "icon16/car_add.png", "icon16/shield.png", "icon16/shield_add.png",
		"icon16/gun.png", "icon16/key.png", "icon16/lock.png", "icon16/lock_open.png",
		"icon16/money.png", "icon16/coins.png", "icon16/cog.png", "icon16/wrench.png",
		"icon16/wrench_orange.png", "icon16/medal_gold_1.png", "icon16/award_star_gold_3.png", "icon16/house.png",
		"icon16/briefcase.png", "icon16/group.png", "icon16/user.png", "icon16/star.png",
		"icon16/flag_red.png", "icon16/fire.png", "icon16/pill.png", "icon16/table.png",
	}

	local iconPickBtn = vgui.Create("DButton", rowC)
	iconPickBtn:Dock(RIGHT)
	iconPickBtn:SetWide(28)
	iconPickBtn:DockMargin(4, 0, 0, 0)
	iconPickBtn:SetText("")
	iconPickBtn.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(Material("icon16/picture.png"))
		surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
	end
	iconPickBtn.DoClick = function()
		local menu = DermaMenu()
		local cols = 6
		local cell = 32
		local grid = vgui.Create("DPanel", menu)
		grid:SetSize(cols * cell, math.ceil(#ICON16_CHOICES / cols) * cell)
		grid.Paint = function() end

		for i, path in ipairs(ICON16_CHOICES) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local mat = Material(path)

			local b = vgui.Create("DButton", grid)
			b:SetPos(col * cell, row * cell)
			b:SetSize(cell - 2, cell - 2)
			b:SetText("")
			b.Paint = function(self, w, h)
				if self:IsHovered() then draw.RoundedBox(2, 0, 0, w, h, PDCity.THEME.PanelHover) end
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(mat)
				surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
			end
			b.DoClick = function()
				iconEntry:SetValue(path)
				CloseDermaMenus() -- a DermaMenu has no :Close(); this is GMod's way to close one
			end
		end

		menu:AddPanel(grid)
		menu:Open()
	end

	--[[-----------------------------------------------------
		Two columns below: models (left) / flags + weapons (right) -
		mirrors the requested mockup's own layout.
	-------------------------------------------------------]]
	local columns = vgui.Create("DPanel", form)
	columns:Dock(TOP)
	columns:SetTall(320)
	columns:DockMargin(0, 14, 0, 0)
	columns.Paint = function() end

	local leftCol = vgui.Create("DPanel", columns)
	leftCol:Dock(LEFT)
	leftCol:SetWide(260)
	leftCol.Paint = function() end

	local rightCol = vgui.Create("DPanel", columns)
	rightCol:Dock(FILL)
	rightCol:DockMargin(12, 0, 0, 0)
	rightCol.Paint = function() end

	--[[-----------------------------------------------------
		Left column: player models
	-------------------------------------------------------]]
	local modelList = vgui.Create("DListView", leftCol)
	modelList:Dock(TOP)
	modelList:SetTall(64)
	modelList:SetMultiSelect(false)
	modelList:AddColumn("Current models (optional - leave empty to use each character's own chosen model)")

	-- Grows to fit however many models are on the job so far, instead of
	-- a fixed height that forced a scrollbar as soon as there were more
	-- than 2-3 - capped so a job with a huge model pool doesn't push the
	-- rest of the column out of alignment with the flags/weapons side.
	local function RefreshModelList()
		modelList:Clear()
		for _, path in ipairs(pendingModels) do
			local line = modelList:AddLine(path)
			line.pdcityModelPath = path
		end
		modelList:SetTall(math.Clamp(16 + #pendingModels * 18 + 4, 64, 140))
	end

	local addModelPickerBtn = vgui.Create("DButton", leftCol)
	addModelPickerBtn:Dock(TOP)
	addModelPickerBtn:SetTall(28)
	addModelPickerBtn:DockMargin(0, 6, 0, 0)
	PDCity.StyleButton(addModelPickerBtn, "Choose a Player Model  >")
	addModelPickerBtn.DoClick = function() ShowPicker(false) end

	OnModelPicked = function(model)
		table.insert(pendingModels, model)
		RefreshModelList()
	end

	local removeModelBtn = vgui.Create("DButton", leftCol)
	removeModelBtn:Dock(TOP)
	removeModelBtn:SetTall(22)
	removeModelBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(removeModelBtn, "Remove Selected Model", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	removeModelBtn.DoClick = function()
		local selected = modelList:GetSelected()
		local row = selected and selected[1]
		if not row then return end

		for i, path in ipairs(pendingModels) do
			if path == row.pdcityModelPath then
				table.remove(pendingModels, i)
				break
			end
		end
		RefreshModelList()
	end

	-- Fallback for anything not in that stock list (custom/workshop
	-- models, like the existing police jobs' LVMPD ones).
	local modelRow = vgui.Create("DPanel", leftCol)
	modelRow:Dock(TOP)
	modelRow:SetTall(26)
	modelRow:DockMargin(0, 8, 0, 0)
	modelRow.Paint = function() end

	local modelEntry = vgui.Create("DTextEntry", modelRow)
	modelEntry:Dock(FILL)
	modelEntry:DockMargin(0, 0, 6, 0)
	modelEntry:SetPlaceholderText("Or paste a custom model path...")

	local addModelBtn = vgui.Create("DButton", modelRow)
	addModelBtn:Dock(RIGHT)
	addModelBtn:SetWide(90)
	PDCity.StyleButton(addModelBtn, "Add Model")
	addModelBtn.DoClick = function()
		local path = modelEntry:GetValue()
		if path == "" then return end
		table.insert(pendingModels, path)
		modelEntry:SetValue("")
		RefreshModelList()
	end

	--[[-----------------------------------------------------
		Right column: display-only permission flags (see
		core/sv_job_catalogue.lua's NormalizeFlag - no gameplay system
		reads these yet) + the job's weapon loadout.
	-------------------------------------------------------]]
	local flagsHeader = vgui.Create("DLabel", rightCol)
	flagsHeader:Dock(TOP)
	flagsHeader:SetTall(18)
	flagsHeader:SetFont("PDCity_Small")
	flagsHeader:SetTextColor(PDCity.THEME.TextDim)
	flagsHeader:SetText("Flags shown on this job's F4 card (informational only for now)")

	local raidCheck = vgui.Create("DCheckBoxLabel", rightCol)
	raidCheck:Dock(TOP)
	raidCheck:SetTall(20)
	raidCheck:DockMargin(0, 4, 0, 0)
	raidCheck:SetText("Can Raid")
	raidCheck:SetTextColor(PDCity.THEME.Text)

	local mugCheck = vgui.Create("DCheckBoxLabel", rightCol)
	mugCheck:Dock(TOP)
	mugCheck:SetTall(20)
	mugCheck:SetText("Can Mug")
	mugCheck:SetTextColor(PDCity.THEME.Text)

	local kidnapCheck = vgui.Create("DCheckBoxLabel", rightCol)
	kidnapCheck:Dock(TOP)
	kidnapCheck:SetTall(20)
	kidnapCheck:SetText("Can Kidnap")
	kidnapCheck:SetTextColor(PDCity.THEME.Text)

	-- Not display-only: core/sv_chat.lua sends /dwa adverts to these jobs.
	local darkWebCheck = vgui.Create("DCheckBoxLabel", rightCol)
	darkWebCheck:Dock(TOP)
	darkWebCheck:SetTall(20)
	darkWebCheck:SetText("Dark web access (receives /dwa adverts)")
	darkWebCheck:SetTextColor(PDCity.THEME.Text)

	local weaponListView = vgui.Create("DListView", rightCol)
	weaponListView:Dock(TOP)
	weaponListView:SetTall(120)
	weaponListView:DockMargin(0, 10, 0, 0)
	weaponListView:SetMultiSelect(false)
	weaponListView:AddColumn("Current weapons added")

	local function RefreshWeaponList()
		weaponListView:Clear()
		for _, entry in ipairs(pendingWeapons) do
			local line = weaponListView:AddLine(entry.Nickname or entry.Class)
			line.pdcityWeaponEntry = entry
		end
	end

	local removeWeaponBtn = vgui.Create("DButton", rightCol)
	removeWeaponBtn:Dock(TOP)
	removeWeaponBtn:SetTall(22)
	removeWeaponBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(removeWeaponBtn, "Remove Selected Weapon", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	removeWeaponBtn.DoClick = function()
		local selected = weaponListView:GetSelected()
		local row = selected and selected[1]
		if not row or not row.pdcityWeaponEntry then return end

		for i, entry in ipairs(pendingWeapons) do
			if entry == row.pdcityWeaponEntry then
				table.remove(pendingWeapons, i)
				break
			end
		end
		RefreshWeaponList()
	end

	local addWeaponBtn = vgui.Create("DButton", rightCol)
	addWeaponBtn:Dock(TOP)
	addWeaponBtn:SetTall(28)
	addWeaponBtn:DockMargin(0, 8, 0, 0)
	PDCity.StyleButton(addWeaponBtn, "Add A Weapon  >")
	addWeaponBtn.DoClick = function() ShowPicker(true) end

	OnWeaponPicked = function(class, nickname)
		table.insert(pendingWeapons, {
			Class = class,
			Nickname = (isstring(nickname) and nickname ~= "") and nickname or nil,
		})
		RefreshWeaponList()
	end

	--[[-----------------------------------------------------
		Door factions this job belongs to (core/sh_door_factions.lua) -
		members can lock/unlock that faction's doors. Whole categories
		can also be added from the faction's side in Site Admin.
	-------------------------------------------------------]]
	local pendingFactions = {} -- [factionID] = true

	local factionsHeader = vgui.Create("DLabel", form)
	factionsHeader:Dock(TOP)
	factionsHeader:SetTall(18)
	factionsHeader:DockMargin(0, 14, 0, 0)
	factionsHeader:SetFont("PDCity_Small")
	factionsHeader:SetTextColor(PDCity.THEME.TextDim)
	factionsHeader:SetText("Door factions - this job can lock/unlock doors owned by the ticked factions")

	local factionsHolder = vgui.Create("DPanel", form)
	factionsHolder:Dock(TOP)
	factionsHolder:DockMargin(0, 2, 0, 0)
	factionsHolder.Paint = function() end

	local function RebuildFactionChecks()
		factionsHolder:Clear()

		local factions = PDCity.GetSortedDoorFactions()
		if #factions == 0 then
			local hint = vgui.Create("DLabel", factionsHolder)
			hint:Dock(TOP)
			hint:SetTall(18)
			hint:SetFont("PDCity_Small")
			hint:SetTextColor(PDCity.THEME.TextDim)
			hint:SetText("No door factions yet - create them in F1 > Site Admin > Door Factions.")
			factionsHolder:SetTall(22)
		else
			for _, faction in ipairs(factions) do
				local check = vgui.Create("DCheckBoxLabel", factionsHolder)
				check:Dock(TOP)
				check:SetTall(20)
				check:DockMargin(0, 4, 0, 0)
				check:SetText(faction.Name)
				check:SetTextColor(PDCity.THEME.Text)
				check:SetChecked(pendingFactions[faction.ID] == true)
				check.OnChange = function(self, checked)
					pendingFactions[faction.ID] = checked or nil
				end
			end
			factionsHolder:SetTall(#factions * 24)
		end

		form:InvalidateLayout()
	end
	RebuildFactionChecks()

	hook.Add("PDCity_DoorFactionsUpdated", factionsHolder, function() RebuildFactionChecks() end)

	--[[-----------------------------------------------------
		Submit / cancel
	-------------------------------------------------------]]
	local addBtn = vgui.Create("DButton", form)
	addBtn:Dock(TOP)
	addBtn:SetTall(30)
	addBtn:DockMargin(0, 14, 0, 0)
	local addBtnLabel = "Add Job"
	PDCity.StyleButton(addBtn, addBtnLabel)

	local cancelEditBtn = vgui.Create("DButton", form)
	cancelEditBtn:Dock(TOP)
	cancelEditBtn:SetTall(22)
	cancelEditBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(cancelEditBtn, "Cancel Edit (Start a New Job Instead)", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelEditBtn:SetVisible(false)

	-- Shared by "submitted successfully" (optimistic - same as before,
	-- this doesn't wait for a server ack) and the cancel button.
	local function ResetForm()
		editingJobID = nil
		editingBuiltin = false
		nameEntry:SetValue("")
		salaryEntry:SetValue("")
		requiredLevelEntry:SetValue("")
		requiredWhitelistLevelEntry:SetValue("")
		descEntry:SetValue("")
		iconEntry:SetValue("")
		raidCheck:SetChecked(false)
		mugCheck:SetChecked(false)
		kidnapCheck:SetChecked(false)
		darkWebCheck:SetChecked(false)
		pendingModels = {}
		RefreshModelList()
		pendingWeapons = {}
		RefreshWeaponList()
		pendingFactions = {}
		RebuildFactionChecks()
		addBtnLabel = "Add Job"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(false)
	end

	cancelEditBtn.DoClick = ResetForm

	addBtn.DoClick = function()
		if nameEntry:GetValue() == "" then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a job name first.")
			return
		end

		-- Models are optional now - a job with none picked falls back to
		-- each character's own chosen player model at spawn time
		-- (core/sv_job_catalogue.lua's IsValidModelList).

		local salary = tonumber(salaryEntry:GetValue()) or 0
		local requiredLevel = tonumber(requiredLevelEntry:GetValue()) or 0
		local requiredWhitelistLevel = tonumber(requiredWhitelistLevelEntry:GetValue()) or 0

		local doorFactions = {}
		for id in pairs(pendingFactions) do table.insert(doorFactions, id) end

		local payload = {
			Name = nameEntry:GetValue(),
			Models = pendingModels,
			Salary = math.floor(salary),
			RequiredLevel = math.floor(requiredLevel),
			RequiredWhitelistLevel = math.floor(requiredWhitelistLevel),
			Section = categoryCombo:GetSelected() or PDCity.SECTIONS[1],
			Description = descEntry:GetValue(),
			Icon = iconEntry:GetValue(),
			Weapons = pendingWeapons,
			CanRaid = raidCheck:GetChecked(),
			CanMug = mugCheck:GetChecked(),
			CanKidnap = kidnapCheck:GetChecked(),
			DarkWeb = darkWebCheck:GetChecked(),
			DoorFactions = doorFactions,
		}

		if editingJobID then
			payload.ID = editingJobID
			SendJobAdminAction(editingBuiltin and "edit_builtin_job" or "edit_job", payload)
		else
			SendJobAdminAction("add_job", payload)
		end

		ResetForm()
	end

	--[[-----------------------------------------------------
		Removed built-in jobs - same idea as the Entities tab's own
		restore list (core/sh_f4_entities.lua's Removed override flag),
		just for PDCity.JOBS/PDCity.JOB_OVERRIDES instead. Only visible
		at all when something's actually removed.

		Created (and Dock(BOTTOM)'d) BEFORE the main job list below -
		GMod's docking allocates space in DOCK ORDER, not creation order
		vs. Dock type: a FILL panel docked first claims everything still
		available at that point, leaving nothing for a BOTTOM panel
		docked afterward (that's what was cutting this off entirely -
		it never had it backwards, it just needed to reserve its slice
		of `root` before the FILL list got a chance to take all of it).
	-------------------------------------------------------]]
	local removedHolder = vgui.Create("DPanel", rightPane)
	removedHolder:Dock(BOTTOM)
	removedHolder:SetTall(140)
	removedHolder:DockMargin(0, 8, 0, 0)
	removedHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end
	removedHolder:SetVisible(false)

	local removedLabel = vgui.Create("DLabel", removedHolder)
	removedLabel:Dock(TOP)
	removedLabel:SetTall(20)
	removedLabel:DockMargin(8, 6, 8, 0)
	removedLabel:SetFont("PDCity_Small")
	removedLabel:SetTextColor(PDCity.THEME.TextDim)
	removedLabel:SetText("Removed built-in jobs:")

	local restoreJobBtn = vgui.Create("DButton", removedHolder)
	restoreJobBtn:Dock(BOTTOM)
	restoreJobBtn:SetTall(24)
	restoreJobBtn:DockMargin(8, 4, 8, 6)
	PDCity.StyleButton(restoreJobBtn, "Restore Selected")

	local removedJobList = vgui.Create("DListView", removedHolder)
	removedJobList:Dock(FILL)
	removedJobList:DockMargin(8, 4, 8, 0)
	removedJobList:SetMultiSelect(false)
	removedJobList:AddColumn("Name")

	restoreJobBtn.DoClick = function()
		local selected = removedJobList:GetSelected()
		local row = selected and selected[1]
		if not row then return end
		SendJobAdminAction("restore_builtin_job", { ID = row.pdcityID })
	end

	local function RefreshRemovedJobList()
		removedJobList:Clear()
		local removed = PDCity.GetRemovedBuiltinJobs()
		for _, cfg in ipairs(removed) do
			local line = removedJobList:AddLine(cfg.Name)
			line.pdcityID = cfg.ID
		end
		removedHolder:SetVisible(#removed > 0)
	end

	-- Jobs don't support reordering (unlike entities, where display
	-- position matters for a shop) - onMove is nil to hide those buttons.
	-- A built-in job (core/sh_jobs.lua's PDCity.JOBS) can't be truly
	-- deleted - the row itself (the entry in PDCity.JOBS) always exists -
	-- but "Remove" hides it from the game entirely (remove_builtin_job,
	-- reversible below), same as a custom job's real delete from this
	-- list's point of view. PDCity.DEFAULT_JOB refuses specifically
	-- (server-side) since the game needs a real job at that ID.
	listView = BuildManagedList(rightPane, { "Name", "Category", "Salary", "Models" }, nil,
		function(id)
			if editingJobID == id then ResetForm() end
			if PDCity.JOBS[id] then
				SendJobAdminAction("remove_builtin_job", { ID = id })
			else
				SendJobAdminAction("remove_job", { ID = id })
			end
		end
	)

	-- Clicking a row loads that job back into the form above for editing
	-- rather than adding a new one - Save Changes (addBtn, relabelled)
	-- then sends edit_job/edit_builtin_job instead of add_job. Uses
	-- PDCity.GetJob so a built-in job's CURRENT (possibly already
	-- overridden) values load, not always its original hardcoded ones.
	listView.OnRowSelected = function(self, index, row)
		local job = PDCity.GetJob(row.pdcityID)
		if not job then return end

		editingJobID = row.pdcityID
		editingBuiltin = PDCity.JOBS[row.pdcityID] ~= nil

		nameEntry:SetValue(job.Name or "")
		salaryEntry:SetValue(tostring(job.Salary or 0))
		requiredLevelEntry:SetValue(tostring(job.RequiredLevel or 0))
		requiredWhitelistLevelEntry:SetValue(tostring(job.RequiredWhitelistLevel or 0))
		descEntry:SetValue(job.Description or "")
		iconEntry:SetValue(job.Icon or "")
		raidCheck:SetChecked(job.CanRaid == true)
		mugCheck:SetChecked(job.CanMug == true)
		kidnapCheck:SetChecked(job.CanKidnap == true)
		darkWebCheck:SetChecked(job.DarkWeb == true)

		pendingModels = table.Copy(job.Models or {})
		RefreshModelList()

		pendingWeapons = {}
		for _, entry in ipairs(job.Weapons or {}) do
			if istable(entry) then
				table.insert(pendingWeapons, table.Copy(entry))
			else
				table.insert(pendingWeapons, { Class = entry }) -- pre-Nickname saved job
			end
		end
		RefreshWeaponList()

		pendingFactions = {}
		for _, id in ipairs(job.DoorFactions or {}) do pendingFactions[id] = true end
		RebuildFactionChecks()

		for i, name in ipairs(PDCity.SECTIONS) do
			if name == job.Section then
				categoryCombo:ChooseOptionID(i)
				break
			end
		end

		addBtnLabel = "Save Changes"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(true)
	end

	local function RefreshJobList()
		listView:Clear()
		for _, id in ipairs(PDCity.GetSortedJobIDs()) do
			local job = PDCity.GetJob(id)
			if job then
				local line = listView:AddLine(job.Name, job.Section or "", "$" .. (job.Salary or 0), #(job.Models or {}))
				line.pdcityID = id
			end
		end
		RefreshCategoryCombo()
		RefreshRemovedJobList()
	end
	RefreshJobList()

	root.PDCityRefresh = function()
		RefreshJobList()
	end

	return root

end

local function BuildJobCategoriesTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local addRow = vgui.Create("DPanel", root)
	addRow:Dock(TOP)
	addRow:SetTall(30)
	addRow:DockMargin(0, 0, 0, 8)
	addRow.Paint = function() end

	local nameEntry = vgui.Create("DTextEntry", addRow)
	nameEntry:Dock(FILL)
	nameEntry:DockMargin(0, 0, 6, 0)
	nameEntry:SetPlaceholderText("New job category name")

	local addBtn = vgui.Create("DButton", addRow)
	addBtn:Dock(RIGHT)
	addBtn:SetWide(100)
	PDCity.StyleButton(addBtn, "Add Category")
	addBtn.DoClick = function()
		local name = nameEntry:GetValue()
		if name == "" then return end
		SendJobAdminAction("add_category", { Name = name })
		nameEntry:SetValue("")
	end

	-- Whitelist-only toggle (core/sh_jobs.lua's PDCity.SECTION_WHITELIST_ONLY) -
	-- every job in a whitelist-only category swaps its RequiredLevel gate
	-- for a department whitelist level instead (core/sv_jobs.lua's
	-- PDCity.ApplyJob). Shown as a column since BuildManagedList's own
	-- list doesn't support per-row custom controls - select a row, then
	-- this button below flips it.
	local toggleWhitelistBtn = vgui.Create("DButton", root)
	toggleWhitelistBtn:Dock(BOTTOM)
	toggleWhitelistBtn:SetTall(26)
	toggleWhitelistBtn:DockMargin(0, 8, 0, 0)
	PDCity.StyleButton(toggleWhitelistBtn, "Toggle \"Whitelist Only?\" For Selected")

	local listView = BuildManagedList(root, { "Category", "Whitelist Only?" },
		function(id, dir)
			local order = table.Copy(PDCity.SECTIONS)

			local from
			for i, name in ipairs(order) do
				if name == id then from = i break end
			end
			if not from then return end

			local to = from + dir
			if to < 1 or to > #order then return end

			order[from], order[to] = order[to], order[from]
			SendJobAdminAction("reorder_categories", { Order = order })
		end,
		function(id)
			SendJobAdminAction("remove_category", { Name = id })
		end
	)

	toggleWhitelistBtn.DoClick = function()
		local selected = listView:GetSelected()
		local row = selected and selected[1]
		if not row then return end

		SendJobAdminAction("set_category_whitelist", {
			Name = row.pdcityID,
			WhitelistOnly = not PDCity.IsSectionWhitelistOnly(row.pdcityID),
		})
	end

	local function RefreshList()
		listView:Clear()
		for _, name in ipairs(PDCity.SECTIONS) do
			local line = listView:AddLine(name, PDCity.IsSectionWhitelistOnly(name) and "Yes" or "No")
			line.pdcityID = name
		end
	end
	RefreshList()

	root.PDCityRefresh = function()
		RefreshList()
	end

	return root

end

--[[---------------------------------------------------------
	Inventory Items tab - the whitelist of classes players are allowed
	to store (PDCity.INVENTORY_ALLOWED, core/sh_inventory.lua). Nothing
	is storable until it's added here.
-----------------------------------------------------------]]
-- Persists for as long as the F4 admin editor's Lua environment does
-- (a plain upvalue, not tied to one tab instance) - reopening the
-- editor keeps whatever split the owner last dragged to, the same way
-- window layouts usually remember themselves.
local inventoryTabSplit = {}

local function BuildInventoryItemsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	-- Top and bottom panels below are positioned entirely by
	-- PDCity.MakeSplitter (cl_theme.lua) - no Dock of their own, so the
	-- drag handle between them can freely resize the split instead of it
	-- being a fixed pixel value baked into the layout.
	local formHolder = vgui.Create("DPanel", root)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DPanel", formHolder)
	form:Dock(FILL)
	form.Paint = function() end
	form:DockMargin(10, 10, 10, 10)

	local blurb = vgui.Create("DLabel", form)
	blurb:Dock(TOP)
	blurb:SetTall(32)
	blurb:SetText("Only these classes can be picked up into an inventory (CTRL+E).\nRemoving one leaves existing copies in players' inventories alone.")
	blurb:SetTextColor(PDCity.THEME.TextDim)
	blurb:SetWrap(true)

	local searchEntry = vgui.Create("DTextEntry", form)
	searchEntry:Dock(TOP)
	searchEntry:SetTall(26)
	searchEntry:DockMargin(0, 4, 0, 6)
	searchEntry:SetPlaceholderText("Search entity/weapon classes...")

	-- BOTTOM before the FILL list below.
	local addBtn = vgui.Create("DButton", form)
	addBtn:Dock(BOTTOM)
	addBtn:SetTall(28)
	addBtn:DockMargin(0, 8, 0, 0)
	PDCity.StyleButton(addBtn, "Allow In Inventory")

	local classList = vgui.Create("DListView", form)
	classList:Dock(FILL)
	classList:SetMultiSelect(false)
	classList:AddColumn("Class")

	local allClasses = GetAllClasses()
	local selectedClass = nil

	local function RefreshClassList(filter)
		classList:Clear()
		filter = filter and filter:lower() or ""
		local shown = 0
		for _, entry in ipairs(allClasses) do
			if shown >= 150 then break end
			if filter == "" or entry.Class:lower():find(filter, 1, true) then
				local line = classList:AddLine(entry.Print)
				line.pdcityClass = entry.Class
				shown = shown + 1
			end
		end
	end
	RefreshClassList("")

	searchEntry.OnValueChange = function(self, val) RefreshClassList(val) end
	classList.OnRowSelected = function(self, index, row) selectedClass = row.pdcityClass end

	addBtn.DoClick = function()
		if not selectedClass then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Pick a class from the search list first.")
			return
		end
		SendInventoryAdminAction("add", selectedClass)
	end

	-- Own holder (not `root` directly) so PDCity.MakeSplitter can size
	-- this whole thing as one unit - BuildManagedList's own DListView
	-- still just Dock(FILL)s inside it as always.
	local listHolder = vgui.Create("DPanel", root)
	listHolder.Paint = function() end

	local listView = BuildManagedList(listHolder, { "Allowed item", "Class" }, nil,
		function(class)
			SendInventoryAdminAction("remove", class)
		end
	)

	local function RefreshAllowedList()
		listView:Clear()
		for _, class in ipairs(PDCity.INVENTORY_ALLOWED) do
			local line = listView:AddLine(PDCity.GetItemName(class), class)
			line.pdcityID = class
		end
	end
	RefreshAllowedList()

	local Reflow = PDCity.MakeSplitter(root, formHolder, listHolder, inventoryTabSplit)
	root.PerformLayout = function(self, w, h) Reflow(w, h) end

	root.PDCityRefresh = function()
		RefreshAllowedList()
	end

	return root

end

--[[---------------------------------------------------------
	Physgun Whitelist tab - which entity classes a normal player's
	physgun can pick up at all (PDCity.PHYSGUN_WHITELIST,
	core/sh_physgun_whitelist.lua). Ordinary build props (prop_physics and
	friends) are always allowed and don't appear here - this only governs
	everything else (map fixtures, NPCs, vehicles, custom entities).
	Owner/staff bypass the whitelist entirely regardless of what's listed.
	Same layout as the Inventory Items tab immediately above, right down
	to the splitter and the search-then-add flow.
-----------------------------------------------------------]]
local physgunTabSplit = {}

local function BuildPhysgunWhitelistTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local formHolder = vgui.Create("DPanel", root)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DPanel", formHolder)
	form:Dock(FILL)
	form.Paint = function() end
	form:DockMargin(10, 10, 10, 10)

	local blurb = vgui.Create("DLabel", form)
	blurb:Dock(TOP)
	blurb:SetTall(46)
	blurb:SetText("Ordinary spawned/bought/duplicated props stay physgun-able for everyone without needing to be listed here. Everything else (map entities, NPCs, vehicles, custom entities) needs its class added below before a normal player can physgun it. Owner/staff bypass this entirely.")
	blurb:SetTextColor(PDCity.THEME.TextDim)
	blurb:SetWrap(true)

	local searchEntry = vgui.Create("DTextEntry", form)
	searchEntry:Dock(TOP)
	searchEntry:SetTall(26)
	searchEntry:DockMargin(0, 4, 0, 6)
	searchEntry:SetPlaceholderText("Search entity/weapon classes...")

	-- BOTTOM before the FILL list below.
	local addBtn = vgui.Create("DButton", form)
	addBtn:Dock(BOTTOM)
	addBtn:SetTall(28)
	addBtn:DockMargin(0, 8, 0, 0)
	PDCity.StyleButton(addBtn, "Allow Physgun Pickup")

	local classList = vgui.Create("DListView", form)
	classList:Dock(FILL)
	classList:SetMultiSelect(false)
	classList:AddColumn("Class")

	local allClasses = GetAllClasses()
	local selectedClass = nil

	local function RefreshClassList(filter)
		classList:Clear()
		filter = filter and filter:lower() or ""
		local shown = 0
		for _, entry in ipairs(allClasses) do
			if shown >= 150 then break end
			if filter == "" or entry.Class:lower():find(filter, 1, true) then
				local line = classList:AddLine(entry.Print)
				line.pdcityClass = entry.Class
				shown = shown + 1
			end
		end
	end
	RefreshClassList("")

	searchEntry.OnValueChange = function(self, val) RefreshClassList(val) end
	classList.OnRowSelected = function(self, index, row) selectedClass = row.pdcityClass end

	addBtn.DoClick = function()
		if not selectedClass then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Pick a class from the search list first.")
			return
		end
		SendPhysgunAdminAction("add", selectedClass)
	end

	local listHolder = vgui.Create("DPanel", root)
	listHolder.Paint = function() end

	local listView = BuildManagedList(listHolder, { "Allowed class" }, nil,
		function(class)
			SendPhysgunAdminAction("remove", class)
		end
	)

	local function RefreshAllowedList()
		listView:Clear()
		for _, class in ipairs(PDCity.PHYSGUN_WHITELIST) do
			local line = listView:AddLine(class)
			line.pdcityID = class
		end
	end
	RefreshAllowedList()

	local Reflow = PDCity.MakeSplitter(root, formHolder, listHolder, physgunTabSplit)
	root.PerformLayout = function(self, w, h) Reflow(w, h) end

	root.PDCityRefresh = function()
		RefreshAllowedList()
	end

	return root

end

--[[---------------------------------------------------------
	Activities (core/sh_activities.lua) - ties an entity class to a job,
	so only players on that job can +use entities of that class, and a
	named hook fires when they do. Deliberately minimal (see that file's
	own header): no timer/reward UI here, just the wiring - what actually
	happens on use is up to whatever hooks HookName, built separately
	(addons/pdroleplay_modification).
-----------------------------------------------------------]]
local function BuildActivitiesTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(420)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	--[[-----------------------------------------------------
		Class grid column, between the form and the list. One grid serves
		both class fields - the switch above it picks which one a click
		fills in.
	-------------------------------------------------------]]
	local PICK_MAIN, PICK_FILL = 1, 2
	local OnGridPick -- forward declared: set once the form fields below exist

	local pickerPane = vgui.Create("DPanel", root)
	pickerPane:Dock(LEFT)
	pickerPane:SetWide(380)
	pickerPane:DockMargin(0, 0, 12, 0)
	pickerPane.Paint = function() end

	local modeRow = vgui.Create("DPanel", pickerPane)
	modeRow:Dock(TOP)
	modeRow:SetTall(26)
	modeRow:DockMargin(0, 0, 0, 8)
	modeRow.Paint = function() end

	local modeLabel = vgui.Create("DLabel", modeRow)
	modeLabel:Dock(LEFT)
	modeLabel:SetWide(110)
	modeLabel:SetText("Clicking a class:")
	modeLabel:SetTextColor(PDCity.THEME.TextDim)

	local modeCombo = vgui.Create("DComboBox", modeRow)
	modeCombo:Dock(FILL)
	modeCombo:SetSortItems(false)
	modeCombo:AddChoice("Sets the activity's class", PICK_MAIN, true)
	modeCombo:AddChoice("Adds a fill item class", PICK_FILL)

	local classPicker = PDCity.BuildEntityClassPicker(pickerPane, function(entry)
		local _, mode = modeCombo:GetSelected()
		OnGridPick(entry, mode or PICK_MAIN)
	end, { Header = "Entity Class" })
	classPicker:Dock(FILL)

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	local formHolder = vgui.Create("DPanel", leftPane)
	formHolder:Dock(FILL)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(10, 10, 10, 10)

	local intro = vgui.Create("DLabel", form)
	intro:Dock(TOP)
	intro:SetTall(50)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetText("Ties an entity class to a job. Staff still spawn/place the entity itself (Q menu) - this only decides who can use it, and what hook fires when they do. Only entities that already implement Use will ever fire anything.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local selectedClass = nil

	local selectedLabel = vgui.Create("DLabel", form)
	selectedLabel:Dock(TOP)
	selectedLabel:SetTall(20)
	selectedLabel:DockMargin(0, 6, 0, 0)
	selectedLabel:SetText("Selected class: (none) - pick one from the class grid")
	selectedLabel:SetTextColor(PDCity.THEME.TextDim)

	local nameEntry -- forward declared, filled in by the class picker below
	local hookEntry -- forward declared, filled in by the class picker below

	local function OnClassPicked(entry)
		selectedClass = entry.Class
		selectedLabel:SetText("Selected class: " .. selectedClass)
		if nameEntry:GetValue() == "" then
			nameEntry:SetValue(PDCity.PrettifyClassName(selectedClass))
		end
		if hookEntry:GetValue() == "" then
			hookEntry:SetValue(PDCity.SuggestActivityHookName(nameEntry:GetValue()))
		end
	end

	nameEntry = vgui.Create("DTextEntry", form)
	nameEntry:Dock(TOP)
	nameEntry:SetTall(26)
	nameEntry:DockMargin(0, 6, 0, 0)
	nameEntry:SetPlaceholderText("Display name (admin UI only, players never see this)")
	-- Keeps the hook-name suggestion following the name for as long as
	-- the admin hasn't typed their own hook name yet - same "only
	-- auto-fill an untouched field" idea as OnClassPicked's own name
	-- auto-fill above.
	nameEntry.OnValueChange = function(self, val)
		if hookEntry and (hookEntry:GetValue() == "" or hookEntry.pdcityAutoFilled) then
			hookEntry:SetValue(PDCity.SuggestActivityHookName(val))
			hookEntry.pdcityAutoFilled = true
		end
	end

	hookEntry = vgui.Create("DTextEntry", form)
	hookEntry:Dock(TOP)
	hookEntry:SetTall(26)
	hookEntry:DockMargin(0, 6, 0, 0)
	hookEntry:SetPlaceholderText("Hook name fired on trigger (auto-filled, editable)")
	hookEntry.OnValueChange = function(self) self.pdcityAutoFilled = false end

	--[[-----------------------------------------------------
		Trigger type - "Use" (default) fires on +use, same as any normal
		interactable entity; "Collide" fires when another entity touches
		it (a thrown/dropped item, for a "put ingredients in the barrel"
		style interaction) - only meaningful for the model kind (a
		Class-based activity's own entity decides its own collision
		behaviour, this shim can't add touch detection to code it doesn't
		own). Two checkboxes acting as a mutually-exclusive pair, same
		trick cl_site_admin.lua's Prop Filter tab uses for its own
		whitelist/blacklist toggle.
	-------------------------------------------------------]]
	local triggerLabel = vgui.Create("DLabel", form)
	triggerLabel:Dock(TOP)
	triggerLabel:SetTall(18)
	triggerLabel:DockMargin(0, 8, 0, 0)
	triggerLabel:SetText("Fires when a player:")
	triggerLabel:SetTextColor(PDCity.THEME.TextDim)

	local useCheck = vgui.Create("DCheckBoxLabel", form)
	useCheck:Dock(TOP)
	useCheck:SetTall(20)
	useCheck:SetText("Presses USE (E) on it")
	useCheck:SetTextColor(PDCity.THEME.Text)
	useCheck:SetChecked(true)

	local collideCheck = vgui.Create("DCheckBoxLabel", form)
	collideCheck:Dock(TOP)
	collideCheck:SetTall(20)
	collideCheck:SetText("Touches it with another entity (model kind only)")
	collideCheck:SetTextColor(PDCity.THEME.Text)

	useCheck.OnChange = function(self, checked) if checked then collideCheck:SetChecked(false) end end
	collideCheck.OnChange = function(self, checked) if checked then useCheck:SetChecked(false) end end

	--[[-----------------------------------------------------
		Fill item classes - which entity classes count as a valid "fill"
		item for a Collide-triggered activity (blank = anything touching
		it counts). Picked via the same entity picker used for the main
		Class field above (its own "Only entities I've made" filter makes
		this fast when the fill item is one of your own Custom Props),
		not typed by hand - a raw comma-separated text box meant typing
		the exact class string blind, with no validation or spawnable-
		class lookup at all.
	-------------------------------------------------------]]
	local fillClassesLabel = vgui.Create("DLabel", form)
	fillClassesLabel:Dock(TOP)
	fillClassesLabel:SetTall(18)
	fillClassesLabel:DockMargin(0, 6, 0, 0)
	fillClassesLabel:SetText("Fill item classes (blank = anything touching it counts):")
	fillClassesLabel:SetTextColor(PDCity.THEME.TextDim)

	local fillClasses = {} -- array of class strings - current form state
	local RefreshFillClassesUI -- forward declared, defined right after the holder below

	local fillClassesHolder = vgui.Create("DScrollPanel", form)
	fillClassesHolder:Dock(TOP)
	fillClassesHolder:SetTall(60)
	fillClassesHolder:DockMargin(0, 4, 0, 0)
	PDCity.ApplyFastScroll(fillClassesHolder)

	RefreshFillClassesUI = function()
		fillClassesHolder:Clear()
		for i, class in ipairs(fillClasses) do
			local row = vgui.Create("DPanel", fillClassesHolder)
			row:Dock(TOP)
			row:SetTall(22)
			row:DockMargin(0, 0, 4, 2)
			row.Paint = function(self, w, h) draw.RoundedBox(3, 0, 0, w, h, PDCity.THEME.Panel) end

			local lbl = vgui.Create("DLabel", row)
			lbl:Dock(FILL)
			lbl:DockMargin(6, 0, 0, 0)
			lbl:SetFont("PDCity_Small")
			lbl:SetText(class)
			lbl:SetTextColor(PDCity.THEME.Text)

			local rm = vgui.Create("DButton", row)
			rm:Dock(RIGHT)
			rm:SetWide(22)
			rm:SetText("")
			rm.Paint = function(self, w, h)
				draw.RoundedBox(3, 0, 0, w, h, self:IsHovered() and Color(190, 70, 70) or PDCity.THEME.PanelHover)
				draw.SimpleText("x", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			rm.DoClick = function()
				table.remove(fillClasses, i)
				RefreshFillClassesUI()
			end
		end
	end

	-- Switches the class grid over to adding fill classes.
	local addFillClassBtn = vgui.Create("DButton", form)
	addFillClassBtn:Dock(TOP)
	addFillClassBtn:SetTall(24)
	addFillClassBtn:DockMargin(0, 2, 0, 0)
	PDCity.StyleButton(addFillClassBtn, "+ Add Fill Classes (pick in the class grid)", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	addFillClassBtn.DoClick = function() modeCombo:ChooseOptionID(PICK_FILL) end

	OnGridPick = function(entry, mode)
		if mode == PICK_FILL then
			if not table.HasValue(fillClasses, entry.Class) then
				table.insert(fillClasses, entry.Class)
				RefreshFillClassesUI()
			end
		else
			OnClassPicked(entry)
		end
	end

	local jobsLabel = vgui.Create("DLabel", form)
	jobsLabel:Dock(TOP)
	jobsLabel:SetTall(18)
	jobsLabel:DockMargin(0, 8, 0, 0)
	jobsLabel:SetText("Job roles allowed to use it (none checked = everyone):")
	jobsLabel:SetTextColor(PDCity.THEME.TextDim)

	local jobsScroll = vgui.Create("DScrollPanel", form)
	jobsScroll:Dock(TOP)
	jobsScroll:SetTall(140)
	jobsScroll:DockMargin(0, 4, 0, 0)

	local jobCheckboxes = {}
	for _, id in ipairs(PDCity.GetSortedJobIDs()) do
		local job = PDCity.GetJob(id)
		if job then
			local chk = vgui.Create("DCheckBoxLabel", jobsScroll)
			chk:SetText(job.Name)
			chk:Dock(TOP)
			chk:DockMargin(2, 2, 0, 0)
			chk:SetTextColor(PDCity.THEME.Text)
			jobCheckboxes[id] = chk
		end
	end

	local editingID = nil -- set while an existing activity is loaded for editing, same pattern as the other tabs

	local addBtn = vgui.Create("DButton", form)
	addBtn:Dock(TOP)
	addBtn:SetTall(28)
	addBtn:DockMargin(0, 10, 0, 0)
	local addBtnLabel = "Add Activity"
	PDCity.StyleButton(addBtn, addBtnLabel)

	local cancelEditBtn = vgui.Create("DButton", form)
	cancelEditBtn:Dock(TOP)
	cancelEditBtn:SetTall(22)
	cancelEditBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(cancelEditBtn, "Cancel Edit (Start a New Activity Instead)", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelEditBtn:SetVisible(false)

	-- Only meaningful once an existing activity is loaded for editing - a
	-- flowchart attaches to a saved activity's ID, there's nothing to
	-- edit yet for one that's still being created.
	local flowBtn = vgui.Create("DButton", form)
	flowBtn:Dock(TOP)
	flowBtn:SetTall(26)
	flowBtn:DockMargin(0, 6, 0, 0)
	PDCity.StyleButton(flowBtn, "Edit Flowchart...", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	flowBtn:SetVisible(false)

	local function ResetForm()
		editingID = nil
		selectedClass = nil
		selectedLabel:SetText("Selected class: (none) - pick one from the class grid")
		modeCombo:ChooseOptionID(PICK_MAIN)
		nameEntry:SetValue("")
		hookEntry:SetValue("")
		hookEntry.pdcityAutoFilled = false
		useCheck:SetChecked(true)
		collideCheck:SetChecked(false)
		fillClasses = {}
		RefreshFillClassesUI()
		for _, chk in pairs(jobCheckboxes) do chk:SetChecked(false) end
		addBtnLabel = "Add Activity"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(false)
		flowBtn:SetVisible(false)
	end

	cancelEditBtn.DoClick = ResetForm
	flowBtn.DoClick = function()
		if editingID then PDCity.OpenFlowEditor(editingID, nameEntry:GetValue()) end
	end

	addBtn.DoClick = function()
		if not selectedClass then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Choose an entity class first.")
			return
		end

		local jobs = {}
		for id, chk in pairs(jobCheckboxes) do
			if chk:GetChecked() then table.insert(jobs, id) end
		end

		local payload = {
			ID = editingID,
			Class = selectedClass,
			Name = nameEntry:GetValue() ~= "" and nameEntry:GetValue() or PDCity.PrettifyClassName(selectedClass),
			HookName = hookEntry:GetValue(),
			Jobs = jobs,
			TriggerType = collideCheck:GetChecked() and "collide" or "use",
			FillClasses = (collideCheck:GetChecked() and #fillClasses > 0) and fillClasses or nil,
		}

		SendActivityAdminAction(editingID and "edit" or "add", payload)
		ResetForm()
	end

	local listView = BuildManagedList(rightPane, { "Name", "Class", "Trigger", "Jobs" }, nil,
		function(id)
			if editingID == id then ResetForm() end
			SendActivityAdminAction("remove", { ID = id })
		end
	)

	listView.OnRowSelected = function(self, index, row)
		local activity
		for _, a in ipairs(PDCity.ACTIVITIES) do
			if a.ID == row.pdcityID then activity = a break end
		end
		if not activity then return end

		editingID = activity.ID
		hookEntry:SetValue(activity.HookName or "")
		hookEntry.pdcityAutoFilled = false
		nameEntry:SetValue(activity.Name or "")
		selectedClass = activity.Class
		selectedLabel:SetText("Selected class: " .. activity.Class)

		local collide = activity.TriggerType == "collide"
		useCheck:SetChecked(not collide)
		collideCheck:SetChecked(collide)
		fillClasses = {}
		for _, class in ipairs(activity.FillClasses or {}) do table.insert(fillClasses, class) end
		RefreshFillClassesUI()

		local wanted = {}
		for _, id in ipairs(activity.Jobs or {}) do wanted[id] = true end
		for id, chk in pairs(jobCheckboxes) do
			chk:SetChecked(wanted[id] == true)
		end

		addBtnLabel = "Save Changes"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(true)
		flowBtn:SetVisible(true)
	end

	local function JobNamesFor(activity)
		if not activity.Jobs or #activity.Jobs == 0 then return "Everyone" end
		local names = {}
		for _, id in ipairs(activity.Jobs) do
			local job = PDCity.GetJob(id)
			table.insert(names, job and job.Name or ("#" .. id))
		end
		return table.concat(names, ", ")
	end

	local function RefreshActivityList()
		listView:Clear()
		for _, activity in ipairs(PDCity.ACTIVITIES) do
			local trigger = activity.TriggerType == "collide" and "Collide" or "Use"
			local line = listView:AddLine(activity.Name, activity.Class, trigger, JobNamesFor(activity))
			line.pdcityID = activity.ID
		end
	end
	RefreshActivityList()

	root.PDCityRefresh = function()
		RefreshActivityList()
	end

	return root

end

--[[---------------------------------------------------------
	NPCs (core/sh_npc_classes.lua) - owner-made custom NPCs, name + model
	only. Every one created here automatically shows up in the NPC
	Spawner tool's dropdown (entities/weapons/gmod_tool/stools/pdcity_npcspawner.lua) -
	that tool already reads its list from PDCity.GetAllNPCClasses(),
	which merges this with the hardcoded ones, so there's nothing else
	to wire up. No dialogue/behaviour here - a placed NPC just stands
	there until something hooks "PDCity_CustomNPCUsed"
	(entities/entities/ent_pdcity_custom_npc.lua).
-----------------------------------------------------------]]
local function BuildNPCsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(460)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	-- Left column, top to bottom: the form, the model grid, Add/Cancel.
	-- Docked TOP, BOTTOM, then FILL - a FILL dock must come last.
	local formHolder = vgui.Create("DPanel", leftPane)
	formHolder:Dock(TOP)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local submitBar = vgui.Create("DPanel", leftPane)
	submitBar:Dock(BOTTOM)
	submitBar:SetTall(30)
	submitBar:DockMargin(0, 12, 0, 0)
	submitBar.Paint = function() end

	local OnModelPicked -- set once the model fields below exist
	local modelPicker = PDCity.BuildPlayerModelPicker(leftPane, function(model) OnModelPicked(model) end, { Header = "NPC Model" })
	modelPicker:Dock(FILL)
	modelPicker:DockMargin(0, 12, 0, 0)

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(10, 10, 10, 10)

	-- Sized to fit the form's contents, leaving the rest to the model grid
	-- (never less than MIN_GRID_TALL of it).
	local MIN_GRID_TALL = 220
	local SUBMIT_BAR_TALL = 42 -- bar height + its top margin
	formHolder.Think = function(self)
		local wanted = math.min(form:GetCanvas():GetTall() + 20, leftPane:GetTall() - MIN_GRID_TALL - SUBMIT_BAR_TALL)
		if wanted > 0 and math.abs(self:GetTall() - wanted) > 1 then self:SetTall(wanted) end
	end

	local intro = vgui.Create("DLabel", form)
	intro:Dock(TOP)
	intro:SetTall(46)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetText("Place these with the NPC Spawner toolgun tool, same as the Bail Bondsman - they'll appear in its dropdown automatically. Pick a model from the grid below, or type a model path.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local nameEntry = vgui.Create("DTextEntry", form)
	nameEntry:Dock(TOP)
	nameEntry:SetTall(26)
	nameEntry:DockMargin(0, 6, 0, 0)
	nameEntry:SetPlaceholderText("Display name")

	local modelRow = vgui.Create("DPanel", form)
	modelRow:Dock(TOP)
	modelRow:SetTall(54)
	modelRow:DockMargin(0, 6, 0, 0)
	modelRow.Paint = function() end

	local modelPreview = vgui.Create("SpawnIcon", modelRow)
	modelPreview:Dock(LEFT)
	modelPreview:SetWide(54)

	local modelEntry = vgui.Create("DTextEntry", modelRow)
	modelEntry:Dock(FILL)
	modelEntry:DockMargin(6, 14, 0, 14)
	modelEntry:SetPlaceholderText("models/player/kleiner.mdl")
	modelEntry.OnValueChange = function(self, val) modelPreview:SetModel(val) end

	-- The grid lists player models (player_manager.AllValidModels()) - a
	-- Custom NPC's model is just as often a reskinned citizen/player model
	-- as a job's own. Picking just fills modelEntry, so typing a model path
	-- by hand (an NPC-only model outside that list) keeps working too.
	OnModelPicked = function(model)
		modelEntry:SetValue(model)
		modelPreview:SetModel(model)
	end

	local editingID = nil

	local cancelEditBtn = vgui.Create("DButton", submitBar)
	cancelEditBtn:Dock(RIGHT)
	cancelEditBtn:SetWide(220)
	cancelEditBtn:DockMargin(8, 0, 0, 0)
	PDCity.StyleButton(cancelEditBtn, "Cancel Edit (Start a New NPC)", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelEditBtn:SetVisible(false)

	local addBtn = vgui.Create("DButton", submitBar)
	addBtn:Dock(FILL)
	local addBtnLabel = "Add NPC"
	PDCity.StyleButton(addBtn, addBtnLabel)

	local function ResetForm()
		editingID = nil
		nameEntry:SetValue("")
		modelEntry:SetValue("")
		modelPreview:SetModel("")
		addBtnLabel = "Add NPC"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(false)
	end

	cancelEditBtn.DoClick = ResetForm

	addBtn.DoClick = function()
		if nameEntry:GetValue() == "" or modelEntry:GetValue() == "" then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a name and a model first.")
			return
		end

		SendCustomNPCAdminAction(editingID and "edit" or "add", {
			ID = editingID,
			Name = nameEntry:GetValue(),
			Model = modelEntry:GetValue(),
		})
		ResetForm()
	end

	local listView = BuildManagedList(rightPane, { "Name", "Model" }, nil,
		function(id)
			if editingID == id then ResetForm() end
			SendCustomNPCAdminAction("remove", { ID = id })
		end
	)

	listView.OnRowSelected = function(self, index, row)
		local npc
		for _, n in ipairs(PDCity.CUSTOM_NPCS) do
			if n.ID == row.pdcityID then npc = n break end
		end
		if not npc then return end

		editingID = npc.ID
		nameEntry:SetValue(npc.Name or "")
		modelEntry:SetValue(npc.Model or "")
		modelPreview:SetModel(npc.Model or "")

		addBtnLabel = "Save Changes"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(true)
	end

	local function RefreshNPCList()
		listView:Clear()
		for _, npc in ipairs(PDCity.CUSTOM_NPCS) do
			local line = listView:AddLine(npc.Name, npc.Model)
			line.pdcityID = npc.ID
		end
	end
	RefreshNPCList()

	root.PDCityRefresh = function()
		RefreshNPCList()
	end

	return root

end

--[[---------------------------------------------------------
	Currencies tab (core/sh_currencies.lua) - owner-defined ADDITIONAL
	currencies (loyalty points, a premium currency, ...) alongside the
	gamemode's own built-in Money. Same shape as the NPCs tab just above:
	a form on the left, a managed list on the right, edit-by-clicking-a-row.
	Balances themselves aren't editable here - PDCity.AddCurrency/
	PDCity.RemoveCurrency (core/sv_currencies.lua) is a devcode/Flow API,
	same as Money, not something granted through this admin form.
-----------------------------------------------------------]]
local function BuildCurrenciesTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(360)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	local formHolder = vgui.Create("DPanel", leftPane)
	formHolder:Dock(FILL)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(10, 10, 10, 10)

	local intro = vgui.Create("DLabel", form)
	intro:Dock(TOP)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetAutoStretchVertical(true) -- grows to fit however many lines the wrap needs
	intro:SetText("Extra currencies alongside Money - loyalty points, a premium currency, event tokens. Balances are granted from devcode or a Flowchart (PDCity.AddCurrency), not here - this just defines what the currency IS.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local nameEntry = vgui.Create("DTextEntry", form)
	nameEntry:Dock(TOP)
	nameEntry:SetTall(26)
	nameEntry:DockMargin(0, 6, 0, 0)
	nameEntry:SetPlaceholderText("Display name (e.g. Loyalty Points)")

	local symbolEntry = vgui.Create("DTextEntry", form)
	symbolEntry:Dock(TOP)
	symbolEntry:SetTall(26)
	symbolEntry:DockMargin(0, 6, 0, 0)
	symbolEntry:SetPlaceholderText("Short symbol (e.g. LP)")

	local iconRow = vgui.Create("DPanel", form)
	iconRow:Dock(TOP)
	iconRow:SetTall(40)
	iconRow:DockMargin(0, 6, 0, 0)
	iconRow.Paint = function() end

	local iconPreview = vgui.Create("DImage", iconRow)
	iconPreview:Dock(LEFT)
	iconPreview:SetWide(28)
	iconPreview:DockMargin(0, 6, 0, 6)

	local iconEntry = vgui.Create("DTextEntry", iconRow)
	iconEntry:Dock(FILL)
	iconEntry:DockMargin(8, 0, 0, 0)
	iconEntry:SetPlaceholderText("Icon: pick one, or an image URL")
	iconEntry.OnValueChange = function(self, val) iconPreview:SetImage(val ~= "" and val or "icon16/coins.png") end

	local iconPickBtn = vgui.Create("DButton", iconRow)
	iconPickBtn:Dock(RIGHT)
	iconPickBtn:SetWide(28)
	iconPickBtn:DockMargin(4, 0, 0, 0)
	iconPickBtn:SetText("")
	iconPickBtn.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(Material("icon16/picture.png"))
		surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
	end
	iconPickBtn.DoClick = function()
		PDCity.OpenIconPicker(function(path)
			iconEntry:SetValue(path)
		end)
	end

	local editingID = nil

	local addBtn = vgui.Create("DButton", form)
	addBtn:Dock(TOP)
	addBtn:SetTall(28)
	addBtn:DockMargin(0, 10, 0, 0)
	local addBtnLabel = "Add Currency"
	PDCity.StyleButton(addBtn, addBtnLabel)

	local cancelEditBtn = vgui.Create("DButton", form)
	cancelEditBtn:Dock(TOP)
	cancelEditBtn:SetTall(22)
	cancelEditBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(cancelEditBtn, "Cancel Edit (Start a New Currency Instead)", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelEditBtn:SetVisible(false)

	local function ResetForm()
		editingID = nil
		nameEntry:SetValue("")
		symbolEntry:SetValue("")
		iconEntry:SetValue("")
		iconPreview:SetImage("icon16/coins.png")
		addBtnLabel = "Add Currency"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(false)
	end
	ResetForm()

	cancelEditBtn.DoClick = ResetForm

	addBtn.DoClick = function()
		if nameEntry:GetValue() == "" or symbolEntry:GetValue() == "" then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a name and a symbol first.")
			return
		end

		SendCurrencyAdminAction(editingID and "edit" or "add", {
			ID = editingID,
			Name = nameEntry:GetValue(),
			Symbol = symbolEntry:GetValue(),
			Icon = iconEntry:GetValue(),
		})
		ResetForm()
	end

	local listView = BuildManagedList(rightPane, { "Name", "Symbol" }, nil,
		function(id)
			if editingID == id then ResetForm() end
			SendCurrencyAdminAction("remove", { ID = id })
		end
	)

	listView.OnRowSelected = function(self, index, row)
		local currency
		for _, c in ipairs(PDCity.CURRENCIES) do
			if c.ID == row.pdcityID then currency = c break end
		end
		if not currency then return end

		editingID = currency.ID
		nameEntry:SetValue(currency.Name or "")
		symbolEntry:SetValue(currency.Symbol or "")
		iconEntry:SetValue(currency.Icon or "")
		iconPreview:SetImage(currency.Icon ~= "" and currency.Icon or "icon16/coins.png")

		addBtnLabel = "Save Changes"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(true)
	end

	local function RefreshCurrencyList()
		listView:Clear()
		for _, currency in ipairs(PDCity.CURRENCIES) do
			local line = listView:AddLine(currency.Name, currency.Symbol)
			line.pdcityID = currency.ID
		end
	end
	RefreshCurrencyList()

	root.PDCityRefresh = function()
		RefreshCurrencyList()
	end

	return root

end

local GMOD_TOOLS = {
	"axis", "balloon", "button", "cam", "colour", "dynamite", "elasticity",
	"eyeposer", "finger", "gravitgun", "hudcomposer", "lamp", "magnetic",
	"motor", "nail", "nocollide", "physprop", "pulley", "remover", "rope",
	"slider", "spring", "thrusters", "torch", "trails", "weight", "wheel",
	"weld", "winch"
}

local function BuildPlayerRanksTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(360)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	local formHolder = vgui.Create("DPanel", leftPane)
	formHolder:Dock(FILL)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(10, 10, 10, 10)

	local intro = vgui.Create("DLabel", form)
	intro:Dock(TOP)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetAutoStretchVertical(true)
	intro:SetText("Create and manage custom player ranks for toolgun access, cosmetics, or server features.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local nameEntry = vgui.Create("DTextEntry", form)
	nameEntry:Dock(TOP)
	nameEntry:SetTall(26)
	nameEntry:DockMargin(0, 6, 0, 0)
	nameEntry:SetPlaceholderText("Rank name (e.g. Donator)")

	local idEntry = vgui.Create("DTextEntry", form)
	idEntry:Dock(TOP)
	idEntry:SetTall(26)
	idEntry:DockMargin(0, 6, 0, 0)
	idEntry:SetPlaceholderText("Rank ID (e.g. donator - lowercase, no spaces)")

	local colorLabel = vgui.Create("DLabel", form)
	colorLabel:Dock(TOP)
	colorLabel:SetTall(18)
	colorLabel:DockMargin(0, 10, 0, 2)
	colorLabel:SetText("Rank colour")
	colorLabel:SetTextColor(PDCity.THEME.TextDim)

	-- Inline, not a popup - it fits in the form column as-is.
	local colorMixer = vgui.Create("DColorMixer", form)
	colorMixer:Dock(TOP)
	colorMixer:SetTall(170)
	colorMixer:SetPalette(false)
	colorMixer:SetAlphaBar(false)
	colorMixer:SetWangs(true)

	local rankColor = Color(100, 170, 255)
	colorMixer.ValueChanged = function(self, col)
		rankColor = Color(col.r, col.g, col.b)
	end

	local function SetRankColor(col)
		rankColor = Color(col.r, col.g, col.b)
		colorMixer:SetColor(rankColor)
	end

	local editingID = nil

	local addBtn = vgui.Create("DButton", form)
	addBtn:Dock(TOP)
	addBtn:SetTall(28)
	addBtn:DockMargin(0, 10, 0, 0)
	local addBtnLabel = "Add Rank"
	PDCity.StyleButton(addBtn, addBtnLabel)

	local cancelEditBtn = vgui.Create("DButton", form)
	cancelEditBtn:Dock(TOP)
	cancelEditBtn:SetTall(22)
	cancelEditBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(cancelEditBtn, "Cancel Edit", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelEditBtn:SetVisible(false)

	local function ResetForm()
		editingID = nil
		nameEntry:SetValue("")
		idEntry:SetValue("")
		SetRankColor(Color(100, 170, 255))
		addBtnLabel = "Add Rank"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(false)
	end
	ResetForm()

	cancelEditBtn.DoClick = ResetForm

	addBtn.DoClick = function()
		if nameEntry:GetValue() == "" or idEntry:GetValue() == "" then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter both a name and ID.")
			return
		end

		net.Start("pdcity_playerranks_admin")
			net.WriteString(util.TableToJSON({
				Action = editingID and "edit" or "add",
				ID = editingID or idEntry:GetValue(),
				Name = nameEntry:GetValue(),
				NewID = idEntry:GetValue(),
				Color = { r = rankColor.r, g = rankColor.g, b = rankColor.b }
			}))
		net.SendToServer()
		ResetForm()
	end

	local listView = BuildManagedList(rightPane, { "Name", "ID" }, nil,
		function(id)
			if editingID == id then ResetForm() end
			net.Start("pdcity_playerranks_admin")
				net.WriteString(util.TableToJSON({ Action = "remove", ID = id }))
			net.SendToServer()
		end
	)

	listView.OnRowSelected = function(self, index, row)
		local rank = PDCity.GetRankInfo(row.pdcityID)
		if not rank then return end

		editingID = rank.ID
		nameEntry:SetValue(rank.Name or "")
		idEntry:SetValue(rank.ID or "")
		SetRankColor(rank.Color or Color(255, 255, 255))

		addBtnLabel = "Save Changes"
		PDCity.StyleButton(addBtn, addBtnLabel)
		cancelEditBtn:SetVisible(true)
	end

	local function RefreshRankList()
		if not PDCity.GetAllPlayerRanks then
			timer.Simple(0.1, RefreshRankList)
			return
		end

		listView:Clear()
		local ranks = PDCity.GetAllPlayerRanks()
		if istable(ranks) then
			for _, rank in ipairs(ranks) do
				local line = listView:AddLine(rank.Name or rank.ID, rank.ID)
				line.pdcityID = rank.ID
			end
		end
	end
	RefreshRankList()

	root.PDCityRefresh = function()
		RefreshRankList()
	end

	return root

end

local function BuildToolgunToolsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local form = vgui.Create("DScrollPanel", root)
	form:Dock(FILL)
	form:DockMargin(10, 10, 10, 10)
	PDCity.ApplyFastScroll(form)

	local intro = vgui.Create("DLabel", form)
	intro:Dock(TOP)
	intro:SetTall(48)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetText("Control which toolgun tools are available and who can use them. Enable/disable each tool, then set access mode (everyone, whitelist, or blacklist).")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local toolList = vgui.Create("DListView", form)
	toolList:Dock(TOP)
	toolList:SetTall(200)
	toolList:DockMargin(0, 12, 0, 12)
	toolList:SetMultiSelect(false)
	toolList:AddColumn("Tool Name")
	toolList:AddColumn("Status")

	local availableTools = GMOD_TOOLS
	local toolConfigs = {}

	for _, toolName in ipairs(availableTools) do
		local line = toolList:AddLine(toolName, "Enabled")
		line.pdcityTool = toolName
		toolConfigs[toolName] = { Enabled = true, AccessMode = "everyone", Whitelist = {}, Blacklist = {} }
	end

	local modeLabel = vgui.Create("DLabel", form)
	modeLabel:Dock(TOP)
	modeLabel:SetTall(20)
	modeLabel:DockMargin(0, 0, 0, 4)
	modeLabel:SetFont("PDCity_Body")
	modeLabel:SetText("Settings for selected tool:")
	modeLabel:SetTextColor(PDCity.THEME.Text)

	local enabledCheck = vgui.Create("DCheckBoxLabel", form)
	enabledCheck:Dock(TOP)
	enabledCheck:SetTall(20)
	enabledCheck:DockMargin(0, 4, 0, 8)
	enabledCheck:SetText("Enabled")
	enabledCheck:SetTextColor(PDCity.THEME.Text)

	local modeCombo = vgui.Create("DComboBox", form)
	modeCombo:Dock(TOP)
	modeCombo:SetTall(26)
	modeCombo:DockMargin(0, 0, 0, 12)
	modeCombo:AddChoice("Everyone", "everyone", true)
	modeCombo:AddChoice("Whitelist (only specific people)", "whitelist")
	modeCombo:AddChoice("Blacklist (block specific people)", "blacklist")

	local entryList = vgui.Create("DListView", form)
	entryList:Dock(TOP)
	entryList:SetTall(100)
	entryList:DockMargin(0, 0, 0, 12)
	entryList:SetMultiSelect(false)
	entryList:AddColumn("Type")
	entryList:AddColumn("Value")

	local typeCombo = vgui.Create("DComboBox", form)
	typeCombo:Dock(TOP)
	typeCombo:SetTall(26)
	typeCombo:DockMargin(0, 0, 0, 6)
	typeCombo:AddChoice("SteamID", "steamid", true)
	typeCombo:AddChoice("Player Rank", "rank")
	typeCombo:AddChoice("Staff", "staff")

	local valueEntry = vgui.Create("DTextEntry", form)
	valueEntry:Dock(TOP)
	valueEntry:SetTall(26)
	valueEntry:DockMargin(0, 0, 0, 6)
	valueEntry:SetPlaceholderText("Value (SteamID, rank ID, or leave blank for Staff)")

	local addEntryBtn = vgui.Create("DButton", form)
	addEntryBtn:Dock(TOP)
	addEntryBtn:SetTall(26)
	PDCity.StyleButton(addEntryBtn, "Add Entry")

	local removeEntryBtn = vgui.Create("DButton", form)
	removeEntryBtn:Dock(TOP)
	removeEntryBtn:SetTall(26)
	removeEntryBtn:DockMargin(0, 4, 0, 12)
	PDCity.StyleButton(removeEntryBtn, "Remove Entry")

	local saveBtn = vgui.Create("DButton", form)
	saveBtn:Dock(TOP)
	saveBtn:SetTall(28)
	PDCity.StyleButton(saveBtn, "Save All Tool Settings")

	local selectedTool = nil

	local function RefreshToolSettings()
		if not selectedTool then
			enabledCheck:SetEnabled(false)
			modeCombo:SetEnabled(false)
			return
		end

		enabledCheck:SetEnabled(true)
		modeCombo:SetEnabled(true)

		local config = toolConfigs[selectedTool]
		enabledCheck:SetChecked(config.Enabled ~= false)
		modeCombo:SetValue(config.AccessMode or "everyone")

		entryList:Clear()
		local entries = config.AccessMode == "whitelist" and config.Whitelist or config.Blacklist
		if istable(entries) then
			for _, entry in ipairs(entries) do
				local line = entryList:AddLine(entry.Type, entry.Value)
				line.pdcityEntry = entry
			end
		end
	end

	toolList.OnRowSelected = function(self, index, row)
		selectedTool = row.pdcityTool
		RefreshToolSettings()
	end

	RefreshToolSettings()

	enabledCheck.OnChange = function(self, checked)
		if selectedTool then
			toolConfigs[selectedTool].Enabled = checked
			local line = toolList:GetSelected()
			if line and line[1] then
				line[1]:SetColumnText(2, checked and "Enabled" or "Disabled")
			end
		end
	end

	modeCombo.OnSelect = function(self, index, value, data)
		if selectedTool then
			toolConfigs[selectedTool].AccessMode = data
			RefreshToolSettings()
		end
	end

	addEntryBtn.DoClick = function()
		if not selectedTool then
			LocalPlayer():ChatPrint("Select a tool first")
			return
		end

		local type = typeCombo:GetSelectedID()
		local value = (type == "staff") and "" or valueEntry:GetValue()

		if type ~= "staff" and value == "" then
			LocalPlayer():ChatPrint("Enter a value first")
			return
		end

		local config = toolConfigs[selectedTool]
		local entries = config.AccessMode == "whitelist" and config.Whitelist or config.Blacklist
		table.insert(entries, { Type = type, Value = value })
		RefreshToolSettings()
		valueEntry:SetValue("")
	end

	removeEntryBtn.DoClick = function()
		if not selectedTool then return end
		local selected = entryList:GetSelected()
		if not selected or not selected[1] then return end
		local entry = selected[1].pdcityEntry
		local config = toolConfigs[selectedTool]
		local entries = config.AccessMode == "whitelist" and config.Whitelist or config.Blacklist
		table.RemoveByValue(entries, entry)
		RefreshToolSettings()
	end

	saveBtn.DoClick = function()
		net.Start("pdcity_toolgun_tools_admin")
			net.WriteString(util.TableToJSON(toolConfigs))
		net.SendToServer()
		LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Toolgun tool settings saved!")
	end

	return root

end

--[[---------------------------------------------------------
	Page - built inside the F1 menu's content area (cl_f1_menu.lua) as
	its owner-only "Catalogue" page (layout: cl_theme.lua's
	PDCity.BuildAdminPage).

	Owner-only, so every submission always applies immediately - no
	review queue, no reason bar.
-----------------------------------------------------------]]
function PDCity.BuildF4AdminPanel(parent)

	local previewHolder

	-- Centered over the page at the SAME width:height ratio as the
	-- player's screen - a panel built smaller with the same shape via
	-- PDCity.BuildF4PreviewPanel (cl_f4_menu.lua), not a scaled capture.
	local function RepositionPreview(pageW, pageH)
		if not IsValid(previewHolder) then return end
		local pw = math.floor(pageW * 0.55)
		local ph = math.floor(pw * (ScrH() / ScrW()))
		if ph > pageH - 90 then
			ph = pageH - 90
			pw = math.floor(ph * (ScrW() / ScrH()))
		end
		previewHolder:SetSize(pw, ph)
		previewHolder:SetPos((pageW - pw) / 2, (pageH - ph) / 2)
	end

	local tabs = {
		{ Name = "Entities", Build = BuildEntitiesTab },
		{ Name = "Jobs", Build = BuildJobsTab },
		{ Name = "Job Categories", Build = BuildJobCategoriesTab },
		{ Name = "Inventory Items", Build = BuildInventoryItemsTab },
		{ Name = "Physgun Whitelist", Build = BuildPhysgunWhitelistTab },
		{ Name = "Toolgun Tools", Build = BuildToolgunToolsTab },
		{ Name = "Activities", Build = BuildActivitiesTab },
		{ Name = "NPCs", Build = BuildNPCsTab },
		{ Name = "Currencies", Build = BuildCurrenciesTab },
		{ Name = "Player Ranks", Build = BuildPlayerRanksTab },
	}

	-- Which real F4 tab the live preview shows for a given admin tab -
	-- only Entities/Jobs have a direct F4-facing counterpart; the other
	-- two (Job Categories, Inventory Items) fall back to Jobs, the
	-- closer-related one of the two. Sections used to be its own tab
	-- here too, but it's now a popup opened from the Entities tab
	-- (OpenSectionsManager) instead of a sidebar entry.
	local PREVIEW_TAB_FOR = { [1] = "Entities", [2] = "Jobs" }

	local currentTabIndex = 1

	local function RefreshPreview()
		if not IsValid(previewHolder) or not previewHolder:IsVisible() then return end
		PDCity.BuildF4PreviewPanel(previewHolder, LocalPlayer(), PREVIEW_TAB_FOR[currentTabIndex] or "Jobs")
	end

	local root, sidebar, navBottom = PDCity.BuildAdminPage(parent, "Catalogue", tabs, function(index)
		currentTabIndex = index
		RefreshPreview()
	end)

	--[[-----------------------------------------------------
		Live preview - a non-interactive copy of the real F4 menu
		(PDCity.BuildF4PreviewPanel, cl_f4_menu.lua), projected over this
		page rather than replacing any of it. Toggled on/off rather than
		always built, since rebuilding it on every catalogue edit isn't
		free and there's no reason to pay that cost while nobody's looking.
	-------------------------------------------------------]]
	previewHolder = vgui.Create("DPanel", root)
	previewHolder:SetVisible(false)
	previewHolder.Paint = function(self, w, h)
		surface.SetDrawColor(PDCity.THEME.Accent)
		surface.DrawOutlinedRect(-2, -2, w + 4, h + 4, 2)
	end
	root.PerformLayout = function(self, w, h) RepositionPreview(w, h) end

	local previewToggleBtn = vgui.Create("DButton", sidebar)
	previewToggleBtn:SetPos(8, navBottom + 10)
	previewToggleBtn:SetSize(sidebar:GetWide() - 16, 28)
	local function UpdatePreviewToggleLabel()
		PDCity.StyleButton(previewToggleBtn, previewHolder:IsVisible() and "Disable Preview" or "Enable Preview",
			previewHolder:IsVisible() and { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim } or nil)
	end
	UpdatePreviewToggleLabel()
	previewToggleBtn.DoClick = function()
		previewHolder:SetVisible(not previewHolder:IsVisible())
		if previewHolder:IsVisible() then
			previewHolder:MoveToFront()
			RefreshPreview()
		end
		UpdatePreviewToggleLabel()
	end

	local function RefreshAllPanels()
		root.PDCityRefreshAll()
		RefreshPreview()
	end

	-- Keyed on the panel, so each hook removes itself when F1 closes.
	hook.Add("PDCity_F4CatalogueUpdated", root, RefreshAllPanels)
	hook.Add("PDCity_JobCatalogueUpdated", root, RefreshAllPanels)
	hook.Add("PDCity_InventoryWhitelistUpdated", root, RefreshAllPanels)
	hook.Add("PDCity_PhysgunWhitelistUpdated", root, RefreshAllPanels)
	hook.Add("PDCity_VehicleCatalogueUpdated", root, RefreshAllPanels)
	hook.Add("PDCity_ActivityCatalogueUpdated", root, RefreshAllPanels)
	hook.Add("PDCity_CustomNPCCatalogueUpdated", root, RefreshAllPanels)
	hook.Add("PDCity_CurrencyCatalogueUpdated", root, RefreshAllPanels)

	return root

end

concommand.Add("pdcity_f4admin", function()
	if PDCity.IsOwner(LocalPlayer()) then PDCity.OpenF1Menu("Catalogue") end
end)
