--[[---------------------------------------------------------
	Owner-only "Site Admin" editor, opened from the F1 menu (cl_f1_menu.lua's
	sidebar, gated the same way as this file's tab). Edits everything
	core/sh_site_content.lua holds: the Workshop collection link, the
	three welcome-screen boxes (cl_welcome.lua), and the F1 "Welcome"
	tab's news/update posts (cl_f1_menu.lua's CreateWelcomePanel).

	Every change is sent to the server as a single "pdcity_site_admin" net
	message (core/sv_site_content.lua does the actual validation and
	persistence - this file only builds the form and re-syncs from
	whatever the server broadcasts back).
-----------------------------------------------------------]]

local function SendSiteAdminAction(action, payload)
	payload = payload or {}
	payload.Action = action
	net.Start("pdcity_site_admin")
		net.WriteString(util.TableToJSON(payload))
	net.SendToServer()
end

local function SendLawSettingsAction(action, payload)
	payload = payload or {}
	payload.Action = action
	net.Start("pdcity_law_settings_admin")
		net.WriteString(util.TableToJSON(payload))
	net.SendToServer()
end

-- Rulebook edits go to their own receiver (core/sv_rules.lua) rather than
-- through the site-content one, since the rules are their own file and
-- their own saved JSON - the wrapper shape is identical either way.
local function SendRulesAction(action, payload)
	net.Start("pdcity_rules_admin")
		net.WriteString(util.TableToJSON({ Action = action, Payload = payload or {} }))
	net.SendToServer()
end

--[[---------------------------------------------------------
	Small reusable "list with up/down/remove buttons" - a trimmed copy of
	cl_f4_admin.lua's BuildManagedList (that one's a file-local, so not
	reachable from here) since this is the only place in this file that
	needs it.
-----------------------------------------------------------]]
local function BuildManagedList(parent, columns, onMove, onRemove, onSelect)

	local holder = vgui.Create("DPanel", parent)
	holder:Dock(FILL)
	holder.Paint = function() end

	local listView = vgui.Create("DListView", holder)
	listView:Dock(FILL)
	listView:DockMargin(0, 0, 0, 8)
	listView:SetMultiSelect(false)
	for _, col in ipairs(columns) do
		listView:AddColumn(col)
	end
	if onSelect then
		listView.OnRowSelected = function(self, index, row) onSelect(row.pdcityID) end
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
	Tab 1 - Workshop link
-----------------------------------------------------------]]
local function BuildWorkshopTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local label = vgui.Create("DLabel", root)
	label:Dock(TOP)
	label:SetTall(40)
	label:SetFont("PDCity_Small")
	label:SetWrap(true)
	label:SetText("The URL opened by \"OPEN COLLECTION\" on the welcome screen, the F1 Content tab's button, and !content in chat.")
	label:SetTextColor(PDCity.THEME.TextDim)

	local urlEntry = vgui.Create("DTextEntry", root)
	urlEntry:Dock(TOP)
	urlEntry:SetTall(28)
	urlEntry:DockMargin(0, 8, 0, 8)
	urlEntry:SetValue(PDCity.SITE_CONTENT.WorkshopURL or "")

	local saveBtn = vgui.Create("DButton", root)
	saveBtn:Dock(TOP)
	saveBtn:SetTall(30)
	PDCity.StyleButton(saveBtn, "Save Workshop URL")
	saveBtn.DoClick = function()
		SendSiteAdminAction("set_workshop_url", { URL = urlEntry:GetValue() })
	end

	root.PDCityRefresh = function()
		if not urlEntry:HasFocus() then
			urlEntry:SetValue(PDCity.SITE_CONTENT.WorkshopURL or "")
		end
	end

	return root

end

--[[---------------------------------------------------------
	Tab 2 - Welcome screen (the 3 fixed boxes cl_welcome.lua shows)
-----------------------------------------------------------]]
local function BuildWelcomeStepsTab(parent)

	local root = vgui.Create("DScrollPanel", parent)
	root:Dock(FILL)

	local entries = {}

	for i = 1, 3 do

		local step = PDCity.GetWelcomeStep(i)

		local box = vgui.Create("DPanel", root)
		box:Dock(TOP)
		box:SetTall(230)
		box:DockMargin(0, 0, 0, 12)
		box.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

		local heading = vgui.Create("DLabel", box)
		heading:SetPos(10, 8)
		heading:SetSize(300, 20)
		heading:SetFont("PDCity_Heading")
		heading:SetText("Box " .. i)
		heading:SetTextColor(PDCity.THEME.Text)

		local titleEntry = vgui.Create("DTextEntry", box)
		titleEntry:SetPos(10, 34)
		titleEntry:SetSize(box:GetWide() - 20, 26)
		titleEntry:SetPlaceholderText("Title")
		titleEntry:SetValue(step.Title)

		local bodyEntry = vgui.Create("DTextEntry", box)
		bodyEntry:SetPos(10, 66)
		bodyEntry:SetSize(box:GetWide() - 20, 60)
		bodyEntry:SetMultiline(true)
		bodyEntry:SetPlaceholderText("Body text")
		bodyEntry:SetValue(step.Body)

		local buttonEntry = vgui.Create("DTextEntry", box)
		buttonEntry:SetPos(10, 132)
		buttonEntry:SetSize(box:GetWide() - 20, 26)
		buttonEntry:SetPlaceholderText("Button label")
		buttonEntry:SetValue(step.Button)

		local imageEntry = vgui.Create("DTextEntry", box)
		imageEntry:SetPos(10, 164)
		imageEntry:SetSize(box:GetWide() - 20, 26)
		imageEntry:SetPlaceholderText("Image (material path, optional - e.g. pdcity/somebanner)")
		imageEntry:SetValue(step.Image)

		local saveBtn = vgui.Create("DButton", box)
		saveBtn:SetPos(10, 196)
		saveBtn:SetSize(box:GetWide() - 20, 26)
		PDCity.StyleButton(saveBtn, "Save Box " .. i)
		saveBtn.DoClick = function()
			SendSiteAdminAction("set_welcome_step", {
				Index = i,
				Title = titleEntry:GetValue(),
				Body = bodyEntry:GetValue(),
				Button = buttonEntry:GetValue(),
				Image = imageEntry:GetValue(),
			})
		end

		box.PerformLayout = function(self, w, h)
			titleEntry:SetWide(w - 20)
			bodyEntry:SetWide(w - 20)
			buttonEntry:SetWide(w - 20)
			imageEntry:SetWide(w - 20)
			saveBtn:SetWide(w - 20)
		end

		entries[i] = { Title = titleEntry, Body = bodyEntry, Button = buttonEntry, Image = imageEntry }

	end

	root.PDCityRefresh = function()
		for i, fields in ipairs(entries) do
			local step = PDCity.GetWelcomeStep(i)
			if not fields.Title:HasFocus() then fields.Title:SetValue(step.Title) end
			if not fields.Body:HasFocus() then fields.Body:SetValue(step.Body) end
			if not fields.Button:HasFocus() then fields.Button:SetValue(step.Button) end
			if not fields.Image:HasFocus() then fields.Image:SetValue(step.Image) end
		end
	end

	return root

end

