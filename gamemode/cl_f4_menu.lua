--[[---------------------------------------------------------
	F4 roleplay menu. Pressing F4 runs the native "gm_showspare2"
	concommand, which the server picks up as GM:ShowSpare2(ply) and
	forwards to us via Player:ConCommand (see init.lua) - same mechanism
	as the F1 help menu (see cl_f1_menu.lua).

	Two pages, selected by a left sidebar like the F1 menu:
	  Jobs      - job cards grouped into a grid per section
	              (see PDCity.SECTIONS in core/sh_jobs.lua)
	  Entities  - purchasable entities (see core/sh_f4_entities.lua)
-----------------------------------------------------------]]

local JOB_CARD = {}

function JOB_CARD:Init()
	self.HoverAlpha = 0
end

-- PDCityJobCard is registered off plain DPanel, which never fires
-- DoClick on its own the way DButton does - setting card.DoClick alone
-- (BuildJobCard below) was a silent no-op, the actual bug behind "the
-- side card doesn't work" (nothing happened on click at all). Wiring it
-- here, once, at the panel type level, rather than repeating this same
-- OnMousePressed override on every card instance.
function JOB_CARD:OnMousePressed(mcode)
	if mcode == MOUSE_LEFT and self.DoClick then self:DoClick() end
end

function JOB_CARD:Think()
	local target = self:IsHovered() and 1 or 0
	self.HoverAlpha = Lerp(FrameTime() * 8, self.HoverAlpha, target)
end

function JOB_CARD:Paint(w, h)
	local bg = PDCity.THEME.Panel
	if self.HoverAlpha > 0.01 then
		-- Lerps its own alpha too now, rather than hardcoding 255 - that
		-- silently un-did the 90%-opacity theme (cl_theme.lua) the moment
		-- a card was hovered, popping it back to fully opaque.
		bg = ColorAlpha(Color(
			Lerp(self.HoverAlpha, PDCity.THEME.Panel.r, PDCity.THEME.PanelHover.r),
			Lerp(self.HoverAlpha, PDCity.THEME.Panel.g, PDCity.THEME.PanelHover.g),
			Lerp(self.HoverAlpha, PDCity.THEME.Panel.b, PDCity.THEME.PanelHover.b)
		), Lerp(self.HoverAlpha, PDCity.THEME.Panel.a, PDCity.THEME.PanelHover.a))
	end
	draw.RoundedBox(6, 0, 0, w, h, bg)

	-- A thin outline rather than the old thick top-strip - reads as a
	-- formal, bordered card instead of a loud colour bar, and doubles as
	-- the "you can click this" affordance on hover now that there's no
	-- separate button.
	surface.SetDrawColor(self.CurrentBorder or (self.HoverAlpha > 0.5 and self.JobColor or PDCity.THEME.Border))
	surface.DrawOutlinedRect(0, 0, w, h, self.CurrentBorder and 2 or 1)
end

vgui.Register("PDCityJobCard", JOB_CARD, "DPanel")


-- Job cards - wide, short rows (a small square portrait on the left,
-- name/description to the right) rather than tall portrait-on-top
-- tiles, specifically so more jobs are visible on screen at once
-- without scrolling - the tall version looked tidier per-card but only
-- fit a handful before needing to scroll.
local JOB_CARD_WIDE = 300
local JOB_CARD_TALL = 68
local JOB_CARD_PORTRAIT_SIZE = 52

-- Entity cards match the job cards' wide-short-row shape (see above) so
-- both pages read as one consistent list style - but unlike jobs, there's
-- no slide-out detail panel for entities; the buy button lives directly
-- on the row itself instead of behind a click-through.
local ENTITY_CARD_WIDE = JOB_CARD_WIDE
local ENTITY_CARD_TALL = JOB_CARD_TALL
local ENTITY_CARD_PORTRAIT_SIZE = JOB_CARD_PORTRAIT_SIZE

--[[---------------------------------------------------------
	Jobs page
-----------------------------------------------------------]]

