--[[---------------------------------------------------------
	F1 information menu - now the SAME full-screen dashboard the
	mandatory join/character-select screen uses (cl_character_select.lua),
	not a separate smaller windowed frame. Pressing F1 runs the native
	"gm_showhelp" concommand, which the server picks up as GM:ShowHelp(ply)
	and forwards to us via Player:ConCommand (see init.lua) - the same
	mechanism TerrorTown uses for its own F1 help screen, and more
	reliable than Player:SendLua, which most clients silently ignore.

	PDCity.OpenF1Menu(startTabName, mandatory, characterData) is the one
	entry point both paths use:
	  - Normal F1 press: mandatory=false, characterData=nil - the
	    Character Selection tab (built by cl_character_select.lua's
	    PDCity.BuildCharacterSelectTab) starts empty with a "Switch
	    Character" button, since nothing pushed it fresh data.
	  - The mandatory join screen (net.Receive("pdcity_character_screen")
	    in cl_character_select.lua): mandatory=true, characterData
	    supplied - opens with no close button, landed directly on
	    Character Selection, already populated.
-----------------------------------------------------------]]

local TABS = {
	{
		Name = "Welcome",
		Icon = "icon16/information.png",
		IsWelcomeTab = true, -- intro blurb + the news/update cards (core/sh_site_content.lua), not plain RichText
	},
	{
		Name = "Character Selection",
		Short = "Characters", -- the tile buttons are narrow - the full name (used for lookups, e.g. PDCitySelectTabByName) is too long to fit
		Icon = "icon16/user.png",
		IsCharacterTab = true,
	},
	{
		Name = "Jobs",
		Icon = "icon16/group_gear.png",
		Text = nil, -- built dynamically below, once PDCity.JOBS exists
	},
	{
		Name = "Rules",
		Icon = "icon16/book.png",
		IsRulesTab = true, -- the owner-editable rulebook (cl_rules.lua), not RichText
	},
	{
		Name = "Job Levels",
		Icon = "icon16/chart_bar.png",
		IsJobLevelsTab = true, -- shows per-class progress bars instead of RichText
	},
	{
		Name = "Keybinds",
		Icon = "icon16/keyboard.png",
		IsKeybindTab = true,
	},
	{
		Name = "Commands",
		Icon = "icon16/page_white_text.png",
		IsCommandsTab = true,
	},
	{
		Name = "Accessibility",
		Icon = "icon16/eye.png",
		IsAccessibilityTab = true, -- per-player readable mode (cl_accessibility.lua)
	},
	{
		Name = "Content",
		Icon = "icon16/world.png",
		IsContentTab = true,
	},
}

--[[---------------------------------------------------------
	Keybinds (core/sh_keybinds.lua). The server owns these - it stores
	them per player and watches for the keypress itself - so this is
	just the last copy it sent us, used to draw the right key in each
	box.
-----------------------------------------------------------]]

PDCity.MY_KEYBINDS = PDCity.MY_KEYBINDS or {}

net.Receive("pdcity_keybinds_sync", function()
	local binds = util.JSONToTable(net.ReadString() or "")
	if istable(binds) then PDCity.MY_KEYBINDS = binds end
end)

local function SendKeybinds()
	net.Start("pdcity_keybinds_set")
		net.WriteString(util.TableToJSON(PDCity.MY_KEYBINDS))
	net.SendToServer()
end

-- Tells the server to ignore hotkeys while this menu is open, so
-- pressing "M" to bind it doesn't also fire the action behind the menu.
local function SetKeybindMenuOpen(open)
	net.Start("pdcity_keybinds_menu")
		net.WriteBool(open)
	net.SendToServer()
end

--[[---------------------------------------------------------
	Accessibility - the readable-mode toggle (cl_accessibility.lua). Only
	ever changes this player's own screen.
-----------------------------------------------------------]]
local function CreateAccessibilityPanel(parent)

	local panel = vgui.Create("DScrollPanel", parent)
	panel:Dock(FILL)
	panel:DockMargin(24, 18, 24, 18)

	local heading = vgui.Create("DLabel", panel)
	heading:Dock(TOP)
	heading:SetTall(30)
	heading:SetFont("PDCity_Title")
	heading:SetText("Accessibility")
	heading:SetTextColor(PDCity.THEME.Text)

	local intro = vgui.Create("DLabel", panel)
	intro:Dock(TOP)
	intro:SetTall(40)
	intro:DockMargin(0, 4, 0, 12)
	intro:SetFont("PDCity_Body")
	intro:SetWrap(true)
	intro:SetText("These settings only change how the game looks on your screen. Nobody else is affected, and they're remembered next time you play.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local card = vgui.Create("DPanel", panel)
	card:Dock(TOP)
	card:SetTall(190)
	card:DockPadding(16, 14, 16, 14)
	card.Paint = function(self, w, h) draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel) end

	-- A plain checkbox + full-width label rather than DCheckBoxLabel, whose
	-- label keeps the width it measured at creation and truncates once
	-- readable mode makes the font bigger.
	local toggleRow = vgui.Create("DPanel", card)
	toggleRow:Dock(TOP)
	toggleRow:SetTall(28)
	toggleRow.Paint = function() end

	local checkbox = vgui.Create("DCheckBox", toggleRow)
	checkbox:Dock(LEFT)
	checkbox:SetWide(15)
	checkbox:DockMargin(0, 6, 0, 7)
	checkbox:SetChecked(PDCity.IsReadableMode())
	checkbox.OnChange = function(self, checked) PDCity.SetReadableMode(checked) end

	local toggle = vgui.Create("DLabel", toggleRow)
	toggle:Dock(FILL)
	toggle:DockMargin(10, 0, 0, 0)
	toggle:SetFont("PDCity_Heading")
	toggle:SetText("Readable mode (dyslexia-friendly)")
	toggle:SetTextColor(PDCity.THEME.Text)
	toggle:SetMouseInputEnabled(true)
	toggle:SetCursor("hand")
	toggle.DoClick = function() checkbox:Toggle() end

	local details = vgui.Create("DLabel", card)
	details:Dock(FILL)
	details:DockMargin(26, 10, 0, 0)
	details:SetFont("PDCity_Body")
	details:SetWrap(true)
	details:SetContentAlignment(7)
	details:SetText(
		"- Switches all text to Verdana, a clear, evenly spaced font\n" ..
		"- Makes text about 15% larger, including your HUD card\n" ..
		"- Uses soft off-white text instead of bright white, with brighter secondary text\n" ..
		"- Makes menu backgrounds solid, so the game behind them doesn't show through the text"
	)
	details:SetTextColor(PDCity.THEME.TextDim)

	-- Colours and fonts change live; re-read them once the change lands.
	hook.Add("PDCity_ReadableModeChanged", panel, function()
		heading:SetTextColor(PDCity.THEME.Text)
		intro:SetTextColor(PDCity.THEME.TextDim)
		toggle:SetTextColor(PDCity.THEME.Text)
		details:SetTextColor(PDCity.THEME.TextDim)
	end)

	return panel