--[[---------------------------------------------------------
	Tab 3 - News posts (F1 "Welcome" tab's cards)
-----------------------------------------------------------]]
local function BuildNewsPostsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(300)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	local editingID = nil

	local titleEntry = vgui.Create("DTextEntry", rightPane)
	titleEntry:Dock(TOP)
	titleEntry:SetTall(26)
	titleEntry:SetPlaceholderText("Post title")

	local bodyEntry = vgui.Create("DTextEntry", rightPane)
	bodyEntry:Dock(TOP)
	bodyEntry:SetTall(140)
	bodyEntry:DockMargin(0, 6, 0, 0)
	bodyEntry:SetMultiline(true)
	bodyEntry:SetPlaceholderText("Post body")

	local imageEntry = vgui.Create("DTextEntry", rightPane)
	imageEntry:Dock(TOP)
	imageEntry:SetTall(26)
	imageEntry:DockMargin(0, 6, 0, 0)
	imageEntry:SetPlaceholderText("Image (material path, optional)")

	local linkRow = vgui.Create("DPanel", rightPane)
	linkRow:Dock(TOP)
	linkRow:SetTall(26)
	linkRow:DockMargin(0, 6, 0, 0)
	linkRow.Paint = function() end

	local linkTextEntry = vgui.Create("DTextEntry", linkRow)
	linkTextEntry:Dock(LEFT)
	linkTextEntry:SetWide(140)
	linkTextEntry:SetPlaceholderText("Link label (optional)")

	local linkURLEntry = vgui.Create("DTextEntry", linkRow)
	linkURLEntry:Dock(FILL)
	linkURLEntry:DockMargin(6, 0, 0, 0)
	linkURLEntry:SetPlaceholderText("Link URL (optional)")

	local btnRow = vgui.Create("DPanel", rightPane)
	btnRow:Dock(TOP)
	btnRow:SetTall(30)
	btnRow:DockMargin(0, 8, 0, 0)
	btnRow.Paint = function() end

	local function ResetForm()
		editingID = nil
		titleEntry:SetValue("")
		bodyEntry:SetValue("")
		imageEntry:SetValue("")
		linkTextEntry:SetValue("")
		linkURLEntry:SetValue("")
	end

	local addBtn = vgui.Create("DButton", btnRow)
	addBtn:Dock(LEFT)
	addBtn:SetWide(140)
	PDCity.StyleButton(addBtn, "Post")
	addBtn.DoClick = function()
		local title = titleEntry:GetValue()
		local body = bodyEntry:GetValue()
		if title == "" or body == "" then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] A post needs both a title and body.")
			return
		end

		SendSiteAdminAction(editingID and "edit_post" or "add_post", {
			ID = editingID,
			Title = title,
			Body = body,
			Image = imageEntry:GetValue(),
			LinkText = linkTextEntry:GetValue(),
			LinkURL = linkURLEntry:GetValue(),
		})
		ResetForm()
	end

	local cancelBtn = vgui.Create("DButton", btnRow)
	cancelBtn:Dock(LEFT)
	cancelBtn:SetWide(100)
	cancelBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(cancelBtn, "Cancel", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelBtn.DoClick = ResetForm

	local function UpdateAddBtnLabel()
		PDCity.StyleButton(addBtn, editingID and "Save Changes" or "Post")
	end

	local listView = BuildManagedList(leftPane, { "Title" },
		function(id, dir)
			local order = {}
			for _, post in ipairs(PDCity.SITE_CONTENT.BlogPosts) do table.insert(order, post.ID) end

			local from
			for i, existingID in ipairs(order) do
				if existingID == id then from = i break end
			end
			if not from then return end

			local to = from + dir
			if to < 1 or to > #order then return end

			order[from], order[to] = order[to], order[from]
			SendSiteAdminAction("reorder_posts", { Order = order })
		end,
		function(id)
			if editingID == id then ResetForm() end
			SendSiteAdminAction("remove_post", { ID = id })
		end,
		function(id)
			for _, post in ipairs(PDCity.SITE_CONTENT.BlogPosts) do
				if post.ID == id then
					editingID = id
					titleEntry:SetValue(post.Title)
					bodyEntry:SetValue(post.Body)
					imageEntry:SetValue(post.Image or "")
					linkTextEntry:SetValue(post.LinkText or "")
					linkURLEntry:SetValue(post.LinkURL or "")
					UpdateAddBtnLabel()
					break
				end
			end
		end
	)

	local function RefreshList()
		listView:Clear()
		for _, post in ipairs(PDCity.SITE_CONTENT.BlogPosts) do
			local line = listView:AddLine(post.Title)
			line.pdcityID = post.ID
		end
	end
	RefreshList()

	root.PDCityRefresh = function()
		RefreshList()
		UpdateAddBtnLabel()
	end

	return root

end

--[[---------------------------------------------------------
	Tab - Prop Filter (core/sh_prop_filter.lua). Which way round the Q
	menu's prop whitelist works - "whitelist" (default-deny, nothing
	spawns for regular players unless explicitly whitelisted) or
	"blacklist" (default-allow, everything spawns unless explicitly
	blacklisted). The Prop Filter toolgun tool itself always works the
	same way either way (left click blacklists, right click
	whitelists) - this only changes what a model with NEITHER does.
-----------------------------------------------------------]]
local function BuildPropFilterTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local label = vgui.Create("DLabel", root)
	label:Dock(TOP)
	label:SetTall(40)
	label:SetFont("PDCity_Small")
	label:SetWrap(true)
	label:SetText("Controls what happens to a prop model NOBODY has explicitly whitelisted or blacklisted with the Prop Filter tool. The owner/superadmins can always spawn anything regardless of this setting.")
	label:SetTextColor(PDCity.THEME.TextDim)

	local optionAllow = vgui.Create("DCheckBoxLabel", root)
	optionAllow:Dock(TOP)
	optionAllow:SetTall(20)
	optionAllow:DockMargin(0, 8, 0, 0)
	optionAllow:SetText("All allowed by default - manually blacklist to block specific props")
	optionAllow:SetTextColor(PDCity.THEME.Text)

	local optionDeny = vgui.Create("DCheckBoxLabel", root)
	optionDeny:Dock(TOP)
	optionDeny:SetTall(20)
	optionDeny:DockMargin(0, 6, 0, 0)
	optionDeny:SetText("All blocked by default - manually whitelist to allow specific props")
	optionDeny:SetTextColor(PDCity.THEME.Text)

	local applying = false -- guards against OnChange firing itself while the pair is being kept in sync

	local function SendMode(mode)
		net.Start("pdcity_prop_filter_mode_admin")
			net.WriteString(mode)
		net.SendToServer()
	end

	local function Reflect()
		applying = true
		optionAllow:SetChecked(PDCity.PROP_FILTER_MODE == "blacklist")
		optionDeny:SetChecked(PDCity.PROP_FILTER_MODE == "whitelist")
		applying = false
	end
	Reflect()

	-- Two checkboxes acting as one either/or choice - simpler and more
	-- visually explicit than a dropdown for a binary "which one" pick,
	-- but needs each one to force the other off on click rather than
	-- letting both (or neither) end up checked.
	optionAllow.OnChange = function(self, checked)
		if applying then return end
		if not checked then Reflect() return end
		SendMode("blacklist")
	end

	optionDeny.OnChange = function(self, checked)
		if applying then return end
		if not checked then Reflect() return end
		SendMode("whitelist")
	end

	root.PDCityRefresh = function()
		Reflect()
	end

	return root