-- Job cards no longer share BuildCard with the Entities page (used to,
-- but the two have diverged enough - no buy button, a formal centered
-- layout, a status badge instead of an action button - that forcing
-- them through the same scaffolding meant more opts-juggling than just
-- laying this out directly).
local function BuildJobCard(grid, ply, frame, id, job, ShowJobDetail)

	local isCurrent = IsValid(ply) and ply:Team() == id
	local isStaffLocked = job.StaffOnly and not PDCity.IsStaff(ply)

	-- Whitelist-only category (core/sh_jobs.lua's PDCity.IsSectionWhitelistOnly) -
	-- completely replaces the RequiredLevel check below, same as the
	-- server-authoritative logic in core/sv_jobs.lua's PDCity.ApplyJob.
	local isWhitelistSection = PDCity.IsSectionWhitelistOnly(job.Section)
	local isBlacklisted = isWhitelistSection and PDCity.AmIDepartmentBanned(job.Section)
	local requiredWhitelistLevel = isWhitelistSection and math.max(1, job.RequiredWhitelistLevel or 1)
	local isWhitelistLocked = isWhitelistSection and not isBlacklisted
		and PDCity.MyWhitelistLevel(job.Section) < requiredWhitelistLevel

	-- Ranks unlocked by class level (core/sh_xp.lua) - shown greyed out
	-- with the level requirement rather than hidden, so it reads as a
	-- goal to work towards rather than a mystery. Server-authoritative
	-- check lives in core/sv_jobs.lua's PDCity.ApplyJob; this is only
	-- the display, driven by the same last-synced XP the F1 "Job
	-- Levels" tab uses (core/sh_xp.lua, cl_f1_menu.lua). Doesn't apply at
	-- all in a whitelist-only category (see above), or while the XP
	-- system itself is turned off (core/sh_xp_settings.lua) - the server
	-- won't enforce it either way in that case.
	local levelCheckActive = not isWhitelistSection and job.RequiredLevel and PDCity.XP_ENABLED
	local myLevel = levelCheckActive and PDCity.LevelForXP((PDCity.MY_JOB_XP or {})[job.Section] or 0)
	local isLevelLocked = levelCheckActive and myLevel < job.RequiredLevel

	local isLocked = isStaffLocked or isLevelLocked or isWhitelistLocked or isBlacklisted
	local isSelectable = not isCurrent and not isLocked

	local card = vgui.Create("PDCityJobCard", grid)
	card:SetSize(JOB_CARD_WIDE, JOB_CARD_TALL)
	card:SetMouseInputEnabled(true)
	card.JobColor = job.Color
	card.CurrentBorder = isCurrent and job.Color or nil

	-- Small square portrait on the left rather than a tall banner on
	-- top - one of the job's own Models (core/sh_jobs.lua), same pool a
	-- player spawning into this job would actually be given. Framed off
	-- the model's OWN render bounds rather than fixed world-height
	-- guesses, so it adapts to whichever player model a job uses.
	local portraitHolder = vgui.Create("DPanel", card)
	portraitHolder:Dock(LEFT)
	portraitHolder:SetWide(JOB_CARD_PORTRAIT_SIZE)
	-- Explicit height, not left to Dock(LEFT)'s own auto-stretch - that
	-- stretch only resolves on the NEXT layout pass, so the DModelPanel
	-- created below (docked FILL inside this) could get parented into a
	-- still-zero-height panel and never pick up a real size afterwards,
	-- which is what was rendering as an empty portrait. The tall-card
	-- version never hit this because that portrait holder always had an
	-- explicit SetTall of its own, set before the model panel existed.
	portraitHolder:SetTall(JOB_CARD_TALL - 16)
	portraitHolder:DockMargin(8, 8, 0, 8)
	portraitHolder.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.TitleBar)
	end

	PDCity.BuildPortrait(portraitHolder, PDCity.GetJobPortraitModel(job))

	-- Status badge - a small right-aligned label rather than a
	-- full-width button, only shown when there's actually something to
	-- say (locked/current). A selectable card says nothing here at
	-- rest; the hover border + cursor are the only affordance.
	local badgeText, badgeColor
	if isBlacklisted then
		badgeText, badgeColor = "BLACKLISTED", Color(200, 60, 60)
	elseif isStaffLocked then
		badgeText, badgeColor = "STAFF ONLY", PDCity.THEME.TextDim
	elseif isWhitelistLocked then
		badgeText, badgeColor = "WHITELIST LVL " .. requiredWhitelistLevel .. " REQ.", PDCity.THEME.TextDim
	elseif isLevelLocked then
		badgeText, badgeColor = "LVL " .. job.RequiredLevel .. " REQ.", PDCity.THEME.TextDim
	elseif isCurrent then
		badgeText, badgeColor = "CURRENT", job.Color
	end

	if badgeText then
		local badge = vgui.Create("DLabel", card)
		badge:Dock(RIGHT)
		badge:SetWide(70)
		badge:DockMargin(0, 8, 10, 8)
		badge:SetFont("PDCity_Small")
		badge:SetText(badgeText)
		badge:SetTextColor(badgeColor)
		badge:SetContentAlignment(6) -- right-centered
		badge:SetWrap(true)
		badge:SetMouseInputEnabled(false)
	end

	-- Name + description stacked to the right of the portrait, filling
	-- whatever width is left. Full description is a tooltip rather than
	-- wrapped body text - there's no room for it at this card height,
	-- and a tooltip means it's not lost, just one hover away.
	local textHolder = vgui.Create("DPanel", card)
	textHolder:Dock(FILL)
	textHolder:DockMargin(10, 8, 8, 8)
	textHolder.Paint = function() end
	textHolder:SetMouseInputEnabled(false)

	local nameLabel = vgui.Create("DLabel", textHolder)
	nameLabel:Dock(TOP)
	nameLabel:SetTall(20)
	nameLabel:SetFont("PDCity_Heading")
	nameLabel:SetText(job.Name)
	nameLabel:SetTextColor(PDCity.THEME.Text)
	nameLabel:SetMouseInputEnabled(false)

	local descLabel = vgui.Create("DLabel", textHolder)
	descLabel:Dock(TOP)
	descLabel:SetFont("PDCity_Small")
	descLabel:SetText(job.Description or "")
	descLabel:SetTextColor(PDCity.THEME.TextDim)
	descLabel:SetWrap(true)
	descLabel:SetAutoStretchVertical(true)
	descLabel:SetMouseInputEnabled(false)

	if job.Description and job.Description ~= "" then
		card:SetTooltip(job.Description)
	end

	-- Click opens the slide-out detail panel (below) rather than
	-- becoming the job immediately - that's what its own Become button
	-- is for now. Works for locked/current cards too, so their detail
	-- (and WHY they're locked) is still visible on click, just with
	-- Become disabled.
	card:SetCursor("hand")
	card.DoClick = function()
		ShowJobDetail(job, id, isSelectable, badgeText, badgeColor)
	end

end

local function BuildJobsPage(parent, ply, frame, ShowJobDetail)

	local scroll = vgui.Create("DScrollPanel", parent)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 12, 16, 12)
	PDCity.ApplyFastScroll(scroll)

	for index, sectionName in ipairs(PDCity.SECTIONS) do

		local ids = PDCity.GetJobIDsInSection(sectionName)

		if #ids > 0 then

			-- Doubles as a (discreet) XP bar for the category's own class
			-- level - "Citizens", "Police" etc. as a category ARE a job
			-- class key (job.Section, same string used for RequiredLevel
			-- checks above and core/sv_jobs.lua's rank-ups), so there's
			-- always a real level/progress to show here, not a separate
			-- concept bolted on.
			local sectionXP = (PDCity.MY_JOB_XP or {})[sectionName] or 0
			local sectionLevel, into, span = PDCity.XPProgress(sectionXP)
			local sectionFrac = span > 0 and (into / span) or 1

			local header = vgui.Create("DPanel", scroll)
			header:Dock(TOP)
			header:SetTall(28)
			header:DockMargin(2, index == 1 and 0 or 28, 0, 14)
			header.Paint = function(self, w, h)
				draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.TitleBar)
				if sectionFrac > 0 then
					-- Low alpha - a tint across the bar's own width, not a
					-- separate loud progress element competing with the text.
					surface.SetDrawColor(ColorAlpha(PDCity.THEME.Accent, 45))
					surface.DrawRect(0, 0, w * sectionFrac, h)
				end
				local label = sectionName .. "   •   Level " .. sectionLevel
				draw.SimpleText(label, "PDCity_Title", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end

			local grid = vgui.Create("DIconLayout", scroll)
			grid:Dock(TOP)
			grid:SetSpaceX(10)
			grid:SetSpaceY(10)

			for _, id in ipairs(ids) do
				local job = PDCity.GetJob(id)
				if job then
					local ok, err = pcall(BuildJobCard, grid, ply, frame, id, job, ShowJobDetail)
					if not ok then
						print("[" .. PDCity.BRAND_TAG .. "] ERROR building job card for id=" .. tostring(id) .. ": " .. tostring(err))
					end
				end
			end

		end

	end

	return scroll

end

--[[---------------------------------------------------------
	Entities page
-----------------------------------------------------------]]

local function BuildEntityCard(grid, ply, cfg)

	-- cfg.Model (cl_f4_admin.lua's "Model shown on the shop card" field)
	-- is an explicit override for when the automatic lookup below can't
	-- find one - a SENT that sets its model in Initialize() rather than a
	-- static ENT.Model (several of this gamemode's own entities do) has
	-- nothing for PDCity.GetItemModel to detect on its own. Best-effort
	-- either way: a class/model with no obvious single model (point/logic
	-- entities) falls back to just its small icon16.
	local previewModel = cfg.Model or PDCity.GetItemModel(cfg.Class)

	-- A shipment sells a crate of N rather than a single item, so say so
	-- on the card - the price is for the whole crate.
	local shipment = (cfg.ShipmentCount or 0) > 1 and cfg.ShipmentCount or nil
	local cardName = shipment and (cfg.Name .. "  (x" .. shipment .. ")") or cfg.Name

	local card = vgui.Create("PDCityJobCard", grid)
	card:SetSize(ENTITY_CARD_WIDE, ENTITY_CARD_TALL)
	card.JobColor = PDCity.THEME.Accent

	-- Small square preview on the left, same slot the job cards use -
	-- either the entity's own model (SpawnIcon, same as the old bigger
	-- preview above the header) or, failing that, its icon16.
	local portraitHolder = vgui.Create("DPanel", card)
	portraitHolder:Dock(LEFT)
	portraitHolder:SetWide(ENTITY_CARD_PORTRAIT_SIZE)
	-- Explicit height for the same reason as the job card's own
	-- portraitHolder - Dock(LEFT)'s auto-stretch doesn't resolve until
	-- the next layout pass, too late for the SpawnIcon docked FILL inside.
	portraitHolder:SetTall(ENTITY_CARD_TALL - 16)
	portraitHolder:DockMargin(8, 8, 0, 8)
	portraitHolder.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.TitleBar)
		if not previewModel and cfg.Icon then
			local mat = PDCity.GetIconMaterial(cfg.Icon)
			if mat and not mat:IsError() then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(mat)
				surface.DrawTexturedRect(w / 2 - 12, h / 2 - 12, 24, 24)
			end
		end
	end

	if previewModel then
		local icon = vgui.Create("SpawnIcon", portraitHolder)
		icon:Dock(FILL)
		icon:DockMargin(1, 1, 1, 1)
		icon:SetModel(previewModel)
		icon:SetMouseInputEnabled(false)
	end

	local canAccess, lockReason = PDCity.CanAccessF4Entity(ply, cfg)
	local canAfford = LocalPlayer():GetNWInt("PDCity_Money", 0) >= cfg.Price

	-- No separate buy button - the whole row IS the buy action (matching
	-- the job cards, which already click-to-select the same way; only
	-- entities used to differ, back when this had its own button because
	-- the price needed to look clickable). Price is now a plain label
	-- docked right, not a coloured button box, so it reads as information
	-- rather than a second, competing click target.
	local priceLabel = vgui.Create("DLabel", card)
	priceLabel:Dock(RIGHT)
	priceLabel:SetWide(80)
	priceLabel:DockMargin(0, 8, 10, 8)
	priceLabel:SetContentAlignment(5)
	priceLabel:SetMouseInputEnabled(false)

	if not canAccess then
		-- Lock reasons are a sentence, not a price - keep them in the
		-- small/dim body font rather than the bold price font below,
		-- which is sized and weighted for a short "$1234"/"SPAWN" only.
		priceLabel:SetFont("PDCity_Small")
		priceLabel:SetText(lockReason)
		priceLabel:SetTextColor(PDCity.THEME.TextDim)
	else
		local label = cfg.Price > 0 and ("$" .. cfg.Price) or "SPAWN"
		priceLabel:SetFont("PDCity_PriceTag")
		priceLabel:SetText(label)
		priceLabel:SetTextColor(canAfford and PDCity.THEME.PriceGreen or PDCity.THEME.TextDim)
	end

	if canAccess then
		card:SetCursor("hand")
		card.DoClick = function()
			RunConsoleCommand("pdcity_buyentity", cfg.ID)
		end
	end

	-- Name + description stacked to the right of the portrait, same as
	-- the job cards - full description is a tooltip, no room to wrap it
	-- inline at this row height.
	local textHolder = vgui.Create("DPanel", card)
	textHolder:Dock(FILL)
	textHolder:DockMargin(10, 8, 8, 8)
	textHolder.Paint = function() end
	textHolder:SetMouseInputEnabled(false)

	local nameLabel = vgui.Create("DLabel", textHolder)
	nameLabel:Dock(TOP)
	nameLabel:SetTall(20)
	nameLabel:SetFont("PDCity_Heading")
	nameLabel:SetText(cardName)
	nameLabel:SetTextColor(PDCity.THEME.Text)
	nameLabel:SetMouseInputEnabled(false)

	local descLabel = vgui.Create("DLabel", textHolder)
	descLabel:Dock(TOP)
	descLabel:SetFont("PDCity_Small")
	descLabel:SetText(cfg.Description or "")
	descLabel:SetTextColor(PDCity.THEME.TextDim)
	descLabel:SetWrap(true)
	descLabel:SetAutoStretchVertical(true)
	descLabel:SetMouseInputEnabled(false)

	if cfg.Description and cfg.Description ~= "" then
		card:SetTooltip(cfg.Description)
	end

end

local function BuildEntitiesPage(parent, ply)

	local scroll = vgui.Create("DScrollPanel", parent)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 12, 16, 12)
	PDCity.ApplyFastScroll(scroll)

	local shownAny = false

	for index, sectionName in ipairs(PDCity.F4_SECTIONS) do

		local cfgs = {}
		for _, cfg in ipairs(PDCity.GetF4EntitiesInSection(sectionName)) do
			-- Job-restricted entries are left off the menu entirely for
			-- players who don't qualify, rather than shown locked -
			-- unlike a rank restriction, which still shows (see
			-- BuildEntityCard) so players know what to work towards.
			if PDCity.HasF4JobAccess(ply, cfg) then
				table.insert(cfgs, cfg)
			end
		end

		if #cfgs > 0 then

			shownAny = true

			local header = vgui.Create("DLabel", scroll)
			header:Dock(TOP)
			header:DockMargin(2, index == 1 and 0 or 20, 0, 10)
			header:SetFont("PDCity_Title")
			header:SetText(sectionName)
			header:SetTextColor(PDCity.THEME.Text)
			header:SizeToContents()

			local grid = vgui.Create("DIconLayout", scroll)
			grid:Dock(TOP)
			grid:SetSpaceX(12)
			grid:SetSpaceY(12)

			for _, cfg in ipairs(cfgs) do
				local ok, err = pcall(BuildEntityCard, grid, ply, cfg)
				if not ok then
					print("[" .. PDCity.BRAND_TAG .. "] ERROR building entity card for id=" .. tostring(cfg.ID) .. ": " .. tostring(err))
				end
			end

		end

	end

	if not shownAny then
		local empty = vgui.Create("DLabel", scroll)
		empty:Dock(TOP)
		empty:SetFont("PDCity_Body")
		empty:SetText("Nothing available for your current job yet - check back later.")
		empty:SetTextColor(PDCity.THEME.TextDim)
		empty:SizeToContents()
	end

	return scroll