end

local function CreateKeybindPanel(parent)

	local panel = vgui.Create("DScrollPanel", parent)
	panel:Dock(FILL)
	panel:DockMargin(24, 18, 24, 18)

	local intro = vgui.Create("DLabel", panel)
	intro:Dock(TOP)
	intro:SetTall(38)
	intro:DockMargin(0, 0, 0, 10)
	intro:SetFont("PDCity_Small")
	intro:SetText("Click a key box, then press the key you want. These are saved to your profile, so they follow you between sessions.")
	intro:SetTextColor(PDCity.THEME.TextDim)
	intro:SetWrap(true)

	for _, def in ipairs(PDCity.KEYBINDS) do

		local row = vgui.Create("DPanel", panel)
		row:Dock(TOP)
		row:SetTall(34)
		row:DockMargin(0, 0, 0, 8)
		row.Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Panel)
		end

		local binder = vgui.Create("DBinder", row)
		binder:Dock(RIGHT)
		binder:SetWide(150)
		binder:DockMargin(0, 4, 6, 4)
		binder:SetValue(PDCity.MY_KEYBINDS[def.ID] or def.Default or 0)
		binder.OnChange = function(self, num)
			PDCity.MY_KEYBINDS[def.ID] = num
			SendKeybinds()
		end

		local label = vgui.Create("DLabel", row)
		label:Dock(FILL)
		label:DockMargin(12, 0, 0, 0)
		label:SetFont("PDCity_Body")
		label:SetText(def.Name .. (def.Note and ("   (" .. def.Note .. ")") or ""))
		label:SetTextColor(PDCity.THEME.Text)

	end

	return panel

end

PDCity.LOADED_COMMANDS = PDCity.LOADED_COMMANDS or false

net.Receive("pdcity_commands_sync", function()
	local cmds = util.JSONToTable(net.ReadString() or "")
	if istable(cmds) then
		PDCity.LOADED_COMMANDS = cmds
	end
end)

local function CreateCommandsPanel(parent)

	local panel = vgui.Create("DScrollPanel", parent)
	panel:Dock(FILL)
	panel:DockMargin(24, 18, 24, 18)
	PDCity.ApplyFastScroll(panel)

	if not PDCity.LOADED_COMMANDS or next(PDCity.LOADED_COMMANDS) == nil then
		net.Start("pdcity_commands_request")
		net.SendToServer()

		local loading = vgui.Create("DLabel", panel)
		loading:Dock(TOP)
		loading:SetTall(30)
		loading:SetFont("PDCity_Body")
		loading:SetText("Loading commands...")
		loading:SetTextColor(PDCity.THEME.TextDim)
		return panel
	end

	for category, commands in pairs(PDCity.LOADED_COMMANDS) do
		local categoryLabel = vgui.Create("DLabel", panel)
		categoryLabel:Dock(TOP)
		categoryLabel:SetTall(28)
		categoryLabel:DockMargin(0, 16, 0, 8)
		categoryLabel:SetFont("PDCity_Heading")
		categoryLabel:SetText(category)
		categoryLabel:SetTextColor(PDCity.THEME.Accent)

		for _, cmd in ipairs(commands) do
			local row = vgui.Create("DPanel", panel)
			row:Dock(TOP)
			row:SetTall(50)
			row:DockMargin(0, 0, 0, 6)
			row.Paint = function(self, w, h)
				draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Panel)
			end

			local cmdLabel = vgui.Create("DLabel", row)
			cmdLabel:SetPos(12, 6)
			cmdLabel:SetSize(300, 18)
			cmdLabel:SetFont("PDCity_Body")
			cmdLabel:SetText(cmd.Command)
			cmdLabel:SetTextColor(PDCity.THEME.Accent)

			local descLabel = vgui.Create("DLabel", row)
			descLabel:SetPos(12, 26)
			descLabel:SetSize(row:GetWide() - 24, 20)
			descLabel:SetFont("PDCity_Small")
			descLabel:SetText(cmd.Description)
			descLabel:SetTextColor(PDCity.THEME.TextDim)
		end
	end

	return panel

end

--[[---------------------------------------------------------
	Job Levels (core/sh_xp.lua for the level math, core/sv_job_xp.lua
	for the server-authoritative XP itself). This is a read-only view -
	the server decides XP, this only displays the last copy it sent.
-----------------------------------------------------------]]

PDCity.MY_JOB_XP = PDCity.MY_JOB_XP or {}

net.Receive("pdcity_jobxp_sync", function()
	local xpTable = util.JSONToTable(net.ReadString() or "")
	if istable(xpTable) then
		PDCity.MY_JOB_XP = xpTable
		hook.Run("PDCity_JobXPUpdated")
	end
end)