end

--[[---------------------------------------------------------
	Tab - Developers (core/sv_developers.lua). A narrower grant than
	owner/admin - the ONLY thing this list can do is write the Lua code
	behind a Job Activity's trigger, from the separate Developer Console
	("!devcode" in chat, cl_dev_console.lua). Not staff, not admin, not
	anything else - deciding who holds even this narrow power stays
	owner-only, same as everything else on this whole panel.
-----------------------------------------------------------]]
local function BuildDevelopersTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local label = vgui.Create("DLabel", root)
	label:Dock(TOP)
	label:SetTall(40)
	label:SetFont("PDCity_Small")
	label:SetWrap(true)
	label:SetText("Grants ONLY the ability to write custom code for Job Activities and NPCs (F1 > Developer Console, or \"!devcode\" in chat) - nothing else. Not staff, not admin. Enter a SteamID in STEAM_0:X:XXXXXXXX format.")
	label:SetTextColor(PDCity.THEME.TextDim)

	local addRow = vgui.Create("DPanel", root)
	addRow:Dock(TOP)
	addRow:SetTall(26)
	addRow:DockMargin(0, 6, 0, 0)
	addRow.Paint = function() end

	local steamIDEntry = vgui.Create("DTextEntry", addRow)
	steamIDEntry:Dock(FILL)
	steamIDEntry:SetPlaceholderText("STEAM_0:X:XXXXXXXX")

	local addBtn = vgui.Create("DButton", addRow)
	addBtn:Dock(RIGHT)
	addBtn:SetWide(90)
	addBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(addBtn, "Add")

	local listView = BuildManagedList(root, { "Name", "SteamID" }, nil, function(steamID)
		net.Start("pdcity_developers_admin")
			net.WriteString("remove")
			net.WriteString(steamID)
		net.SendToServer()
	end)

	addBtn.DoClick = function()
		local steamID = string.Trim(steamIDEntry:GetValue())
		if steamID == "" then return end

		net.Start("pdcity_developers_admin")
			net.WriteString("add")
			net.WriteString(steamID)
		net.SendToServer()

		steamIDEntry:SetValue("")
	end
	steamIDEntry.OnEnter = addBtn.DoClick

	local function RefreshList(list)
		listView:Clear()
		for _, dev in ipairs(list) do
			local line = listView:AddLine(dev.Name, dev.SteamID)
			line.pdcityID = dev.SteamID
		end
	end

	net.Receive("pdcity_developers_list", function()
		local list = util.JSONToTable(net.ReadString() or "[]") or {}
		RefreshList(list)
	end)

	local function RequestList()
		net.Start("pdcity_developers_admin")
			net.WriteString("list")
		net.SendToServer()
	end
	RequestList()

	root.PDCityRefresh = RequestList

	return root

end

--[[---------------------------------------------------------
	Tab - XP System (core/sh_xp_settings.lua). One on/off switch for the
	whole job-class XP/levelling system - see XP_SYSTEM.md (next to
	SETUP.md) for how to actually grant XP or add level-based rewards.
-----------------------------------------------------------]]
local function BuildXPSystemTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local label = vgui.Create("DLabel", root)
	label:Dock(TOP)
	label:SetTall(60)
	label:SetFont("PDCity_Small")
	label:SetWrap(true)
	label:SetText("Turns the whole job-class XP/levelling system on or off. While off: no XP is earned, no job stays locked behind a level requirement, and the F1 \"Job Levels\" tab shows as disabled. See XP_SYSTEM.md for how to wire up your own XP-earning activities or level rewards.")
	label:SetTextColor(PDCity.THEME.TextDim)

	local check = vgui.Create("DCheckBoxLabel", root)
	check:Dock(TOP)
	check:SetTall(24)
	check:DockMargin(0, 8, 0, 0)
	check:SetText("XP/levelling system enabled")
	check:SetTextColor(PDCity.THEME.Text)
	check:SetChecked(PDCity.XP_ENABLED)
	check.OnChange = function(self, checked)
		net.Start("pdcity_xp_settings_admin")
			net.WriteBool(checked)
		net.SendToServer()
	end

	root.PDCityRefresh = function()
		check:SetChecked(PDCity.XP_ENABLED)
	end

	return root

end

--[[---------------------------------------------------------
	Tab 4 - Warrant Approvers (core/sv_warrant_perms.lua). Who can
	approve/deny warrant requests (core/sv_wanted.lua) used to be
	hardcoded to "Government, class level 5+" - now any combination of
	usergroups, specific jobs, and class+level rules, any ONE of which is
	enough to qualify. Owner/superadmin can always approve regardless
	(not shown here - that's unconditional, same as everywhere else in
	this codebase).
-----------------------------------------------------------]]
local WARRANT_GROUPS = { "operator", "moderator", "admin", "superadmin", "owner" }

local function SendWarrantPermsAction(action, payload)
	payload = payload or {}
	payload.Action = action
	net.Start("pdcity_warrant_perms_admin")
		net.WriteString(util.TableToJSON(payload))
	net.SendToServer()
end

