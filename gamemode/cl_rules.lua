--[[---------------------------------------------------------
	The F1 menu's "Rules" tab - the player-facing rulebook, built from
	core/sh_rules.lua's PDCity.RULES (owner-editable in-game from Site
	Admin's "Rules" tab, persisted/synced by core/sv_rules.lua).

	Laid out like a real rules document rather than a wall of text: a
	header band, a contents rail down the left that jumps to a section and
	tracks which one you're currently reading, and one card per rule
	carrying its own reference number and a colour-coded penalty pill.

	Rebuilt from scratch on "PDCity_RulesUpdated" (fired on every server
	sync, including the owner's own edits while this tab is open) rather
	than diffing anything in place - same approach the Welcome tab already
	takes, and this isn't performance-sensitive enough to do otherwise.
-----------------------------------------------------------]]

local RAIL_W = 230
local HEADER_H = 88

-- Card geometry, shared between Paint (which draws the badge/title/pill)
-- and PerformLayout (which positions the wrapped detail label under
-- them) so the two can't drift apart.
local CARD_PAD = 14
local CARD_TITLE_Y = 21
local CARD_DETAIL_Y = 36
local CARD_BOTTOM_PAD = 12

local BULLET = " \194\183 " -- middot separator for the header's subtitle line

--[[---------------------------------------------------------
	One rule. Height is decided a frame after creation, once the wrapped
	detail label has actually been laid out at a real width and can report
	its true height - DLabel:GetTall() before that just echoes back
	whatever SetSize was last called with. Same technique the Welcome
	tab's news cards use for exactly the same reason.
-----------------------------------------------------------]]
local function BuildRuleCard(parent, ref, rule)

	local sev = PDCity.GetRuleSeverity(rule.Severity)

	surface.SetFont("PDCity_Small")
	local pillW = surface.GetTextSize(sev.Label) + 20
	local refW = math.max(34, surface.GetTextSize(ref) + 16)
	local textX = CARD_PAD + refW + 12

	local card = vgui.Create("DPanel", parent)
	card:Dock(TOP)
	card:SetTall(44)
	card:DockMargin(0, 0, 0, 8)
	card.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)

		-- Severity colour reads down the left edge of every card, so the
		-- shape of the ruleset (which rules are serious) is visible while
		-- scrolling without reading a single pill.
		draw.RoundedBoxEx(6, 0, 0, 3, h, sev.Color, true, false, true, false)

		draw.RoundedBox(4, CARD_PAD, 12, refW, 18, ColorAlpha(sev.Color, 38))
		draw.SimpleText(ref, "PDCity_Small", CARD_PAD + refW / 2, CARD_TITLE_Y, sev.Color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		draw.SimpleText(rule.Title or "", "PDCity_Heading", textX, CARD_TITLE_Y, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		draw.RoundedBox(4, w - CARD_PAD - pillW, 12, pillW, 18, ColorAlpha(sev.Color, 38))
		draw.SimpleText(sev.Label, "PDCity_Small", w - CARD_PAD - pillW / 2, CARD_TITLE_Y, sev.Color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local detailText = rule.Detail or ""
	local detail
	if detailText ~= "" then
		detail = vgui.Create("DLabel", card)
		detail:SetFont("PDCity_Small")
		detail:SetWrap(true)
		detail:SetAutoStretchVertical(true)
		detail:SetText(detailText)
		detail:SetTextColor(PDCity.THEME.TextDim)
	end

	card.PerformLayout = function(self, w, h)
		if not IsValid(detail) then return end
		detail:SetPos(textX, CARD_DETAIL_Y)
		detail:SetWide(math.max(60, w - textX - CARD_PAD))
	end

	card.Think = function(self)
		if self.pdcitySized then return end

		if not IsValid(detail) then
			self.pdcitySized = true
			return -- no detail line: the 44px it was created at is already right
		end

		if detail:GetTall() <= 0 then return end
		self:SetTall(CARD_DETAIL_Y + detail:GetTall() + CARD_BOTTOM_PAD)
		self.pdcitySized = true
	end

	return card

end

local function BuildSectionHeader(parent, index, section)

	local ruleCount = #(section.Rules or {})
	local iconPath = section.Icon or ""

	local header = vgui.Create("DPanel", parent)
	header:Dock(TOP)
	header:SetTall(34)
	header:DockMargin(0, index == 1 and 4 or 24, 0, 10)
	header.Paint = function(self, w, h)
		draw.RoundedBox(2, 0, 6, 3, 20, PDCity.THEME.Accent)

		local textX = 16
		local icon = PDCity.GetIconMaterial(iconPath)
		if icon and not icon:IsError() then
			surface.SetDrawColor(PDCity.THEME.Text)
			surface.SetMaterial(icon)
			surface.DrawTexturedRect(16, h / 2 - 9, 18, 18)
			textX = 42
		end

		draw.SimpleText(string.upper(section.Title or ""), "PDCity_Title", textX, h / 2 - 3, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(ruleCount .. (ruleCount == 1 and " RULE" or " RULES"), "PDCity_Small", w, h / 2 - 3, PDCity.THEME.TextDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		surface.SetDrawColor(PDCity.THEME.Border)
		surface.DrawRect(0, h - 1, w, 1)
	end

	return header

end

local function BuildIntroBlock(parent, text)

	local block = vgui.Create("DPanel", parent)
	block:Dock(TOP)
	block:SetTall(40)
	block:DockMargin(0, 0, 0, 6)
	block.Paint = function(self, w, h)
		draw.RoundedBox(2, 0, 1, 2, math.max(0, h - 8), PDCity.THEME.AccentDim)
	end

	local label = vgui.Create("DLabel", block)
	label:SetFont("PDCity_Body")
	label:SetWrap(true)
	label:SetAutoStretchVertical(true)
	label:SetText(text)
	label:SetTextColor(PDCity.THEME.TextDim)

	block.PerformLayout = function(self, w, h)
		label:SetPos(18, 0)
		label:SetWide(math.max(60, w - 18))
	end

	block.Think = function(self)
		if self.pdcitySized then return end
		if label:GetTall() <= 0 then return end
		self:SetTall(label:GetTall() + 8)
		self.pdcitySized = true
	end

	return block

end

--[[---------------------------------------------------------
	The contents rail: one jump button per section, plus the penalty
	legend pinned to the bottom. The buttons highlight the section
	currently at the top of the scroll view, so it doubles as a "where am
	I" indicator rather than only being a jump list.
-----------------------------------------------------------]]
local function BuildRail(parent, sections, onJump, getActiveSection)

	local rail = vgui.Create("DPanel", parent)
	rail:Dock(LEFT)
	rail:SetWide(RAIL_W)
	rail:DockMargin(0, 0, 22, 0)
	rail.Paint = function() end

	--[[-------------------------------------------------------
		Legend (docked BOTTOM before the list takes FILL, so it keeps its
		space no matter how many sections there are)
	---------------------------------------------------------]]
	-- 32 = the title's own 24 plus its 8px top margin, so the last colour
	-- row isn't clipped off the bottom.
	local legend = vgui.Create("DPanel", rail)
	legend:Dock(BOTTOM)
	legend:SetTall(32 + #PDCity.RULE_SEVERITIES * 20)
	legend:DockMargin(0, 16, 0, 0)
	legend.Paint = function(self, w, h)
		surface.SetDrawColor(PDCity.THEME.Border)
		surface.DrawRect(0, 0, w, 1)
	end

	local legendTitle = vgui.Create("DLabel", legend)
	legendTitle:Dock(TOP)
	legendTitle:SetTall(24)
	legendTitle:DockMargin(0, 8, 0, 0)
	legendTitle:SetFont("PDCity_Small")
	legendTitle:SetText("PENALTIES")
	legendTitle:SetTextColor(PDCity.THEME.TextDim)

	for _, sev in ipairs(PDCity.RULE_SEVERITIES) do
		local row = vgui.Create("DPanel", legend)
		row:Dock(TOP)
		row:SetTall(20)
		row.Paint = function(self, w, h)
			draw.RoundedBox(2, 0, h / 2 - 4, 8, 8, sev.Color)
			draw.SimpleText(sev.Label, "PDCity_Small", 18, h / 2, PDCity.THEME.TextDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	--[[-------------------------------------------------------
		Section list
	---------------------------------------------------------]]
	local listTitle = vgui.Create("DLabel", rail)
	listTitle:Dock(TOP)
	listTitle:SetTall(24)
	listTitle:SetFont("PDCity_Small")
	listTitle:SetText("CONTENTS")
	listTitle:SetTextColor(PDCity.THEME.TextDim)

	local list = vgui.Create("DScrollPanel", rail)
	list:Dock(FILL)
	PDCity.ApplyFastScroll(list)

	for index, section in ipairs(sections) do
		local btn = vgui.Create("DButton", list)
		btn:Dock(TOP)
		btn:SetTall(32)
		btn:DockMargin(0, 0, 6, 2)
		btn:SetText("")
		btn.Paint = function(self, w, h)
			local active = (getActiveSection() == index)

			if active then
				draw.RoundedBox(5, 0, 0, w, h, PDCity.THEME.Panel)
				draw.RoundedBox(2, 0, 6, 3, h - 12, PDCity.THEME.Accent)
			elseif self:IsHovered() then
				draw.RoundedBox(5, 0, 0, w, h, ColorAlpha(PDCity.THEME.Panel, 120))
			end

			local col = active and PDCity.THEME.Text or PDCity.THEME.TextDim
			draw.SimpleText(string.format("%02d", index), "PDCity_Small", 14, h / 2, active and PDCity.THEME.Accent or PDCity.THEME.Border, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(section.Title or "", "PDCity_Body", 40, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		btn.DoClick = function() onJump(index) end
	end

	return rail

end

function PDCity.BuildRulesTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local function Refresh()

		root:Clear()

		local sections = PDCity.RULES.Sections or {}
		local sectionCount, ruleCount = PDCity.CountRules()

		--[[-------------------------------------------------------
			Header band
		---------------------------------------------------------]]
		local subtitle = PDCity.BRAND_NAME .. BULLET ..
			ruleCount .. (ruleCount == 1 and " rule" or " rules") .. " across " ..
			sectionCount .. (sectionCount == 1 and " section" or " sections")

		local updated = PDCity.RULES.Updated or ""
		if updated ~= "" then subtitle = subtitle .. BULLET .. "Updated " .. updated end

		local header = vgui.Create("DPanel", root)
		header:Dock(TOP)
		header:SetTall(HEADER_H)
		header:DockMargin(0, 0, 0, 18)
		header.Paint = function(self, w, h)
			draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel)
			draw.RoundedBoxEx(8, 0, 0, 4, h, PDCity.THEME.Accent, true, false, true, false)

			local textX = 26
			if not PDCity.LOGO_MAT:IsError() then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(PDCity.LOGO_MAT)
				surface.DrawTexturedRect(26, h / 2 - 22, 44, 44)
				textX = 88
			end

			draw.SimpleText("SERVER RULES", "PDCity_Brand", textX, 30, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(subtitle, "PDCity_Small", textX, 58, PDCity.THEME.TextDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end

		--[[-------------------------------------------------------
			Empty state - a fresh install always ships a full example set
			(core/sh_rules.lua), so this only shows once someone has
			deliberately deleted every section.
		---------------------------------------------------------]]
		if sectionCount == 0 then
			local empty = vgui.Create("DLabel", root)
			empty:Dock(TOP)
			empty:SetTall(30)
			empty:SetFont("PDCity_Body")
			empty:SetText("No rules have been published yet.")
			empty:SetTextColor(PDCity.THEME.TextDim)
			return
		end

		local body = vgui.Create("DPanel", root)
		body:Dock(FILL)
		body.Paint = function() end

		--[[-------------------------------------------------------
			Rail first, THEN the rules column. Docking is resolved in the
			order children were parented, not the order Dock() was called,
			so a FILL panel created before a LEFT one claims the whole area
			and leaves the rail nothing to sit in. `scroll` is forward-
			declared for the rail's jump callback, which only ever runs
			long after it exists.
		---------------------------------------------------------]]
		local scroll
		local sectionHeaders = {}
		local activeSection = 1

		local rail = BuildRail(body, sections,
			function(index)
				local target = sectionHeaders[index]
				if not IsValid(scroll) or not IsValid(target) then return end
				-- Puts the section heading at the top of the view rather
				-- than centring it (DScrollPanel:ScrollToChild's
				-- behaviour) - a contents jump should land on the heading,
				-- not halfway past it.
				scroll:GetVBar():SetScroll(target:GetY() - 6)
			end,
			function() return activeSection end)

		scroll = vgui.Create("DScrollPanel", body)
		scroll:Dock(FILL)
		PDCity.ApplyFastScroll(scroll)

		-- Whichever section heading is the last one at or above the top of
		-- the view is the one being read - recomputed on the rail (a plain
		-- DPanel) rather than on the DScrollPanel, so nothing of that
		-- control's own behaviour is overridden.
		--
		-- A short trailing section (little or no rule text) never gets far
		-- enough for its own heading to actually reach the top of the view -
		-- the scrollbar runs out of content to scroll before it does, so
		-- the Y-position check above alone gets permanently stuck on
		-- whichever earlier section last passed. Scrolled-to-bottom is
		-- checked first and short-circuits straight to the last section to
		-- cover exactly that case.
		rail.Think = function()
			if not IsValid(scroll) then return end

			local canvas = scroll:GetCanvas()
			if IsValid(canvas) and #sectionHeaders > 0 then
				local bar = scroll:GetVBar()
				if bar:GetScroll() + scroll:GetTall() >= canvas:GetTall() - 4 then
					activeSection = #sectionHeaders
					return
				end
			end

			local top = scroll:GetVBar():GetScroll() + 40
			local best = 1
			for index, hdr in ipairs(sectionHeaders) do
				if IsValid(hdr) and hdr:GetY() <= top then best = index end
			end
			activeSection = best
		end

		local intro = PDCity.RULES.Intro or ""
		if intro ~= "" then BuildIntroBlock(scroll, intro) end

		for index, section in ipairs(sections) do
			sectionHeaders[index] = BuildSectionHeader(scroll, index, section)

			for ruleIndex, rule in ipairs(section.Rules or {}) do
				BuildRuleCard(scroll, index .. "." .. ruleIndex, rule)
			end
		end

		-- Breathing room under the last card so it isn't flush against the
		-- bottom edge when scrolled all the way down.
		local tail = vgui.Create("DPanel", scroll)
		tail:Dock(TOP)
		tail:SetTall(24)
		tail.Paint = function() end

	end

	Refresh()
	hook.Add("PDCity_RulesUpdated", root, Refresh)
	root.OnRemove = function() hook.Remove("PDCity_RulesUpdated", root) end

	return root

end