local function CreateJobLevelsPanel(parent)

	local panel = vgui.Create("DScrollPanel", parent)
	panel:Dock(FILL)
	panel:DockMargin(24, 18, 24, 18)

	local rows = {}

	local function Refresh()

		-- Clear(true) destroys every child, so the intro label is rebuilt
		-- fresh each call rather than kept as an outer-scope local re-added
		-- via AddItem - re-adding a panel Clear(true) just destroyed threw
		-- "Tried to use a NULL Panel!" the moment this ran a second time
		-- (e.g. from a PDCity_SiteContentUpdated sync while this tab was
		-- already open). Same fix CreateWelcomePanel's own Refresh already
		-- uses just below in this file.
		panel:Clear(true)
		rows = {}

		local intro = vgui.Create("DLabel", panel)
		intro:Dock(TOP)
		intro:SetTall(38)
		intro:DockMargin(0, 0, 0, 10)
		intro:SetFont("PDCity_Small")
		intro:SetText("Every rank within a job category shares one level - getting promoted never resets your progress.")
		intro:SetTextColor(PDCity.THEME.TextDim)
		intro:SetWrap(true)

		if not PDCity.XP_ENABLED then
			local off = vgui.Create("DLabel", panel)
			off:Dock(TOP)
			off:SetTall(24)
			off:SetFont("PDCity_Small")
			off:SetText("The XP/levelling system is currently turned off.")
			off:SetTextColor(PDCity.THEME.TextDim)
			return
		end

		for _, class in ipairs(PDCity.GetAllJobClasses()) do

			local xp = PDCity.MY_JOB_XP[class] or 0
			local level, into, span = PDCity.XPProgress(xp)

			local row = vgui.Create("DPanel", panel)
			row:Dock(TOP)
			row:SetTall(70)
			row:DockMargin(0, 0, 0, 10)
			row.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
			end

			local title = vgui.Create("DLabel", row)
			title:SetPos(12, 8)
			title:SetSize(300, 20)
			title:SetFont("PDCity_Body")
			title:SetText(class .. " - Level " .. level)
			title:SetTextColor(PDCity.THEME.Text)

			local barBack = vgui.Create("DPanel", row)
			barBack.Paint = function(self, w, h)
				draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Border)

				if span > 0 then
					local frac = math.Clamp(into / span, 0, 1)
					draw.RoundedBox(4, 0, 0, w * frac, h, PDCity.THEME.Accent)
				else
					draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Accent)
				end
			end

			local progressLabel = vgui.Create("DLabel", row)
			progressLabel:SetFont("PDCity_Small")
			progressLabel:SetTextColor(PDCity.THEME.TextDim)
			if span > 0 then
				progressLabel:SetText(into .. " / " .. span .. " xp to level " .. (level + 1))
			else
				progressLabel:SetText("Max level")
			end

			local nextPerk = PDCity.GetNextPerk(class, level)
			local perkLabel
			if nextPerk then
				perkLabel = vgui.Create("DLabel", row)
				perkLabel:SetFont("PDCity_Small")
				perkLabel:SetContentAlignment(6)
				perkLabel:SetTextColor(PDCity.THEME.TextDim)
				perkLabel:SetText("Lv " .. nextPerk.Level .. ": " .. nextPerk.Text)
			end

			-- row:GetWide() right after Dock(TOP) is unreliable - GMod
			-- hasn't run its layout pass yet at that point, so it can
			-- return a stale/tiny width (this was the actual cause of
			-- the bar and text being squeezed into a sliver). Sizing
			-- these here instead, since PerformLayout is only ever
			-- called with the row's real, fully-resolved width.
			row.PerformLayout = function(self, w, h)
				barBack:SetPos(12, 34)
				barBack:SetSize(w - 24, 14)

				progressLabel:SetPos(12, 50)
				progressLabel:SetSize(w - 24, 16)

				if perkLabel then
					perkLabel:SetPos(w - 220, 8)
					perkLabel:SetSize(210, 20)
				end
			end

			table.insert(rows, row)

		end

	end

	Refresh()
	hook.Add("PDCity_JobXPUpdated", panel, Refresh)
	-- Also fired when the XP system's on/off toggle changes (core/sh_xp_settings.lua) -
	-- reuses the same hook the F1 Site Admin panel's other settings use.
	hook.Add("PDCity_SiteContentUpdated", panel, Refresh)
	panel.OnRemove = function()
		hook.Remove("PDCity_JobXPUpdated", panel)
		hook.Remove("PDCity_SiteContentUpdated", panel)
	end

	return panel

end

local function BuildJobsText()
	local text = "Available jobs:\n\n"
	for _, sectionName in ipairs(PDCity.SECTIONS) do
		local ids = PDCity.GetJobIDsInSection(sectionName)
		if #ids > 0 then
			text = text .. sectionName .. "\n"
			for _, id in ipairs(ids) do
				local job = PDCity.GetJob(id)
				if job then
					-- Custom jobs (F4 admin editor) don't collect a
					-- description, unlike the hardcoded ones.
					text = text .. job.Name .. "\n" .. (job.Description or "") .. "\n\n"
				end
			end
		end
	end
	return text
end

-- The filter is fine on "all"; anything else ("mapsonly", "none",
-- "noworkshop") silently skips the cars/guns/models this server needs -
-- shown live on the "Get the content" step card below, the single most
-- common "everything is errors" cause on any server.
local function FilterStatus()
	local filter = GetConVar("cl_downloadfilter")
	local v = filter and string.lower(filter:GetString()) or "?"
	return v == "all", v
end