local function BuildWarrantApproversTab(parent)

	local root = vgui.Create("DScrollPanel", parent)
	root:Dock(FILL)

	local intro = vgui.Create("DLabel", root)
	intro:Dock(TOP)
	intro:SetTall(36)
	intro:DockMargin(0, 0, 0, 10)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetText("Anyone matching ANY rule below can approve/deny warrant requests. Owner and superadmins can always approve, regardless of these rules.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	--[[-------------------------------------------------------
		Usergroups
	---------------------------------------------------------]]
	local groupsHeading = vgui.Create("DLabel", root)
	groupsHeading:Dock(TOP)
	groupsHeading:SetTall(20)
	groupsHeading:SetFont("PDCity_Heading")
	groupsHeading:SetText("Usergroups")
	groupsHeading:SetTextColor(PDCity.THEME.Text)

	local groupChecks = {}
	for _, group in ipairs(WARRANT_GROUPS) do
		local check = vgui.Create("DCheckBoxLabel", root)
		check:Dock(TOP)
		check:SetTall(20)
		check:DockMargin(0, 4, 0, 0)
		check:SetText(group)
		check:SetTextColor(PDCity.THEME.Text)
		check:SetChecked(PDCity.WARRANT_PERMS.Groups[group] == true)
		check.OnChange = function(self, checked)
			SendWarrantPermsAction("set_group", { Group = group, Enabled = checked })
		end
		groupChecks[group] = check
	end

	--[[-------------------------------------------------------
		Specific jobs
	---------------------------------------------------------]]
	local jobsHeading = vgui.Create("DLabel", root)
	jobsHeading:Dock(TOP)
	jobsHeading:SetTall(20)
	jobsHeading:DockMargin(0, 14, 0, 0)
	jobsHeading:SetFont("PDCity_Heading")
	jobsHeading:SetText("Specific Jobs")
	jobsHeading:SetTextColor(PDCity.THEME.Text)

	local jobChecks = {}
	local jobIDs = {}
	for id in pairs(PDCity.JOBS) do table.insert(jobIDs, id) end
	table.sort(jobIDs)

	for _, id in ipairs(jobIDs) do
		local job = PDCity.GetJob(id)
		if job then
			local check = vgui.Create("DCheckBoxLabel", root)
			check:Dock(TOP)
			check:SetTall(20)
			check:DockMargin(0, 4, 0, 0)
			check:SetText(job.Name .. " (" .. job.Section .. ")")
			check:SetTextColor(PDCity.THEME.Text)
			check:SetChecked(PDCity.WARRANT_PERMS.Jobs[tostring(id)] == true)
			check.OnChange = function(self, checked)
				SendWarrantPermsAction("set_job", { JobID = id, Enabled = checked })
			end
			jobChecks[id] = check
		end
	end

	--[[-------------------------------------------------------
		Class + level rules (what "Government level 5+" used to be,
		generalized to any class/level pair, any number of them)
	---------------------------------------------------------]]
	local levelsHeading = vgui.Create("DLabel", root)
	levelsHeading:Dock(TOP)
	levelsHeading:SetTall(20)
	levelsHeading:DockMargin(0, 14, 0, 0)
	levelsHeading:SetFont("PDCity_Heading")
	levelsHeading:SetText("Class + Level")
	levelsHeading:SetTextColor(PDCity.THEME.Text)

	local levelsList = vgui.Create("DListView", root)
	levelsList:Dock(TOP)
	levelsList:SetTall(140)
	levelsList:DockMargin(0, 6, 0, 0)
	levelsList:SetMultiSelect(false)
	levelsList:AddColumn("Class")
	levelsList:AddColumn("Min. Level")

	local addRow = vgui.Create("DPanel", root)
	addRow:Dock(TOP)
	addRow:SetTall(28)
	addRow:DockMargin(0, 6, 0, 0)
	addRow.Paint = function() end

	local classCombo = vgui.Create("DComboBox", addRow)
	classCombo:Dock(LEFT)
	classCombo:SetWide(160)
	for _, section in ipairs(PDCity.SECTIONS) do
		classCombo:AddChoice(section)
	end

	local levelEntry = vgui.Create("DTextEntry", addRow)
	levelEntry:Dock(LEFT)
	levelEntry:SetWide(80)
	levelEntry:DockMargin(6, 0, 0, 0)
	levelEntry:SetNumeric(true)
	levelEntry:SetPlaceholderText("Level")

	local addLevelBtn = vgui.Create("DButton", addRow)
	addLevelBtn:Dock(LEFT)
	addLevelBtn:SetWide(100)
	addLevelBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(addLevelBtn, "Add / Update")
	addLevelBtn.DoClick = function()
		local class = classCombo:GetSelected()
		local level = tonumber(levelEntry:GetValue())
		if not class or not level then return end
		SendWarrantPermsAction("set_class_level", { Class = class, Level = level })
	end

	local removeLevelBtn = vgui.Create("DButton", root)
	removeLevelBtn:Dock(TOP)
	removeLevelBtn:SetTall(26)
	removeLevelBtn:DockMargin(0, 6, 0, 0)
	PDCity.StyleButton(removeLevelBtn, "Remove Selected Rule", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })
	removeLevelBtn.DoClick = function()
		local selected = levelsList:GetSelected()
		local row = selected and selected[1]
		if row then SendWarrantPermsAction("remove_class_level", { Class = row.pdcityClass }) end
	end

	local function RefreshLevelsList()
		levelsList:Clear()
		for class, level in pairs(PDCity.WARRANT_PERMS.ClassLevels) do
			local line = levelsList:AddLine(class, level)
			line.pdcityClass = class
		end
	end
	RefreshLevelsList()

	root.PDCityRefresh = function()
		for group, check in pairs(groupChecks) do
			check:SetChecked(PDCity.WARRANT_PERMS.Groups[group] == true)
		end
		for id, check in pairs(jobChecks) do
			check:SetChecked(PDCity.WARRANT_PERMS.Jobs[tostring(id)] == true)
		end
		RefreshLevelsList()
	end

	return root

end

--[[---------------------------------------------------------
	Tab - Door Factions (core/sh_door_factions.lua, core/sv_door_factions.lua).
	None ship by default. A player is a member if their current job's
	category is ticked here, OR the job itself ticks the faction in the F4
	admin editor's Jobs tab (shown read-only here).
-----------------------------------------------------------]]
local function SendDoorFactionAction(action, payload)
	payload = payload or {}
	payload.Action = action
	net.Start("pdcity_door_factions_admin")
		net.WriteString(util.TableToJSON(payload))
	net.SendToServer()
end

local function CountFactionDoors(factionID)
	local count = 0
	for _, id in pairs(DoorTable or {}) do
		if id == factionID then count = count + 1 end
	end
	return count
end

