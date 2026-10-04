--[[---------------------------------------------------------
	Character Slot Limits editor - owner-only, Site Admin tab
	(cl_site_admin.lua). Base limit + a stacking list of bonus rules
	(core/sv_accounts.lua's PDCity.GetCharacterLimit) - every rule that
	matches a player adds its Bonus onto Base, not "best rule wins".
-----------------------------------------------------------]]

net.Receive("pdcity_character_limits_sync", function()
	PDCity.CHARACTER_LIMIT_CONFIG = util.JSONToTable(net.ReadString() or "{}") or { Base = 2, Rules = {} }
end)

local RULE_TYPE_LABELS = {
	steamid = "Specific SteamID",
	staff = "Staff (admin+)",
	job_level = "Total Job Levels \226\137\165",
	playtime = "Playtime (hours) \226\137\165",
	usergroup = "UCL Usergroup",
}
local RULE_TYPE_ORDER = { "steamid", "staff", "job_level", "playtime", "usergroup" }

local RULE_MATCH_PLACEHOLDER = {
	steamid = "STEAM_0:X:XXXXXXXX",
	staff = "(no match value needed)",
	job_level = "e.g. 20",
	playtime = "e.g. 10",
	usergroup = "e.g. vip",
}

function PDCity.BuildCharacterLimitsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local formHolder = vgui.Create("DPanel", root)
	formHolder:Dock(FILL)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(14, 14, 14, 14)
	PDCity.ApplyFastScroll(form)

	local intro = vgui.Create("DLabel", form)
	intro:Dock(TOP)
	intro:SetTall(50)
	intro:SetFont("PDCity_Small")
	intro:SetWrap(true)
	intro:SetText("How many characters a player may have. Every rule below that matches them ADDS its bonus onto the base - they stack, they don't override each other. \"Staff\" is seeded by default (their extra slot for an on-duty character), but is a normal rule - edit or remove it like any other.")
	intro:SetTextColor(PDCity.THEME.TextDim)

	local baseLabel = vgui.Create("DLabel", form)
	baseLabel:Dock(TOP)
	baseLabel:SetTall(18)
	baseLabel:DockMargin(0, 10, 0, 0)
	baseLabel:SetText("Base Limit (everyone starts with this many)")
	baseLabel:SetTextColor(PDCity.THEME.TextDim)

	local baseEntry = vgui.Create("DTextEntry", form)
	baseEntry:Dock(TOP)
	baseEntry:SetTall(26)
	baseEntry:DockMargin(0, 4, 0, 0)
	baseEntry:SetNumeric(true)

	local rulesLabel = vgui.Create("DLabel", form)
	rulesLabel:Dock(TOP)
	rulesLabel:SetTall(18)
	rulesLabel:DockMargin(0, 14, 0, 0)
	rulesLabel:SetText("Bonus Rules")
	rulesLabel:SetTextColor(PDCity.THEME.TextDim)

	-- Rows are docked and laid out in PerformLayout, not sized from the
	-- list's width at creation - that's 0 when this tab is built before
	-- it's first shown, which crushed every row to a sliver.
	local rulesList = vgui.Create("DPanel", form)
	rulesList:Dock(TOP)
	rulesList:DockMargin(0, 4, 0, 0)
	rulesList.Paint = function() end
	rulesList.PerformLayout = function(self) self:SizeToChildren(false, true) end

	-- Working copy - only sent to the server when "Save Changes" is
	-- pressed, same "edit in the form, commit on submit" pattern as
	-- every other admin form in this gamemode.
	local rules = {}
	local RefreshRules

	local function BuildRuleRow(rule, index)
		local row = vgui.Create("DPanel", rulesList)
		row:Dock(TOP)
		row:SetTall(68)
		row:DockMargin(0, 0, 0, 6)
		row.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Background) end

		local typeBox = vgui.Create("DComboBox", row)
		typeBox:SetPos(10, 8)
		typeBox:SetSize(180, 24)
		typeBox:SetSortItems(false)
		for _, t in ipairs(RULE_TYPE_ORDER) do
			typeBox:AddChoice(RULE_TYPE_LABELS[t], t, t == rule.Type)
		end

		local matchEntry = vgui.Create("DTextEntry", row)
		matchEntry:SetPlaceholderText(RULE_MATCH_PLACEHOLDER[rule.Type] or "")
		matchEntry:SetValue(rule.Match or "")
		matchEntry.OnValueChange = function(self, val) rule.Match = val end

		typeBox.OnSelect = function(self, index2, text, data)
			rule.Type = data
			matchEntry:SetPlaceholderText(RULE_MATCH_PLACEHOLDER[data] or "")
		end

		local bonusEntry = vgui.Create("DTextEntry", row)
		bonusEntry:SetPos(10, 38)
		bonusEntry:SetSize(60, 22)
		bonusEntry:SetNumeric(true)
		bonusEntry:SetPlaceholderText("Bonus")
		bonusEntry:SetValue(tostring(rule.Bonus or 0))
		bonusEntry.OnValueChange = function(self, val) rule.Bonus = tonumber(val) or 0 end

		local bonusLabel = vgui.Create("DLabel", row)
		bonusLabel:SetPos(78, 38)
		bonusLabel:SetSize(220, 22)
		bonusLabel:SetFont("PDCity_Small")
		bonusLabel:SetText("extra character slot(s)")
		bonusLabel:SetTextColor(PDCity.THEME.TextDim)

		local removeBtn = vgui.Create("DButton", row)
		removeBtn:SetSize(80, 24)
		PDCity.StyleButton(removeBtn, "Remove", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })
		removeBtn.DoClick = function()
			table.remove(rules, index)
			RefreshRules()
		end

		row.PerformLayout = function(self, w, h)
			matchEntry:SetPos(198, 8)
			matchEntry:SetSize(math.max(60, w - 198 - 90 - 18), 24)
			removeBtn:SetPos(w - 90, 8)
		end

		return row
	end

	RefreshRules = function()
		rulesList:Clear()
		for i, rule in ipairs(rules) do
			BuildRuleRow(rule, i)
		end
		if #rules == 0 then
			local empty = vgui.Create("DLabel", rulesList)
			empty:Dock(TOP)
			empty:SetTall(24)
			empty:SetFont("PDCity_Small")
			empty:SetText("No rules - every player just gets the base limit.")
			empty:SetTextColor(PDCity.THEME.TextDim)
		end
		rulesList:InvalidateLayout()
	end

	local addRuleBtn = vgui.Create("DButton", form)
	addRuleBtn:Dock(TOP)
	addRuleBtn:SetTall(26)
	addRuleBtn:DockMargin(0, 8, 0, 0)
	PDCity.StyleButton(addRuleBtn, "+ Add Rule", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	addRuleBtn.DoClick = function()
		table.insert(rules, { Type = "steamid", Match = "", Bonus = 1 })
		RefreshRules()
	end

	local function LoadIntoForm()
		local cfg = PDCity.CHARACTER_LIMIT_CONFIG or { Base = 2, Rules = {} }
		baseEntry:SetValue(tostring(cfg.Base or 2))
		rules = {}
		for _, rule in ipairs(cfg.Rules or {}) do
			table.insert(rules, { Type = rule.Type, Match = rule.Match, Bonus = rule.Bonus })
		end
		RefreshRules()
	end
	LoadIntoForm()

	local saveBtn = vgui.Create("DButton", form)
	saveBtn:Dock(TOP)
	saveBtn:SetTall(28)
	saveBtn:DockMargin(0, 16, 0, 0)
	PDCity.StyleButton(saveBtn, "Save Changes")
	saveBtn.DoClick = function()
		net.Start("pdcity_character_limits_admin")
			net.WriteString(util.TableToJSON({ Base = tonumber(baseEntry:GetValue()) or 2, Rules = rules }))
		net.SendToServer()
	end

	root.PDCityRefresh = LoadIntoForm

	return root

end