--[[---------------------------------------------------------
	Welcome tab - the 3 onboarding step cards (content download, pick a
	job, the guide - content editable via Site Admin's Welcome Screen tab,
	core/sh_site_content.lua's PDCity.GetWelcomeStep), formerly cl_welcome.lua's
	own standalone "!welcome"/"!motd" popup, folded in here so it's not a
	second copy of the same onboarding content living in two places - then
	the intro blurb + news/update cards (PDCity.SITE_CONTENT.BlogPosts),
	written and managed via the F1 "Site Admin" panel (cl_site_admin.lua).
	Rebuilt from scratch on "PDCity_SiteContentUpdated" (fired on every
	server sync, including the admin's own edits) rather than trying to
	diff the list in place - this tab isn't performance-sensitive enough
	to bother.
-----------------------------------------------------------]]
local function CreateWelcomePanel(parent)

	local scroll = vgui.Create("DScrollPanel", parent)
	scroll:Dock(FILL)
	scroll:DockMargin(24, 18, 24, 18)

	local function BuildStepCards(container)
		local cardRow = vgui.Create("DPanel", container)
		cardRow:Dock(TOP)
		cardRow:SetTall(230)
		cardRow:DockMargin(0, 0, 0, 20)
		cardRow.Paint = function() end

		-- The 3 cards are a fixed width - docked into THIS fixed-width
		-- inner panel (not cardRow itself, which stretches to the full
		-- content width) and centered within cardRow via PerformLayout,
		-- so they sit centered instead of hugging the left edge with a
		-- large empty gap on a wide screen.
		local CARD_W, CARD_GAP = 240, 16
		local cardsInner = vgui.Create("DPanel", cardRow)
		cardsInner:SetSize(CARD_W * 3 + CARD_GAP * 2, 230)
		cardsInner.Paint = function() end
		cardRow.PerformLayout = function(self, w, h)
			cardsInner:SetPos(math.max(0, (w - cardsInner:GetWide()) / 2), 0)
		end

		local step1, step2, step3 = PDCity.GetWelcomeStep(1), PDCity.GetWelcomeStep(2), PDCity.GetWelcomeStep(3)
		local steps = {
			{ Num = "1", Title = step1.Title, Body = step1.Body, Button = step1.Button, Image = step1.Image, Status = true,
				OnClick = function() gui.OpenURL(PDCity.SITE_CONTENT.WorkshopURL) end },
			{ Num = "2", Title = step2.Title, Body = step2.Body, Button = step2.Button, Image = step2.Image,
				OnClick = function() RunConsoleCommand("pdcity_showjobs") end },
			{ Num = "3", Title = step3.Title, Body = step3.Body, Button = step3.Button, Image = step3.Image,
				OnClick = function() if IsValid(GAMEMODE.PDCityHelpFrame) then GAMEMODE.PDCityHelpFrame.PDCitySelectTabByName("Keybinds") end end },
		}

		for i, step in ipairs(steps) do
			local hasImage = isstring(step.Image) and step.Image ~= ""
			local imageMat = hasImage and Material(step.Image) or nil
			local imageH = hasImage and 55 or 0

			local card = vgui.Create("DPanel", cardsInner)
			card:Dock(LEFT)
			card:SetWide(CARD_W)
			card:DockMargin(0, 0, CARD_GAP, 0)
			card.Paint = function(self, w, h)
				draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel)
				draw.SimpleText(step.Num, "PDCity_Title", w - 14, 6,
					Color(PDCity.THEME.Accent.r, PDCity.THEME.Accent.g, PDCity.THEME.Accent.b, 70),
					TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
				draw.SimpleText(step.Title, "PDCity_Heading", 14, 16, PDCity.THEME.Text)

				if hasImage and not imageMat:IsError() then
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(imageMat)
					surface.DrawTexturedRect(14, 42, w - 28, imageH - 6)
				end

				if step.Status then
					local ok, val = FilterStatus()
					local col = ok and Color(90, 200, 120) or Color(230, 120, 100)
					local txt = ok and "downloads: ON" or ("downloads OFF (" .. val .. ")")
					draw.RoundedBox(4, 14, h - 56, w - 28, 20, Color(0, 0, 0, 80))
					draw.SimpleText(txt, "PDCity_Small", w / 2, h - 46, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end

			local body = vgui.Create("DLabel", card)
			body:SetPos(14, 46 + imageH)
			body:SetSize(240 - 28, math.max(20, 178 - imageH))
			body:SetFont("PDCity_Small")
			body:SetWrap(true)
			body:SetContentAlignment(7)
			body:SetText(step.Body)
			body:SetTextColor(PDCity.THEME.TextDim)

			local btn = vgui.Create("DButton", card)
			btn:SetPos(14, 230 - 38)
			btn:SetSize(240 - 28, 26)
			btn:SetText("")
			btn.Paint = function(self, w, h)
				local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
				draw.RoundedBox(5, 0, 0, w, h, col)
				draw.SimpleText(step.Button, "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			btn.DoClick = step.OnClick
		end
	end

	local function Refresh()
		scroll:Clear(true)

		BuildStepCards(scroll)

		local intro = vgui.Create("DLabel", scroll)
		intro:Dock(TOP)
		intro:SetTall(60)
		intro:DockMargin(0, 0, 0, 14)
		intro:SetFont("PDCity_Small")
		intro:SetWrap(true)
		intro:SetText("Welcome to " .. PDCity.BRAND_NAME .. "! This is a police-themed roleplay city. Explore, build with the tools you're given, " ..
			"and pick a job from the F4 menu to get properly started. Press F4 at any time to change your job.")
		intro:SetTextColor(PDCity.THEME.TextDim)

		local posts = PDCity.SITE_CONTENT.BlogPosts or {}

		if #posts == 0 then
			local empty = vgui.Create("DLabel", scroll)
			empty:Dock(TOP)
			empty:SetTall(24)
			empty:SetFont("PDCity_Small")
			empty:SetText("No news posts yet.")
			empty:SetTextColor(PDCity.THEME.TextDim)
			return
		end

		local heading = vgui.Create("DLabel", scroll)
		heading:Dock(TOP)
		heading:SetTall(22)
		heading:DockMargin(0, 0, 0, 6)
		heading:SetFont("PDCity_Heading")
		heading:SetText("News & Updates")
		heading:SetTextColor(PDCity.THEME.Text)

		for _, post in ipairs(posts) do

			local hasImage = isstring(post.Image) and post.Image ~= ""
			local imageMat = hasImage and Material(post.Image) or nil
			local hasLink = isstring(post.LinkURL) and post.LinkURL ~= ""

			local card = vgui.Create("DPanel", scroll)
			card:Dock(TOP)
			card:DockMargin(0, 0, 0, 12)
			card.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
				if hasImage and not imageMat:IsError() then
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(imageMat)
					surface.DrawTexturedRect(14, 14, w - 28, 120)
				end
			end

			local imageH = hasImage and 132 or 0

			local title = vgui.Create("DLabel", card)
			title:SetPos(14, 12 + imageH)
			title:SetFont("PDCity_Heading")
			title:SetText(post.Title)
			title:SetTextColor(PDCity.THEME.Text)
			title:SizeToContents()

			local body = vgui.Create("DLabel", card)
			body:SetFont("PDCity_Small")
			body:SetWrap(true)
			-- Grows its own Tall to fit the wrapped text at whatever Wide
			-- it's given (set below in PerformLayout) - without this,
			-- GetTall() just returns whatever SetSize was last called
			-- with, not the actual wrapped content height.
			body:SetAutoStretchVertical(true)
			body:SetText(post.Body)
			body:SetTextColor(PDCity.THEME.TextDim)

			local linkBtn
			if hasLink then
				linkBtn = vgui.Create("DButton", card)
				linkBtn:SetText("")
				linkBtn.Paint = function(self, w, h)
					local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
					draw.RoundedBox(4, 0, 0, w, h, col)
					local label = (isstring(post.LinkText) and post.LinkText ~= "") and post.LinkText or "Open Link"
					draw.SimpleText(label, "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				linkBtn.DoClick = function() gui.OpenURL(post.LinkURL) end
			end

			-- Card width isn't known until layout, and body's wrapped
			-- height depends on that width - same "compute in
			-- PerformLayout, not right after creation" reasoning as the
			-- Job Levels panel above.
			card.PerformLayout = function(self, w, h)
				body:SetPos(14, 12 + imageH + title:GetTall() + 6)
				body:SetWide(w - 28)

				local linkH = 0
				if IsValid(linkBtn) then
					linkH = 32
					linkBtn:SetPos(14, h - linkH - 12)
					linkBtn:SetSize(w - 28, 24)
				end
			end

			-- DLabel's :GetTall() after SetWrap only reflects wrapped
			-- height once it's actually been laid out with a real width -
			-- read it a frame later (Think, not PerformLayout, which runs
			-- before the label's own wrap recalculates) to size the card
			-- to fit instead of guessing a fixed height that either clips
			-- long posts or wastes space on short ones.
			card.Think = function(self)
				if self.pdcitySized then return end
				if not IsValid(body) or body:GetTall() <= 0 then return end

				local linkH = IsValid(linkBtn) and 44 or 12
				self:SetTall(12 + imageH + title:GetTall() + 6 + body:GetTall() + linkH)
				self.pdcitySized = true
			end

		end

	end

	Refresh()
	hook.Add("PDCity_SiteContentUpdated", scroll, Refresh)
	scroll.OnRemove = function() hook.Remove("PDCity_SiteContentUpdated", scroll) end

	return scroll

end

local function CreateContentPanel(parent, text)

	local panel = vgui.Create("DPanel", parent)
	panel:Dock(FILL)
	panel.Paint = function() end

	local rt = vgui.Create("RichText", panel)
	rt:Dock(FILL)
	rt:DockMargin(24, 20, 24, 20)
	rt:SetFontInternal("PDCity_Body")
	rt:InsertColorChange(PDCity.THEME.Text.r, PDCity.THEME.Text.g, PDCity.THEME.Text.b, 255)
	rt:AppendText(text)

	return panel

end

-- Friendly names for cl_downloadfilter, the convar behind Options >
-- Multiplayer > "When a game server tries to download custom content to
-- your computer". Only "all" actually lets a server send everything.
local DOWNLOAD_FILTER_NAMES = {
	["all"] = "Allow all custom files from server",
	["none"] = "Do not download any custom files",
	["nosound"] = "Allow all custom files except sounds",
	["mapsonly"] = "Only allow map files",
}

-- The Workshop collection is external, so this is a plain button (opens
-- via gui.OpenURL) rather than a clickable RichText link - RichText's
-- link-click method is a native we can't verify without live-testing,
-- unlike gui.OpenURL which is a long-established, safe GMod function.
local function CreateContentLinkPanel(parent)

	local panel = vgui.Create("DScrollPanel", parent)
	panel:Dock(FILL)
	panel:DockMargin(24, 18, 24, 18)

	local function AddHeading(text)
		local l = vgui.Create("DLabel", panel)
		l:Dock(TOP)
		l:DockMargin(0, 0, 0, 4)
		l:SetTall(22)
		l:SetFont("PDCity_Heading")
		l:SetText(text)
		l:SetTextColor(PDCity.THEME.Text)
		return l
	end

	local function AddBody(text, tall)
		local l = vgui.Create("DLabel", panel)
		l:Dock(TOP)
		l:DockMargin(0, 0, 0, 10)
		l:SetTall(tall or 40)
		l:SetFont("PDCity_Small")
		l:SetText(text)
		l:SetTextColor(PDCity.THEME.TextDim)
		l:SetWrap(true)
		return l
	end

	--[[-------------------------------------------------------
		Step 1 - the Steam/GMod download setting. This is the one that
		silently breaks everything: with it on anything but "all", the
		server's custom models/sounds never reach the client and they
		see errors instead, with no obvious cause.
	---------------------------------------------------------]]
	AddHeading("1. Allow custom content from this server")
	AddBody("In the main menu go to:\n" ..
		"Options  >  Multiplayer  >  \"When a game server tries to download custom content to your computer\"\n" ..
		"Set it to \"Allow all custom files from server\".", 74)

	-- Live readout of their actual setting, so they don't have to guess
	-- whether they already did it.
	local status = vgui.Create("DPanel", panel)
	status:Dock(TOP)
	status:DockMargin(0, 0, 0, 14)
	status:SetTall(34)
	status.Paint = function(self, w, h)
		local filter = GetConVar("cl_downloadfilter")
		local value = filter and filter:GetString():lower() or "all"
		local ok = (value == "all")

		draw.RoundedBox(4, 0, 0, w, h, ok and Color(40, 80, 45) or Color(95, 45, 40))
		draw.SimpleText(
			(ok and "Currently: " or "Currently: ") .. (DOWNLOAD_FILTER_NAMES[value] or value),
			"PDCity_Small", 10, h / 2, ok and Color(150, 230, 160) or Color(240, 180, 170),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(ok and "OK" or "NEEDS CHANGING", "PDCity_Small", w - 10, h / 2,
			ok and Color(150, 230, 160) or Color(240, 180, 170), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	--[[-------------------------------------------------------
		Step 2 - the Workshop collection.
	---------------------------------------------------------]]
	AddHeading("2. Subscribe to the content pack")
	AddBody("All " .. PDCity.BRAND_NAME .. " workshop content (maps, models, weapons) is in one collection. " ..
		"Subscribing downloads it up front so you're not waiting on the server for it.", 42)

	local btn = vgui.Create("DButton", panel)
	btn:Dock(TOP)
	btn:SetTall(36)
	btn:DockMargin(0, 0, 0, 10)
	btn:SetText("")
	btn.Paint = function(self, w, h)
		local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
		draw.RoundedBox(5, 0, 0, w, h, col)
		draw.SimpleText("OPEN WORKSHOP COLLECTION", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	btn.DoClick = function()
		gui.OpenURL(PDCity.SITE_CONTENT.WorkshopURL)
	end

	AddBody("Tip: type !content in chat at any time to open this link again.", 20)

	return panel

end

net.Receive("PDCity_OpenContentLink", function()
	gui.OpenURL(PDCity.SITE_CONTENT.WorkshopURL)
end)

local function DrawGradientStrip(x, y, w, h, c1, c2)
	local steps = math.max(2, math.floor(w / 4))
	local segW = w / steps
	for i = 0, steps - 1 do
		local t = i / (steps - 1)
		surface.SetDrawColor(Lerp(t, c1.r, c2.r), Lerp(t, c1.g, c2.g), Lerp(t, c1.b, c2.b), 255)
		surface.DrawRect(x + i * segW, y, segW + 1, h)
	end
end

-- startTabName optionally selects a tab by name instead of the first one.
-- mandatory (true only for the join screen, cl_character_select.lua)
-- removes the close button and the F1-toggle-closes behaviour - there's
-- nothing to close INTO until a character's actually been picked.
-- characterData ({ Characters = ..., Limit = ... }), when supplied, seeds
-- the Character Selection tab directly instead of it starting empty with
-- a "Switch Character" button.
function PDCity.OpenF1Menu(startTabName, mandatory, characterData)

	if IsValid(GAMEMODE.PDCityHelpFrame) then
		if GAMEMODE.PDCityHelpFrame.PDCityMandatory then
			-- Never toggle-close the mandatory screen - re-selecting a tab
			-- is all a repeat call while it's up should do.
			if startTabName then GAMEMODE.PDCityHelpFrame.PDCitySelectTabByName(startTabName) end
			if characterData then GAMEMODE.PDCityHelpFrame.PDCitySetCharacterData(characterData) end
			return
		end

		GAMEMODE.PDCityHelpFrame:Remove()

		-- Pressing F1 with it open closes it (a toggle). A caller that
		-- passed a tab name (or fresh character data) wants it reopened
		-- on that tab, not just closed.
		if not startTabName and not characterData then return end
	end

	-- Before creating the frame, so the dim panel it creates (cl_menu_dim.lua)
	-- ends up behind it in the popup stack.
	PDCity.PushMenuDim()

	local frame = vgui.Create("DFrame")
	frame:SetPos(0, 0)
	frame:SetSize(ScrW(), ScrH())
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(false)
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(true)
	frame.PDCityMandatory = mandatory == true
	frame.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, PDCity.THEME.Background)
	end
	GAMEMODE.PDCityHelpFrame = frame

	-- Hotkeys stay suppressed for as long as this menu is open, so
	-- rebinding one can't fire the action behind the menu.
	--
	-- OnRemove, not OnClose: the F1 toggle closes this with a bare
	-- Remove(), which never fires OnClose - the suppression would then
	-- stay on for the rest of the session (same reasoning applies to
	-- PDCity.PopMenuDim below - it also has to run every time, however
	-- this closes).
	SetKeybindMenuOpen(true)
	frame.OnRemove = function()
		SetKeybindMenuOpen(false)
		PDCity.PopMenuDim()

		-- No-op unless a mid-session "Switch Character" was opened and
		-- then closed without picking anything (core/sv_characters.lua's
		-- "pdcity_cancel_character_switch" receiver only restores
		-- anything if ActiveCharSlot is still nil) - always sent on close
		-- regardless of which tab was up rather than only from the
		-- Character Selection tab, since that's simpler than tracking
		-- whether one was ever opened this session.
		net.Start("pdcity_cancel_character_switch")
		net.SendToServer()
	end

	-- Deliberately NOT PDCity.LockFrameOnTop here, mandatory or not -
	-- :MakePopup() above already puts this at the front the moment it's
	-- created, and nothing else should realistically try to compete for
	-- front position while it's up (a normal session can open Site Admin
	-- from its own sidebar button below, which WOULD fight a continuous
	-- MoveToFront for the front spot every frame). That constant
	-- reassertion is fine for a simple "click one thing and close" picker
	-- popup, but on a screen with actual text entry + several buttons
	-- (the Character Selection tab's name field, create button...) it can
	-- interrupt a click's press/release cycle mid-interaction and eat the
	-- click outright - which is exactly what made the mandatory join
	-- screen's character cards/Create New unresponsive.
	frame:SetDraggable(false)

	--[[-------------------------------------------------------
		Sidebar - wide enough for a 2-column grid of big square tile
		buttons rather than the thin single-column PDCitySidebarTab rows
		every OTHER menu in this gamemode uses (F4 admin, Site Admin...) -
		deliberately a local, one-off style just for this dashboard rather
		than changing that shared control, which those other menus still
		want in their original compact form.
	---------------------------------------------------------]]
	local SIDEBAR_W = 280
	local sidebar = vgui.Create("DPanel", frame)
	sidebar:SetPos(0, 0)
	sidebar:SetSize(SIDEBAR_W, ScrH())
	sidebar.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, PDCity.THEME.TitleBar)
		surface.SetDrawColor(PDCity.THEME.Accent)
		surface.DrawRect(w - 2, 0, 2, h)
	end

	local LOGO_SIZE = 40
	local logo = vgui.Create("DPanel", sidebar)
	logo:SetPos(24, 24)
	logo:SetSize(LOGO_SIZE, LOGO_SIZE)
	logo.Paint = function(self, w, h)
		if PDCity.LOGO_MAT:IsError() then return end
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(PDCity.LOGO_MAT)
		surface.DrawTexturedRect(0, 0, w, h)
	end

	local brandLabel = vgui.Create("DLabel", sidebar)
	brandLabel:SetPos(24 + LOGO_SIZE + 12, 24)
	brandLabel:SetSize(SIDEBAR_W - LOGO_SIZE - 48, LOGO_SIZE)
	brandLabel:SetFont("PDCity_Heading")
	brandLabel:SetText(PDCity.BRAND_NAME)
	brandLabel:SetTextColor(PDCity.THEME.Text)
	brandLabel:SetContentAlignment(4)
	brandLabel:SetWrap(true)

	local headerDivider = vgui.Create("DPanel", sidebar)
	headerDivider:SetPos(24, 24 + LOGO_SIZE + 20)
	headerDivider:SetSize(SIDEBAR_W - 48, 1)
	headerDivider.Paint = function(self, w, h)
		surface.SetDrawColor(PDCity.THEME.Border)
		surface.DrawRect(0, 0, w, h)
	end

	--[[-------------------------------------------------------
		Big square tile button - icon + label, 2 to a row. Returns a
		DButton with a :SetActive(bool) method so SelectTab below can
		treat it exactly like a PDCitySidebarTab.
	---------------------------------------------------------]]
	local function CreateTileButton(parent, x, y, w, h, label, icon, onClick)
		local btn = vgui.Create("DButton", parent)
		btn:SetPos(x, y)
		btn:SetSize(w, h)
		btn:SetText("")

		local active = false
		btn.SetActive = function(self, val) active = val end

		btn.Paint = function(self, bw, bh)
			local bg = active and PDCity.THEME.Accent or (self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
			draw.RoundedBox(8, 0, 0, bw, bh, bg)

			local mat = Material(icon)
			if not mat:IsError() then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(mat)
				surface.DrawTexturedRect(bw / 2 - 14, bh / 2 - 22, 28, 28)
			end

			draw.SimpleText(label, "PDCity_Small", bw / 2, bh - 14,
				active and PDCity.THEME.Text or PDCity.THEME.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		btn.DoClick = onClick

		return btn
	end

	local content = vgui.Create("DPanel", frame)
	content:SetPos(SIDEBAR_W, 0)
	content:SetSize(ScrW() - SIDEBAR_W, ScrH())
	content:DockPadding(48, 48, 48, 48)
	content.Paint = function() end

	local panels = {}
	local tabButtons = {}
	local tabIndexByName = {}
	local characterTabIndex = nil

	-- 2-column grid of tiles, starting below the header divider.
	local GRID_PAD = 24
	local GRID_GAP = 14
	local TILE_W = (SIDEBAR_W - GRID_PAD * 2 - GRID_GAP) / 2
	local TILE_H = TILE_W
	local gridX, gridY = GRID_PAD, 24 + LOGO_SIZE + 20 + 24
	local col = 0

	local function NextTilePos()
		local x, y = gridX + col * (TILE_W + GRID_GAP), gridY
		col = col + 1
		if col >= 2 then
			col = 0
			gridY = gridY + TILE_H + GRID_GAP
		end
		return x, y
	end

	-- Character Selection takes the WHOLE screen, sidebar included - not
	-- just content's own area to the right of it. Both because a
	-- brand new/mid-switch player shouldn't be able to see (mandatory
	-- already prevents clicking away to) other tabs, and because the
	-- sidebar's own background left a grey strip down the side of what's
	-- otherwise meant to be an edge-to-edge black takeover.
	local function UpdateChromeForTab(index)
		local isCharacterTab = (index == characterTabIndex)
		sidebar:SetVisible(not isCharacterTab)

		if isCharacterTab then
			content:SetPos(0, 0)
			content:SetSize(ScrW(), ScrH())
			-- Solid black across content's OWN full bounds, not the 48px-
			-- padded child inside it (cl_character_select.lua's root) -
			-- a child can't paint past its own bounds (GMod clips each
			-- panel's draw calls to its own rect), so filling the padded
			-- child left a grey DockPadding margin showing all the way
			-- round. Filling content itself, which isn't padding-inset,
			-- reaches the true screen edges.
			content.Paint = function(self, w, h)
				draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 255))
			end
		else
			content:SetPos(SIDEBAR_W, 0)
			content:SetSize(ScrW() - SIDEBAR_W, ScrH())
			content.Paint = function() end
		end
	end

	local function SelectTab(index)
		for i, btn in ipairs(tabButtons) do btn:SetActive(i == index) end
		for i, panel in ipairs(panels) do panel:SetVisible(i == index) end
		UpdateChromeForTab(index)

		local shown = panels[index]
		if IsValid(shown) and shown.PDCityOnShow then shown.PDCityOnShow() end

		-- Fetches the character list the moment this tab is actually
		-- picked, not before - cl_character_select.lua's own
		-- PDCity.BuildCharacterSelectTab exposes PDCityRequestData
		-- rather than calling it itself for exactly this reason (every
		-- tab, including this one, is built up front the instant F1
		-- opens regardless of which tab is showing, so firing the
		-- request from inside that build - as this used to - fired it on
		-- EVERY F1 open no matter which tab was wanted, and the server's
		-- reply always force-switches here and takes over the whole
		-- screen once it lands - hijacking a plain F1 press straight
		-- into Character Selection with the rest of the dashboard gone).
		-- Cleared after firing once so re-selecting this tab later
		-- doesn't keep re-requesting - PDCitySetData (below) already
		-- keeps it current for the rest of this session.
		if index == characterTabIndex then
			local panel = panels[index]
			if IsValid(panel) and panel.PDCityRequestData then
				panel.PDCityRequestData()
				panel.PDCityRequestData = nil
			end
		end
	end

	frame.PDCitySelectTabByName = function(name)
		local index = tabIndexByName[string.lower(name)]
		if index then SelectTab(index) end
	end

	frame.PDCitySetCharacterData = function(data)
		if characterTabIndex and IsValid(panels[characterTabIndex]) and panels[characterTabIndex].PDCitySetData then
			panels[characterTabIndex].PDCitySetData(data.Characters, data.Limit)
		end
	end

	-- Job Levels only makes sense while the XP system itself is turned on
	-- (core/sh_xp_settings.lua's PDCity.XP_ENABLED, owner-toggleable from
	-- Site Admin) - nothing should show progress bars for a system
	-- nobody can currently earn progress in.
	local visibleTabs = {}
	for _, tabData in ipairs(TABS) do
		if not (tabData.IsJobLevelsTab and not PDCity.XP_ENABLED) then
			table.insert(visibleTabs, tabData)
		end
	end

	for i, tabData in ipairs(visibleTabs) do

		local panel

		if tabData.IsContentTab then
			panel = CreateContentLinkPanel(content)
		elseif tabData.IsRulesTab then
			panel = PDCity.BuildRulesTab(content)
		elseif tabData.IsWelcomeTab then
			panel = CreateWelcomePanel(content)
		elseif tabData.IsKeybindTab then
			panel = CreateKeybindPanel(content)
		elseif tabData.IsCommandsTab then
			panel = CreateCommandsPanel(content)
		elseif tabData.IsAccessibilityTab then
			panel = CreateAccessibilityPanel(content)
		elseif tabData.IsJobLevelsTab then
			panel = CreateJobLevelsPanel(content)
		elseif tabData.IsCharacterTab then
			panel = PDCity.BuildCharacterSelectTab(content, characterData and characterData.Characters or nil, characterData and characterData.Limit or nil, characterData and characterData.Mandatory or false)
			characterTabIndex = i
		else
			local text = tabData.Text
			if tabData.Name == "Jobs" then
				text = BuildJobsText()
			end
			panel = CreateContentPanel(content, text)
		end

		panel:SetVisible(false)
		panels[i] = panel
		tabIndexByName[string.lower(tabData.Name)] = i

		local tx, ty = NextTilePos()
		local btn = CreateTileButton(sidebar, tx, ty, TILE_W, TILE_H, tabData.Short or tabData.Name, tabData.Icon, function() SelectTab(i) end)
		tabButtons[i] = btn

	end

	-- Admin pages, each a single wide tile below the grid: Site Admin
	-- (cl_site_admin.lua) and Catalogue (cl_f4_admin.lua) for the owner,
	-- Developer Console (cl_dev_console.lua) for the owner and developers.
	-- Built on first open rather than with the other pages, since most F1
	-- presses never need them.
	-- LocalPlayer() can still be NULL here: the mandatory character screen
	-- opens this menu the moment the server asks, which can be before the
	-- local player entity exists. No admin tiles until it does.
	local me = LocalPlayer()
	local isOwner = IsValid(me) and PDCity.IsOwner(me)
	local isDeveloper = isOwner or (IsValid(me) and me:GetNWBool("PDCity_IsDeveloper", false))

	if isDeveloper then
		if col ~= 0 then col = 0; gridY = gridY + TILE_H + GRID_GAP end
		gridY = gridY + 10

		local divider = vgui.Create("DPanel", sidebar)
		divider:SetPos(GRID_PAD, gridY)
		divider:SetSize(SIDEBAR_W - GRID_PAD * 2, 1)
		divider.Paint = function(self, w, h)
			surface.SetDrawColor(PDCity.THEME.Border)
			surface.DrawRect(0, 0, w, h)
		end
		gridY = gridY + 16

		local function AddAdminPage(label, icon, build)
			local index = #panels + 1

			local page = vgui.Create("DPanel", content)
			page:Dock(FILL)
			page.Paint = function() end
			page:SetVisible(false)
			page.PDCityOnShow = function()
				page.PDCityOnShow = nil
				build(page)
			end

			panels[index] = page
			tabIndexByName[string.lower(label)] = index
			tabButtons[index] = CreateTileButton(sidebar, GRID_PAD, gridY, SIDEBAR_W - GRID_PAD * 2, 64, label, icon, function()
				SelectTab(index)
			end)

			gridY = gridY + 64 + GRID_GAP
		end

		if isOwner then
			AddAdminPage("Site Admin", "icon16/cog.png", PDCity.BuildSiteAdminPanel)
			AddAdminPage("Catalogue", "icon16/book.png", PDCity.BuildF4AdminPanel)
		end
		AddAdminPage("Developer Console", "icon16/page_white_code.png", PDCity.BuildDevConsolePanel)
	end

	-- Close button + Escape, both only when not mandatory (there's
	-- nothing to close INTO before a character's picked). Created HERE,
	-- after `content` and everything in it, not before - `content` spans
	-- all the way to the screen edge (including this button's corner),
	-- so creating this earlier let content's own z-order sit on top of
	-- it: the X was visible but silently ate no clicks, since content
	-- (not the button) was the topmost panel actually catching them.
	if not frame.PDCityMandatory then
		local closeBtn = vgui.Create("DButton", frame)
		closeBtn:SetPos(ScrW() - 42, 7)
		closeBtn:SetSize(32, 32)
		closeBtn:SetText("")
		closeBtn.Paint = function(self, w, h)
			if self:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Panel) end
			draw.SimpleText("\226\156\149", "PDCity_Body", w / 2, h / 2, PDCity.THEME.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		closeBtn.DoClick = function() frame:Remove() end

		-- F1 (whatever "gm_showhelp" is actually bound to) closes this the
		-- same way Escape does. It has to be caught HERE rather than left
		-- to PDCity.OpenF1Menu's own "already open, so close" toggle at the
		-- top: this frame is a keyboard-input popup, so the engine hands
		-- the keypress to VGUI instead of running the gm_showhelp bind, and
		-- that toggle never gets a second call to act on.
		local closeKey = PDCity.BoundKey("gm_showhelp", KEY_F1)
		frame.OnKeyCodePressed = function(self, key)
			if key == KEY_ESCAPE or key == closeKey then self:Remove() end
		end
	end

	local startIndex = mandatory and characterTabIndex or 1
	if startTabName then
		startIndex = tabIndexByName[string.lower(startTabName)] or startIndex
	end

	SelectTab(startIndex)

end

concommand.Add("pdcity_showhelp", function(ply, cmd, args)
	PDCity.OpenF1Menu(args[1])
end)