local function BuildDoorFactionsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local intro = vgui.Create("DLabel", root)
	intro:Dock(TOP)
	intro:SetTall(48)
	intro:DockMargin(0, 0, 0, 8)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetText("Factions own doors as a group - assign doors with the Door Faction tool (Q menu > PD Roleplay). A player can lock/unlock a faction's doors if their current job's category is ticked here, or the job itself has the faction ticked in F4 > Jobs.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(260)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	local selectedID = nil
	local LoadEditor -- forward declared: the list's select handler and refresh both call it

	--[[-------------------------------------------------------
		Left: create + list
	---------------------------------------------------------]]
	local createRow = vgui.Create("DPanel", leftPane)
	createRow:Dock(TOP)
	createRow:SetTall(26)
	createRow.Paint = function() end

	local newNameEntry = vgui.Create("DTextEntry", createRow)
	newNameEntry:Dock(FILL)
	newNameEntry:SetPlaceholderText("New faction name")

	local createBtn = vgui.Create("DButton", createRow)
	createBtn:Dock(RIGHT)
	createBtn:SetWide(80)
	createBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(createBtn, "Create")
	createBtn.DoClick = function()
		local name = string.Trim(newNameEntry:GetValue())
		if name == "" then return end
		SendDoorFactionAction("create", { Name = name })
		newNameEntry:SetValue("")
	end
	newNameEntry.OnEnter = createBtn.DoClick

	local listView = vgui.Create("DListView", leftPane)
	listView:Dock(FILL)
	listView:DockMargin(0, 8, 0, 0)
	listView:SetMultiSelect(false)
	listView:AddColumn("Faction")
	listView:AddColumn("Doors"):SetFixedWidth(50)
	listView.OnRowSelected = function(self, index, row)
		selectedID = row.pdcityID
		LoadEditor()
	end

	--[[-------------------------------------------------------
		Right: editor for the selected faction
	---------------------------------------------------------]]
	local emptyHint = vgui.Create("DLabel", rightPane)
	emptyHint:Dock(TOP)
	emptyHint:SetTall(20)
	emptyHint:SetFont("PDCity_Small")
	emptyHint:SetTextColor(PDCity.THEME.TextDim)

	local editor = vgui.Create("DScrollPanel", rightPane)
	editor:Dock(FILL)
	PDCity.ApplyFastScroll(editor)

	local function Heading(text, topMargin)
		local label = vgui.Create("DLabel", editor)
		label:Dock(TOP)
		label:SetTall(20)
		label:DockMargin(0, topMargin or 0, 0, 0)
		label:SetFont("PDCity_Heading")
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.Text)
		return label
	end

	local function Hint(text)
		local label = vgui.Create("DLabel", editor)
		label:Dock(TOP)
		label:SetTall(32)
		label:DockMargin(0, 2, 6, 0)
		label:SetFont("PDCity_Small")
		label:SetWrap(true)
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.TextDim)
		return label
	end

	Heading("Name")

	local renameRow = vgui.Create("DPanel", editor)
	renameRow:Dock(TOP)
	renameRow:SetTall(26)
	renameRow:DockMargin(0, 6, 6, 0)
	renameRow.Paint = function() end

	local renameEntry = vgui.Create("DTextEntry", renameRow)
	renameEntry:Dock(FILL)

	local renameBtn = vgui.Create("DButton", renameRow)
	renameBtn:Dock(RIGHT)
	renameBtn:SetWide(90)
	renameBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(renameBtn, "Rename")
	renameBtn.DoClick = function()
		if not selectedID then return end
		SendDoorFactionAction("rename", { ID = selectedID, Name = renameEntry:GetValue() })
	end
	renameEntry.OnEnter = renameBtn.DoClick

	Heading("Categories", 16)
	Hint("Every job in a ticked category is a member of this faction.")

	local sectionHolder = vgui.Create("DPanel", editor)
	sectionHolder:Dock(TOP)
	sectionHolder.Paint = function() end

	Heading("Individual Jobs", 16)
	Hint("Jobs that tick this faction themselves. Change these in F4 > Jobs.")

	local jobsLabel = vgui.Create("DLabel", editor)
	jobsLabel:Dock(TOP)
	jobsLabel:DockMargin(0, 4, 6, 0)
	jobsLabel:SetFont("PDCity_Small")
	jobsLabel:SetWrap(true)
	jobsLabel:SetAutoStretchVertical(true)
	jobsLabel:SetTextColor(PDCity.THEME.Text)

	-- Two clicks rather than a popup - same pattern as the Rules tab's
	-- reset. Deleting also clears this faction off every door it owns.
	local deleteBtn = vgui.Create("DButton", editor)
	deleteBtn:Dock(TOP)
	deleteBtn:SetTall(28)
	deleteBtn:DockMargin(0, 20, 6, 0)

	local deleteArmed = false
	local function DisarmDelete()
		deleteArmed = false
		PDCity.StyleButton(deleteBtn, "Delete Faction", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	end
	DisarmDelete()

	deleteBtn.DoClick = function(self)
		if not selectedID then return end

		if deleteArmed then
			SendDoorFactionAction("delete", { ID = selectedID })
			DisarmDelete()
			return
		end

		deleteArmed = true
		local doors = CountFactionDoors(selectedID)
		PDCity.StyleButton(self, "Click again to delete (clears " .. doors .. " door" .. (doors == 1 and "" or "s") .. ")", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })

		timer.Simple(4, function()
			if IsValid(self) and deleteArmed then DisarmDelete() end
		end)
	end

	local function RebuildSections(faction)
		sectionHolder:Clear()

		for _, section in ipairs(PDCity.SECTIONS) do
			local check = vgui.Create("DCheckBoxLabel", sectionHolder)
			check:Dock(TOP)
			check:SetTall(20)
			check:DockMargin(0, 4, 0, 0)
			check:SetText(section)
			check:SetTextColor(PDCity.THEME.Text)
			check:SetChecked(faction.Sections[section] == true)
			check.OnChange = function(self, checked)
				SendDoorFactionAction("set_section", { ID = faction.ID, Section = section, Enabled = checked })
			end
		end

		sectionHolder:SetTall(math.max(24, #PDCity.SECTIONS * 24))
	end

	local function RefreshJobsLabel(faction)
		local names = {}
		for _, id in ipairs(PDCity.GetSortedJobIDs()) do
			local job = PDCity.GetJob(id)
			if job and table.HasValue(job.DoorFactions or {}, faction.ID) then
				table.insert(names, job.Name)
			end
		end

		jobsLabel:SetText(#names > 0 and table.concat(names, ", ") or "None.")
	end

	LoadEditor = function()
		local faction = selectedID and PDCity.DOOR_FACTIONS[selectedID]

		editor:SetVisible(faction ~= nil)
		emptyHint:SetVisible(faction == nil)
		emptyHint:SetText(table.IsEmpty(PDCity.DOOR_FACTIONS)
			and "No factions yet - create one on the left."
			or "Select a faction on the left to edit it.")

		if not faction then return end

		if not renameEntry:HasFocus() then renameEntry:SetValue(faction.Name) end
		RebuildSections(faction)
		RefreshJobsLabel(faction)
		DisarmDelete()
		editor:InvalidateLayout()
	end

	local function RefreshList()
		listView:Clear()

		local factions = PDCity.GetSortedDoorFactions()
		local selectedLine = nil

		for _, faction in ipairs(factions) do
			local line = listView:AddLine(faction.Name, CountFactionDoors(faction.ID))
			line.pdcityID = faction.ID
			if faction.ID == selectedID then selectedLine = line end
		end

		if selectedLine then
			listView:SelectItem(selectedLine)
		else
			selectedID = nil
		end

		LoadEditor()
	end
	RefreshList()

	root.PDCityRefresh = RefreshList

	-- Jobs/categories are edited from the F4 admin editor, which doesn't
	-- fire PDCity_SiteContentUpdated.
	hook.Add("PDCity_JobCatalogueUpdated", root, function() RefreshList() end)

	return root

end

--[[---------------------------------------------------------
	Laws & Rewards tab (core/sh_laws.lua/core/sv_law_settings.lua) - the
	arrest menu's law list (name + min/max sentence years) on the right,
	and the jail system's three money knobs (officer pay per year,
	bail per minute, disconnect penalty per minute) on the left.
-----------------------------------------------------------]]
local function BuildLawsAndRewardsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local leftPane = vgui.Create("DPanel", root)
	leftPane:Dock(LEFT)
	leftPane:SetWide(300)
	leftPane:DockMargin(0, 0, 12, 0)
	leftPane.Paint = function() end

	local rightPane = vgui.Create("DPanel", root)
	rightPane:Dock(FILL)
	rightPane.Paint = function() end

	--[[-------------------------------------------------------
		Rewards
	---------------------------------------------------------]]
	local rewardsHeading = vgui.Create("DLabel", leftPane)
	rewardsHeading:Dock(TOP)
	rewardsHeading:SetTall(20)
	rewardsHeading:SetFont("PDCity_Heading")
	rewardsHeading:SetText("Jail Rewards")
	rewardsHeading:SetTextColor(PDCity.THEME.Text)

	local function RewardField(labelText)
		local rowLabel = vgui.Create("DLabel", leftPane)
		rowLabel:Dock(TOP)
		rowLabel:SetTall(18)
		rowLabel:DockMargin(0, 8, 0, 0)
		rowLabel:SetText(labelText)
		rowLabel:SetTextColor(PDCity.THEME.TextDim)

		local entry = vgui.Create("DTextEntry", leftPane)
		entry:Dock(TOP)
		entry:SetTall(26)
		entry:DockMargin(0, 2, 0, 0)
		entry:SetNumeric(true)

		return entry
	end

	local payEntry = RewardField("Officer pay per year served ($)")
	local bailEntry = RewardField("Bail cost per minute remaining ($)")
	local penaltyEntry = RewardField("Disconnect penalty per minute left ($)")

	local saveRewardsBtn = vgui.Create("DButton", leftPane)
	saveRewardsBtn:Dock(TOP)
	saveRewardsBtn:SetTall(26)
	saveRewardsBtn:DockMargin(0, 8, 0, 0)
	PDCity.StyleButton(saveRewardsBtn, "Save Rewards")
	saveRewardsBtn.DoClick = function()
		SendLawSettingsAction("set_rewards", {
			PayPerMinute = tonumber(payEntry:GetValue()),
			BailPerMinute = tonumber(bailEntry:GetValue()),
			DisconnectPenaltyPerMinute = tonumber(penaltyEntry:GetValue()),
		})
	end

	local divider = vgui.Create("DPanel", leftPane)
	divider:Dock(TOP)
	divider:SetTall(1)
	divider:DockMargin(0, 14, 0, 14)
	divider.Paint = function(self, w, h)
		surface.SetDrawColor(PDCity.THEME.Border)
		surface.DrawRect(0, 0, w, h)
	end

	--[[-------------------------------------------------------
		Add / edit a law
	---------------------------------------------------------]]
	local lawsHeading = vgui.Create("DLabel", leftPane)
	lawsHeading:Dock(TOP)
	lawsHeading:SetTall(20)
	lawsHeading:SetFont("PDCity_Heading")
	lawsHeading:SetText("Add / Edit a Law")
	lawsHeading:SetTextColor(PDCity.THEME.Text)

	local nameEntry = vgui.Create("DTextEntry", leftPane)
	nameEntry:Dock(TOP)
	nameEntry:SetTall(26)
	nameEntry:DockMargin(0, 8, 0, 0)
	nameEntry:SetPlaceholderText("Law name (e.g. Grand Theft Auto)")

	local durationRow = vgui.Create("DPanel", leftPane)
	durationRow:Dock(TOP)
	durationRow:SetTall(26)
	durationRow:DockMargin(0, 6, 0, 0)
	durationRow.Paint = function() end

	local minEntry = vgui.Create("DTextEntry", durationRow)
	minEntry:Dock(LEFT)
	minEntry:SetWide(135)
	minEntry:SetNumeric(true)
	minEntry:SetPlaceholderText("Min. years")

	local maxEntry = vgui.Create("DTextEntry", durationRow)
	maxEntry:Dock(RIGHT)
	maxEntry:SetWide(135)
	maxEntry:SetNumeric(true)
	maxEntry:SetPlaceholderText("Max. years")

	local editingIndex = nil

	local addBtn = vgui.Create("DButton", leftPane)
	addBtn:Dock(TOP)
	addBtn:SetTall(28)
	addBtn:DockMargin(0, 10, 0, 0)
	PDCity.StyleButton(addBtn, "Add Law")

	local cancelEditBtn = vgui.Create("DButton", leftPane)
	cancelEditBtn:Dock(TOP)
	cancelEditBtn:SetTall(22)
	cancelEditBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(cancelEditBtn, "Cancel Edit", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelEditBtn:SetVisible(false)

	local function ResetForm()
		editingIndex = nil
		nameEntry:SetValue("")
		minEntry:SetValue("")
		maxEntry:SetValue("")
		PDCity.StyleButton(addBtn, "Add Law")
		cancelEditBtn:SetVisible(false)
	end
	ResetForm()
	cancelEditBtn.DoClick = ResetForm

	addBtn.DoClick = function()
		SendLawSettingsAction(editingIndex and "edit_law" or "add_law", {
			Index = editingIndex,
			Name = nameEntry:GetValue(),
			MinMinutes = tonumber(minEntry:GetValue()),
			MaxMinutes = tonumber(maxEntry:GetValue()),
		})
		ResetForm()
	end

	--[[-------------------------------------------------------
		The law list itself
	---------------------------------------------------------]]
	local listView = BuildManagedList(rightPane, { "Law", "Min. Years", "Max. Years" },
		function(index, dir) SendLawSettingsAction("move_law", { Index = index, Direction = dir }) end,
		function(index)
			if editingIndex == index then ResetForm() end
			SendLawSettingsAction("remove_law", { Index = index })
		end,
		function(index)
			local law = PDCity.LAWS[index]
			if not law then return end

			editingIndex = index
			nameEntry:SetValue(law.Name or "")
			minEntry:SetValue(tostring(law.MinMinutes or ""))
			maxEntry:SetValue(tostring(law.MaxMinutes or ""))
			PDCity.StyleButton(addBtn, "Save Changes")
			cancelEditBtn:SetVisible(true)
		end
	)

	local function RefreshLawsList()
		listView:Clear()
		for index, law in ipairs(PDCity.LAWS) do
			local line = listView:AddLine(law.Name, law.MinMinutes, law.MaxMinutes)
			line.pdcityID = index
		end
	end
	RefreshLawsList()

	local function RefreshRewardFields()
		payEntry:SetValue(tostring(PDCity.LAW_REWARDS.PayPerMinute or 0))
		bailEntry:SetValue(tostring(PDCity.LAW_REWARDS.BailPerMinute or 0))
		penaltyEntry:SetValue(tostring(PDCity.LAW_REWARDS.DisconnectPenaltyPerMinute or 0))
	end
	RefreshRewardFields()

	root.PDCityRefresh = function()
		RefreshLawsList()
		RefreshRewardFields()
	end

	return root

end

--[[---------------------------------------------------------
	Tab - Rules (the F1 "Rules" tab's rulebook, core/sh_rules.lua)

	Two levels of list, so it's edited the way it's read: sections on top,
	the selected section's rules underneath, with one form column on the
	left driving both. Selecting a row loads it into the matching form and
	flips that form's button from "Add" to "Save Changes" - the same
	select-to-edit pattern the Laws & Rewards and News Posts tabs use.

	The two lists are split by a drag handle (PDCity.MakeSplitter) rather
	than a fixed 50/50, since a section with thirty rules and a server with
	three sections want very different amounts of each.
-----------------------------------------------------------]]
local function BuildRulesEditorTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local selectedSection = 1
	local editingSection = nil
	local editingRule = nil

	-- Forward declarations: the form callbacks below and the list refresh
	-- functions further down each need to call into the other.
	local RefreshSections, RefreshRules, ResetSectionForm, ResetRuleForm

	local formPane = vgui.Create("DScrollPanel", root)
	formPane:Dock(LEFT)
	formPane:SetWide(290)
	formPane:DockMargin(0, 0, 12, 0)
	PDCity.ApplyFastScroll(formPane)

	local listPane = vgui.Create("DPanel", root)
	listPane:Dock(FILL)
	listPane.Paint = function() end

	--[[-------------------------------------------------------
		Small form-building helpers, local to this tab
	---------------------------------------------------------]]
	local function Heading(text)
		local label = vgui.Create("DLabel", formPane)
		label:Dock(TOP)
		label:SetTall(20)
		label:SetFont("PDCity_Heading")
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.Text)
		return label
	end

	local function Hint(text, tall)
		local label = vgui.Create("DLabel", formPane)
		label:Dock(TOP)
		label:SetTall(tall or 16)
		label:DockMargin(0, 4, 6, 0)
		label:SetFont("PDCity_Small")
		label:SetWrap(true)
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.TextDim)
		return label
	end

	local function Entry(placeholder, tall)
		local entry = vgui.Create("DTextEntry", formPane)
		entry:Dock(TOP)
		entry:SetTall(tall or 26)
		entry:DockMargin(0, 6, 6, 0)
		entry:SetPlaceholderText(placeholder)
		if tall and tall > 40 then entry:SetMultiline(true) end
		return entry
	end

	local function Divider()
		local line = vgui.Create("DPanel", formPane)
		line:Dock(TOP)
		line:SetTall(1)
		line:DockMargin(0, 16, 6, 14)
		line.Paint = function(self, w, h)
			surface.SetDrawColor(PDCity.THEME.Border)
			surface.DrawRect(0, 0, w, h)
		end
	end

	--[[-------------------------------------------------------
		Header (intro paragraph + "last updated")
	---------------------------------------------------------]]
	Heading("Page Header")
	Hint("The paragraph above the rules, and an optional revision line shown next to the rule count.", 30)

	local introEntry = Entry("Intro paragraph (leave blank to hide it)", 90)
	local updatedEntry = Entry("Last updated (e.g. March 2025, or v3.1)")

	local saveHeaderBtn = vgui.Create("DButton", formPane)
	saveHeaderBtn:Dock(TOP)
	saveHeaderBtn:SetTall(26)
	saveHeaderBtn:DockMargin(0, 8, 6, 0)
	PDCity.StyleButton(saveHeaderBtn, "Save Header")
	saveHeaderBtn.DoClick = function()
		SendRulesAction("set_header", {
			Intro = introEntry:GetValue(),
			Updated = updatedEntry:GetValue(),
		})
	end

	Divider()

	--[[-------------------------------------------------------
		Section form
	---------------------------------------------------------]]
	Heading("Section")

	local sectionTitleEntry = Entry("Section title (e.g. Roleplay Standards)")

	local iconRow = vgui.Create("DPanel", formPane)
	iconRow:Dock(TOP)
	iconRow:SetTall(26)
	iconRow:DockMargin(0, 6, 6, 0)
	iconRow.Paint = function() end

	local iconPickBtn = vgui.Create("DButton", iconRow)
	iconPickBtn:Dock(RIGHT)
	iconPickBtn:SetWide(64)
	iconPickBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(iconPickBtn, "Pick", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })

	local sectionIconEntry = vgui.Create("DTextEntry", iconRow)
	sectionIconEntry:Dock(FILL)
	sectionIconEntry:SetPlaceholderText("Icon (optional)")

	iconPickBtn.DoClick = function()
		PDCity.OpenIconPicker(function(path) sectionIconEntry:SetValue(path) end)
	end

	local sectionSaveBtn = vgui.Create("DButton", formPane)
	sectionSaveBtn:Dock(TOP)
	sectionSaveBtn:SetTall(28)
	sectionSaveBtn:DockMargin(0, 8, 6, 0)

	local sectionCancelBtn = vgui.Create("DButton", formPane)
	sectionCancelBtn:Dock(TOP)
	sectionCancelBtn:SetTall(22)
	sectionCancelBtn:DockMargin(0, 4, 6, 0)
	PDCity.StyleButton(sectionCancelBtn, "Cancel Edit", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })

	ResetSectionForm = function()
		editingSection = nil
		sectionTitleEntry:SetValue("")
		sectionIconEntry:SetValue("")
		PDCity.StyleButton(sectionSaveBtn, "Add Section")
		sectionCancelBtn:SetVisible(false)
	end
	ResetSectionForm()
	sectionCancelBtn.DoClick = ResetSectionForm

	sectionSaveBtn.DoClick = function()
		SendRulesAction(editingSection and "edit_section" or "add_section", {
			Index = editingSection,
			Title = sectionTitleEntry:GetValue(),
			Icon = sectionIconEntry:GetValue(),
		})
		ResetSectionForm()
	end

	Divider()

	--[[-------------------------------------------------------
		Rule form
	---------------------------------------------------------]]
	Heading("Rule")
	local ruleTargetHint = Hint("Pick a section above to add rules to it.", 40)

	local ruleTitleEntry = Entry("Rule title (e.g. No random deathmatch)")
	local ruleDetailEntry = Entry("What it means in practice (optional)", 80)

	local severityCombo = vgui.Create("DComboBox", formPane)
	severityCombo:Dock(TOP)
	severityCombo:SetTall(26)
	severityCombo:DockMargin(0, 6, 6, 0)
	for _, sev in ipairs(PDCity.RULE_SEVERITIES) do
		severityCombo:AddChoice(sev.Label, sev.ID)
	end

	-- ChooseOptionID, not SetValue: SetValue only changes the text shown
	-- on the box, it doesn't actually select the option behind it, so a
	-- later :GetSelected() hands back nothing and the severity silently
	-- falls back to the default instead of what's on screen.
	local DEFAULT_SEVERITY = 2 -- "WARNING" - a saner default for a new rule than "GUIDANCE"
	local function SeverityOptionID(id)
		for index, sev in ipairs(PDCity.RULE_SEVERITIES) do
			if sev.ID == id then return index end
		end
		return DEFAULT_SEVERITY
	end

	local ruleSaveBtn = vgui.Create("DButton", formPane)
	ruleSaveBtn:Dock(TOP)
	ruleSaveBtn:SetTall(28)
	ruleSaveBtn:DockMargin(0, 8, 6, 0)

	local ruleCancelBtn = vgui.Create("DButton", formPane)
	ruleCancelBtn:Dock(TOP)
	ruleCancelBtn:SetTall(22)
	ruleCancelBtn:DockMargin(0, 4, 6, 0)
	PDCity.StyleButton(ruleCancelBtn, "Cancel Edit", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })

	ResetRuleForm = function()
		editingRule = nil
		ruleTitleEntry:SetValue("")
		ruleDetailEntry:SetValue("")
		severityCombo:ChooseOptionID(DEFAULT_SEVERITY)
		PDCity.StyleButton(ruleSaveBtn, "Add Rule")
		ruleCancelBtn:SetVisible(false)
	end
	ResetRuleForm()
	ruleCancelBtn.DoClick = ResetRuleForm

	ruleSaveBtn.DoClick = function()
		local section = PDCity.RULES.Sections[selectedSection]
		if not section then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Select a section first.")
			return
		end

		local _, severityID = severityCombo:GetSelected()

		SendRulesAction(editingRule and "edit_rule" or "add_rule", {
			Section = selectedSection,
			Index = editingRule,
			Title = ruleTitleEntry:GetValue(),
			Detail = ruleDetailEntry:GetValue(),
			Severity = severityID or PDCity.RULE_SEVERITIES[DEFAULT_SEVERITY].ID,
		})
		ResetRuleForm()
	end

	Divider()

	--[[-------------------------------------------------------
		Reset. Two clicks rather than a Derma_Query popup - this throws
		away the whole rulebook, so it shouldn't be one stray click, but a
		stock query window is the one unthemed white box left in this menu.
		Reverts on its own after a few seconds if the second click never
		comes.
	---------------------------------------------------------]]
	local resetBtn = vgui.Create("DButton", formPane)
	resetBtn:Dock(TOP)
	resetBtn:SetTall(26)
	resetBtn:DockMargin(0, 0, 6, 0)
	PDCity.StyleButton(resetBtn, "Reset to Example Rules", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })

	local resetArmed = false
	resetBtn.DoClick = function(self)
		if resetArmed then
			SendRulesAction("reset_defaults")
			resetArmed = false
			PDCity.StyleButton(self, "Reset to Example Rules", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
			return
		end

		resetArmed = true
		PDCity.StyleButton(self, "Click again to wipe every rule", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })

		timer.Simple(4, function()
			if not IsValid(self) or not resetArmed then return end
			resetArmed = false
			PDCity.StyleButton(self, "Reset to Example Rules", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
		end)
	end

	--[[-------------------------------------------------------
		The two lists
	---------------------------------------------------------]]
	local sectionsBox = vgui.Create("DPanel", listPane)
	sectionsBox.Paint = function() end

	local rulesBox = vgui.Create("DPanel", listPane)
	rulesBox.Paint = function() end

	local splitState = { Top = 220 }
	local Reflow = PDCity.MakeSplitter(listPane, sectionsBox, rulesBox, splitState)
	listPane.PerformLayout = function(self, w, h) Reflow(w, h) end

	local sectionsHeading = vgui.Create("DLabel", sectionsBox)
	sectionsHeading:Dock(TOP)
	sectionsHeading:SetTall(22)
	sectionsHeading:SetFont("PDCity_Heading")
	sectionsHeading:SetText("Sections")
	sectionsHeading:SetTextColor(PDCity.THEME.Text)

	local sectionsList = BuildManagedList(sectionsBox, { "#", "Section", "Rules" },
		function(index, dir) SendRulesAction("move_section", { Index = index, Direction = dir }) end,
		function(index)
			if editingSection == index then ResetSectionForm() end
			SendRulesAction("remove_section", { Index = index })
		end,
		function(index)
			local section = PDCity.RULES.Sections[index]
			if not section then return end

			selectedSection = index
			editingSection = index
			sectionTitleEntry:SetValue(section.Title or "")
			sectionIconEntry:SetValue(section.Icon or "")
			PDCity.StyleButton(sectionSaveBtn, "Save Section")
			sectionCancelBtn:SetVisible(true)

			ResetRuleForm()
			RefreshRules()
		end
	)

	local rulesHeading = vgui.Create("DLabel", rulesBox)
	rulesHeading:Dock(TOP)
	rulesHeading:SetTall(22)
	rulesHeading:SetFont("PDCity_Heading")
	rulesHeading:SetTextColor(PDCity.THEME.Text)

	local rulesList = BuildManagedList(rulesBox, { "#", "Rule", "Penalty" },
		function(index, dir) SendRulesAction("move_rule", { Section = selectedSection, Index = index, Direction = dir }) end,
		function(index)
			if editingRule == index then ResetRuleForm() end
			SendRulesAction("remove_rule", { Section = selectedSection, Index = index })
		end,
		function(index)
			local section = PDCity.RULES.Sections[selectedSection]
			local rule = section and section.Rules and section.Rules[index]
			if not rule then return end

			editingRule = index
			ruleTitleEntry:SetValue(rule.Title or "")
			ruleDetailEntry:SetValue(rule.Detail or "")
			severityCombo:ChooseOptionID(SeverityOptionID(rule.Severity))
			PDCity.StyleButton(ruleSaveBtn, "Save Rule")
			ruleCancelBtn:SetVisible(true)
		end
	)

	RefreshRules = function()
		local sections = PDCity.RULES.Sections or {}

		-- A removed section leaves the stored index pointing past the end
		-- of the list, so it's clamped on every refresh rather than trusted.
		selectedSection = math.Clamp(selectedSection, 1, math.max(1, #sections))

		local section = sections[selectedSection]
		rulesHeading:SetText(section and ("Rules in \"" .. (section.Title or "") .. "\"") or "Rules")
		ruleTargetHint:SetText(section
			and "New rules are added to \"" .. (section.Title or "") .. "\". Pick a different section above to switch."
			or "Add a section first - rules live inside one.")

		rulesList:Clear()
		if not section then return end

		for index, rule in ipairs(section.Rules or {}) do
			local line = rulesList:AddLine(index, rule.Title, PDCity.GetRuleSeverity(rule.Severity).Label)
			line.pdcityID = index
		end
	end

	RefreshSections = function()
		sectionsList:Clear()
		for index, section in ipairs(PDCity.RULES.Sections or {}) do
			local line = sectionsList:AddLine(index, section.Title, #(section.Rules or {}))
			line.pdcityID = index
		end
	end

	local function RefreshHeaderFields()
		if not introEntry:HasFocus() then introEntry:SetValue(PDCity.RULES.Intro or "") end
		if not updatedEntry:HasFocus() then updatedEntry:SetValue(PDCity.RULES.Updated or "") end
	end

	RefreshHeaderFields()
	RefreshSections()
	RefreshRules()

	root.PDCityRefresh = function()
		RefreshHeaderFields()
		RefreshSections()
		RefreshRules()
	end

	return root

end

--[[---------------------------------------------------------
	Page - built inside the F1 menu's content area (cl_f1_menu.lua) as
	its owner-only "Site Admin" page (layout: cl_theme.lua's
	PDCity.BuildAdminPage).
-----------------------------------------------------------]]
function PDCity.BuildSiteAdminPanel(parent)

	local tabs = {
		{ Name = "Workshop Link", Build = BuildWorkshopTab },
		{ Name = "Welcome Screen", Build = BuildWelcomeStepsTab },
		{ Name = "News Posts", Build = BuildNewsPostsTab },
		{ Name = "Rules", Build = BuildRulesEditorTab },
		{ Name = "Warrant Approvers", Build = BuildWarrantApproversTab },
		{ Name = "Door Factions", Build = BuildDoorFactionsTab },
		{ Name = "Laws & Rewards", Build = BuildLawsAndRewardsTab },
		{ Name = "XP System", Build = BuildXPSystemTab },
		{ Name = "Prop Filter", Build = BuildPropFilterTab },
		{ Name = "Developers", Build = BuildDevelopersTab },
		{ Name = "Site Theme", Build = PDCity.BuildSiteThemeEditorTab },
		{ Name = "HUD Card", Build = PDCity.BuildHUDEditorTab },
		{ Name = "Character Limits", Build = PDCity.BuildCharacterLimitsTab },
		{ Name = "Character Models", Build = PDCity.BuildCharacterModelsTab },
	}

	local root = PDCity.BuildAdminPage(parent, "Site Admin", tabs)

	-- Keyed on the panel, so the hook removes itself when F1 closes.
	hook.Add("PDCity_SiteContentUpdated", root, function() root.PDCityRefreshAll() end)

	return root

end