end

--[[---------------------------------------------------------
	Non-interactive live preview of the real F4 menu, built for the F4
	Catalogue Admin's "Enable Preview" button (cl_f4_admin.lua) - shows
	whichever tab the admin is currently editing, reusing the EXACT same
	page-builder functions the real popup below opens
	(BuildJobsPage/BuildEntitiesPage) rather than a separate
	reimplementation, so there's nothing for this to drift out of sync
	with as those change.

	Deliberately NOT the real interactive menu shrunk down - it's parented
	inside another panel instead of its own popup DFrame, and a
	transparent full-size panel is created LAST (so it's frontmost in
	z-order) purely to swallow every click before it reaches anything
	real underneath. That matters here specifically: an entity card's
	DoClick runs the real pdcity_buyentity concommand (a genuine
	purchase), so without this an admin clicking around "just to look"
	could end up actually buying/spawning things. Job cards are already
	harmless on their own (the no-op ShowJobDetail passed in below just
	does nothing on click), but the blocker covers every tab uniformly
	rather than relying on each page happening to be safe.
-----------------------------------------------------------]]
function PDCity.BuildF4PreviewPanel(parent, ply, tabName)
	parent:Clear(true)

	local w, h = parent:GetWide(), parent:GetTall()

	local root = vgui.Create("DPanel", parent)
	root:SetSize(w, h)
	root.Paint = function(self, pw, ph)
		draw.RoundedBox(0, 0, 0, pw, ph, PDCity.THEME.Background)
		draw.RoundedBoxEx(0, 0, 0, pw, 46, PDCity.THEME.TitleBar, true, true, false, false)
		draw.SimpleText("Roleplay", "PDCity_Title", 18, 23, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local sidebar = vgui.Create("DPanel", root)
	sidebar:SetPos(0, 46)
	sidebar:SetSize(150, h - 46)
	sidebar.Paint = function(self, sw, sh)
		draw.RoundedBoxEx(0, 0, 0, sw, sh, PDCity.THEME.TitleBar, false, false, false, true)
	end

	local TAB_NAMES = { "Jobs", "Entities" }
	local y = 10
	for _, name in ipairs(TAB_NAMES) do
		local btn = vgui.Create("PDCitySidebarTab", sidebar)
		btn:SetLabel(name)
		btn:SetPos(8, y)
		btn:SetSize(134, 34)
		btn:SetActive(name == tabName)
		y = y + 38
	end

	local content = vgui.Create("DPanel", root)
	content:SetPos(150, 46)
	content:SetSize(w - 150, h - 46)
	content.Paint = function() end

	if tabName == "Entities" then
		BuildEntitiesPage(content, ply)
	else
		BuildJobsPage(content, ply, nil, function() end)
	end

	local clickBlocker = vgui.Create("DPanel", root)
	clickBlocker:SetSize(w, h)
	clickBlocker:SetMouseInputEnabled(true)
	clickBlocker:SetCursor("no")
	clickBlocker.Paint = function() end

	return root
end

--[[---------------------------------------------------------
	Frame with sidebar, same structure as the F1 menu.
-----------------------------------------------------------]]

local function OpenPDCityJobs()

	if IsValid(GAMEMODE.PDCityJobFrame) then
		GAMEMODE.PDCityJobFrame:Remove()
		return
	end

	-- Job detail slide-out sizing - declared up here (before the frame)
	-- since the onResize callback below needs them, along with forward
	-- declarations of the panels it repositions. All of these are only
	-- actually created further down.
	local DETAIL_WIDE = 240
	-- Gap kept clear on the right (the DScrollPanel's own scrollbar
	-- lives right up against the frame's edge) and top/bottom (so it
	-- reads as a floating card, not a flush-docked panel) - reported as
	-- covering the scrollbar when it was flush against the edge.
	local DETAIL_MARGIN = 18
	local sidebar, content, detail

	-- Before creating the frame, so the dim panel it creates
	-- (cl_menu_dim.lua) ends up behind it in the popup stack.
	PDCity.PushMenuDim()

	local frameW, frameH = PDCity.ResponsiveFrameSize(1400, 900)
	local frame = PDCity.CreateModernFrame("Roleplay", frameW, frameH, function(newW, newH)
		if IsValid(sidebar) then sidebar:SetSize(150, newH - 48) end
		if IsValid(content) then content:SetSize(newW - 150, newH - 48) end

		if IsValid(detail) then
			detail:SetTall(newH - 48 - DETAIL_MARGIN * 2)
			-- Snap immediately to whichever edge (open or closed) it
			-- should currently be at for the NEW width, rather than
			-- animating - mid-resize is not the moment for a slide
			-- transition, and CurX needs to actually match or the next
			-- Think would slide it there from the wrong place anyway.
			detail.TargetX = detail.IsOpen and (newW - DETAIL_WIDE - DETAIL_MARGIN) or newW
			detail.CurX = detail.TargetX
			detail:SetPos(detail.CurX, 48 + DETAIL_MARGIN)
		end
	end)
	GAMEMODE.PDCityJobFrame = frame

	-- OnRemove, not OnClose - this frame closes itself via a bare
	-- :Remove() when F4 is pressed again (line 606 above), which never
	-- fires OnClose (see cl_f1_menu.lua's own identical note).
	frame.OnRemove = function()
		PDCity.PopMenuDim()
	end

	-- F4 (whatever "gm_showspare2" is actually bound to) and Escape both
	-- close this. Caught here rather than left to the "already open, so
	-- close" toggle at the top of this function: a keyboard-input popup
	-- takes keystrokes into VGUI instead of running the console bind, so
	-- pressing F4 again while this is up never re-runs pdcity_showjobs and
	-- that toggle never gets its second call. Same reasoning, and the same
	-- fix, as cl_f1_menu.lua's own close-key handler.
	local closeKey = PDCity.BoundKey("gm_showspare2", KEY_F4)
	frame.OnKeyCodePressed = function(self, key)
		if key == KEY_ESCAPE or key == closeKey then self:Close() end
	end

	sidebar = vgui.Create("DPanel", frame)
	sidebar:SetPos(0, 48)
	sidebar:SetSize(150, frame:GetTall() - 48)
	sidebar.Paint = function(self, w, h)
		draw.RoundedBoxEx(8, 0, 0, w, h, PDCity.THEME.TitleBar, false, false, false, true)
	end

	content = vgui.Create("DPanel", frame)
	content:SetPos(150, 48)
	content:SetSize(frame:GetWide() - 150, frame:GetTall() - 48)
	content.Paint = function() end

	local ply = LocalPlayer()

	--[[-----------------------------------------------------
		Job detail slide-out - opened by clicking a job card
		(BuildJobCard above). Parented to the FRAME itself, not the
		Jobs page's own scroll panel, so it overlays on top regardless
		of scroll position and isn't affected by DScrollPanel
		auto-parenting new children into its canvas. Semi-transparent,
		slides in from the right edge over a few frames rather than
		popping in.
	-------------------------------------------------------]]
	detail = vgui.Create("DPanel", frame)
	detail:SetSize(DETAIL_WIDE, frame:GetTall() - 48 - DETAIL_MARGIN * 2)
	detail.IsOpen = false
	detail.CurX = frame:GetWide()
	detail.TargetX = frame:GetWide() -- starts fully off-screen, closed
	detail:SetPos(detail.CurX, 48 + DETAIL_MARGIN)
	detail:SetMouseInputEnabled(false) -- flips true only while actually open, see ShowJobDetail
	detail.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(PDCity.THEME.TitleBar, 235))
	end
	detail.Think = function(self)
		if math.abs(self.CurX - self.TargetX) < 0.5 then
			self.CurX = self.TargetX
		else
			self.CurX = Lerp(FrameTime() * 9, self.CurX, self.TargetX)
		end
		self:SetPos(self.CurX, 48 + DETAIL_MARGIN)
	end

	local function HideJobDetail()
		detail.IsOpen = false
		detail.TargetX = frame:GetWide()
		detail:SetMouseInputEnabled(false)
	end

	local function ShowJobDetail(job, id, isSelectable, badgeText, badgeColor)
		detail:Clear()
		detail.IsOpen = true
		detail:SetMouseInputEnabled(true)
		detail.TargetX = frame:GetWide() - DETAIL_WIDE - DETAIL_MARGIN

		-- DLabel, like DPanel, never fires DoClick on its own (only
		-- DButton-derived panels do) - same bug the job cards themselves
		-- just had, fixed the same way: enable mouse input and handle
		-- the press directly rather than relying on a DoClick field
		-- nothing would ever call.
		local closeBtn = vgui.Create("DLabel", detail)
		closeBtn:SetPos(DETAIL_WIDE - 26, 8)
		closeBtn:SetSize(18, 18)
		closeBtn:SetFont("PDCity_Heading")
		closeBtn:SetText("x")
		closeBtn:SetTextColor(PDCity.THEME.TextDim)
		closeBtn:SetContentAlignment(5)
		closeBtn:SetCursor("hand")
		closeBtn:SetMouseInputEnabled(true)
		closeBtn.OnMousePressed = function(self, mcode)
			if mcode == MOUSE_LEFT then HideJobDetail() end
		end

		local portraitHolder = vgui.Create("DPanel", detail)
		portraitHolder:SetPos(20, 36)
		portraitHolder:SetSize(DETAIL_WIDE - 40, 150)
		portraitHolder.Paint = function(self, w, h)
			draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
		end
		PDCity.BuildPortrait(portraitHolder, PDCity.GetJobPortraitModel(job))

		local nameLabel = vgui.Create("DLabel", detail)
		nameLabel:SetPos(20, 196)
		nameLabel:SetSize(DETAIL_WIDE - 40, 26)
		nameLabel:SetFont("PDCity_Title")
		nameLabel:SetText(job.Name)
		nameLabel:SetTextColor(PDCity.THEME.Text)
		nameLabel:SetContentAlignment(5)

		local divider = vgui.Create("DPanel", detail)
		divider:SetPos(20, 226)
		divider:SetSize(DETAIL_WIDE - 40, 1)
		divider.Paint = function(self, w, h)
			surface.SetDrawColor(PDCity.THEME.Border)
			surface.DrawRect(0, 0, w, h)
		end

		local descLabel = vgui.Create("DLabel", detail)
		descLabel:SetPos(20, 236)
		descLabel:SetSize(DETAIL_WIDE - 40, 70)
		descLabel:SetFont("PDCity_Small")
		descLabel:SetText(job.Description or "")
		descLabel:SetTextColor(PDCity.THEME.TextDim)
		descLabel:SetWrap(true)

		local payLabel = vgui.Create("DLabel", detail)
		payLabel:SetPos(20, 308)
		payLabel:SetSize(DETAIL_WIDE - 40, 20)
		payLabel:SetFont("PDCity_Small")
		payLabel:SetText(job.Salary and job.Salary > 0 and ("Pay: $" .. job.Salary .. " every 15 min") or "Pay: none")
		payLabel:SetTextColor(PDCity.THEME.TextDim)

		local nextY = 330

		if badgeText then
			local badgeLabel = vgui.Create("DLabel", detail)
			badgeLabel:SetPos(20, nextY)
			badgeLabel:SetSize(DETAIL_WIDE - 40, 20)
			badgeLabel:SetFont("PDCity_Small")
			badgeLabel:SetText(badgeText)
			badgeLabel:SetTextColor(badgeColor or PDCity.THEME.TextDim)
			nextY = nextY + 22
		end

		-- Display-only for now (core/sv_job_catalogue.lua's NormalizeFlag -
		-- no gameplay system reads these yet, set from the F4 admin
		-- editor's Jobs tab) - only shown at all once at least one is set,
		-- so an ordinary job with none of these doesn't get an empty row.
		if job.CanRaid or job.CanMug or job.CanKidnap then
			local flags = {}
			if job.CanRaid then table.insert(flags, "Raid") end
			if job.CanMug then table.insert(flags, "Mug") end
			if job.CanKidnap then table.insert(flags, "Kidnap") end

			local flagsLabel = vgui.Create("DLabel", detail)
			flagsLabel:SetPos(20, nextY)
			flagsLabel:SetSize(DETAIL_WIDE - 40, 20)
			flagsLabel:SetFont("PDCity_Small")
			flagsLabel:SetText("Can: " .. table.concat(flags, ", "))
			flagsLabel:SetTextColor(PDCity.THEME.Accent2)
		end

		local becomeBtn = vgui.Create("DButton", detail)
		becomeBtn:SetPos(20, detail:GetTall() - 46)
		becomeBtn:SetSize(DETAIL_WIDE - 40, 30)
		becomeBtn:SetText("")
		becomeBtn:SetEnabled(isSelectable)
		becomeBtn.Paint = function(self, w, h)
			local col
			if not isSelectable then
				col = PDCity.THEME.Border
			else
				col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
			end
			draw.RoundedBox(5, 0, 0, w, h, col)
			draw.SimpleText(isSelectable and "BECOME" or (badgeText or "UNAVAILABLE"),
				"PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		becomeBtn.DoClick = function()
			if not isSelectable then return end
			RunConsoleCommand("pdcity_selectjob", id)
			frame:Close()
		end
	end

	local pages = {
		{ Name = "Jobs", Icon = "icon16/user_suit.png", Build = function() return BuildJobsPage(content, ply, frame, ShowJobDetail) end },
		{ Name = "Entities", Icon = "icon16/cart.png", Build = function() return BuildEntitiesPage(content, ply) end },
	}

	local panels = {}
	local tabButtons = {}
	local y = 10

	local function SelectTab(index)
		for i, btn in ipairs(tabButtons) do
			btn:SetActive(i == index)
		end
		for i, panel in ipairs(panels) do
			panel:SetVisible(i == index)
		end
		if index ~= 1 then HideJobDetail() end
	end

	for i, page in ipairs(pages) do

		local panel = page.Build()
		panel:SetVisible(false)
		panels[i] = panel

		local btn = vgui.Create("PDCitySidebarTab", sidebar)
		btn:SetLabel(page.Name)
		btn:SetIcon(page.Icon)
		btn:SetPos(8, y)
		btn:SetSize(134, 34)
		btn.DoClick = function() SelectTab(i) end
		tabButtons[i] = btn

		y = y + 38

	end

	SelectTab(1)

	-- Whitelist editor - a separate top-level frame, not a page of this
	-- menu, so it doesn't go through SelectTab. A thin divider marks it as
	-- a different kind of sidebar entry. (The owner's Catalogue editor
	-- lives in the F1 menu now - cl_f1_menu.lua.)
	local y2 = y + 10

	if PDCity.IsSuperAdminPlus(ply) then
		local divider = vgui.Create("DPanel", sidebar)
		divider:SetPos(16, y2)
		divider:SetSize(118, 1)
		divider.Paint = function(self, w, h)
			surface.SetDrawColor(PDCity.THEME.Border)
			surface.DrawRect(0, 0, w, h)
		end
		y2 = y2 + 10

		-- "A role that can access the whitelist regardless of department"
		-- (core/sh_whitelist.lua) - a department-scoped manager (level 6+
		-- in just their own department) uses "!whitelist" instead
		-- (core/sv_whitelist_chat.lua), no tab here for them.
		local whitelistBtn = vgui.Create("PDCitySidebarTab", sidebar)
		whitelistBtn:SetLabel("Whitelist")
		whitelistBtn:SetIcon("icon16/shield.png")
		whitelistBtn:SetPos(8, y2)
		whitelistBtn:SetSize(134, 34)
		whitelistBtn.DoClick = function() PDCity.OpenWhitelistMenu() end
		y2 = y2 + 38
	end

	-- Rebuilds just the Entities tab in place if the owner changes the
	-- catalogue (core/sh_f4_catalogue.lua) while this menu is open.
	hook.Add("PDCity_F4CatalogueUpdated", frame, function()
		local wasVisible = IsValid(panels[2]) and panels[2]:IsVisible()
		if IsValid(panels[2]) then panels[2]:Remove() end
		panels[2] = BuildEntitiesPage(content, ply)
		panels[2]:SetVisible(wasVisible)
	end)

	-- Same, for the Jobs tab when the owner adds/removes a custom job or
	-- job category (core/sh_job_catalogue.lua) while this menu is open.
	hook.Add("PDCity_JobCatalogueUpdated", frame, function()
		local wasVisible = IsValid(panels[1]) and panels[1]:IsVisible()
		HideJobDetail() -- the job it's showing may no longer exist post-update
		if IsValid(panels[1]) then panels[1]:Remove() end
		panels[1] = BuildJobsPage(content, ply, frame, ShowJobDetail)
		panels[1]:SetVisible(wasVisible)
	end)

	frame.OnClose = function()
		hook.Remove("PDCity_F4CatalogueUpdated", frame)
		hook.Remove("PDCity_JobCatalogueUpdated", frame)
	end

end

concommand.Add("pdcity_showjobs", OpenPDCityJobs)
