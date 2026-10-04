--[[---------------------------------------------------------
	Shared visual theme for PD City's custom menus (F1 info, F4 jobs).
	Kept in one place so both look cohesive and are easy to retheme later.
-----------------------------------------------------------]]

-- Light grey, replacing the cold steel-blue pass - neutral grey panels
-- (equal-ish R/G/B, no blue tint baked into the backgrounds themselves
-- like the steel-blue pass had) and noticeably lighter than before, with
-- the same blue accent kept for highlights/selection so it still reads
-- clearly against the lighter surfaces.
--
-- The four surface colours (Background/TitleBar/Panel/PanelHover) and
-- Border carry 230 alpha (90% opaque), not the usual fully-opaque 255 -
-- requested as "barely see-through". This has to live HERE, baked into
-- the colours every menu draws its panels with, rather than as a
-- Panel:SetAlpha() on the outer frame - that multiplier resets back to
-- each CHILD panel's own alpha (255 by default) before that child's own
-- Paint runs rather than compounding with its parent, so it only ever
-- affected the frame's own direct Paint (background/titlebar), never
-- the sidebar/content/cards a menu builds as child panels on top of it
-- (reported as "the side stuff doesn't show through" - it didn't).
-- Text/Accent colours stay fully opaque - legibility and highlights
-- shouldn't wash out along with the backgrounds behind them.
PDCity.THEME = {
	Background  = Color(58, 58, 61, 230),
	TitleBar    = Color(48, 48, 51, 230),
	Panel       = Color(72, 72, 76, 230),
	PanelHover  = Color(86, 86, 91, 230),
	Accent      = Color(100, 170, 255, 255), -- same family of blue, kept for highlights
	AccentDim   = Color(70, 120, 180, 255),
	Accent2     = Color(150, 220, 235, 255), -- icy cyan, paired with Accent for the header gradient
	PriceGreen  = Color(80, 210, 120, 255),  -- "dollar green" for affordable price tags (cl_f4_menu.lua)
	Text        = Color(240, 240, 242, 255),
	TextDim     = Color(182, 182, 187, 255),
	Border      = Color(102, 102, 107, 230),
}

-- PD City's own logo (materials/pdcity/PDCity.png) - global, not local,
-- so every menu can reuse this one Material() lookup rather than each
-- re-resolving the same path (cl_welcome.lua's hero banner does, cheaply,
-- since this file loads first - see cl_init.lua's include order).
-- "noclamp smooth" matches the same flags this file already uses
-- elsewhere for fetched (non-.vmt) images.
-- Optional: no logo ships with the gamemode. A server owner can drop one
-- at materials/pdcity/PDCity.png (sent to players by core/sv_resources.lua)
-- or set an image in Site Admin > Site Theme. Every menu checks IsError()
-- and simply leaves the logo out when there isn't one.
PDCity.LOGO_MAT = Material("pdcity/PDCity.png", "noclamp smooth")

--[[---------------------------------------------------------
	Resolves a job/entity "Icon" field (core/sv_f4_catalogue.lua,
	core/sv_job_catalogue.lua) to a Material - either a local silkicon-
	style path (e.g. "icon16/car.png", resolved the normal way) or an
	http(s) image URL, downloaded once and cached to disk under
	data/pdcity_icons/ so it doesn't get re-fetched on every card
	rebuild/reconnect. This is what actually lets someone "upload an
	image" for a shop card that has no model set - there's no real file
	upload from a GMod client, so pasting an image URL here and having it
	fetched down is the practical equivalent.

	Fetching is async, so this returns nil (draw nothing yet) the first
	few calls for a not-yet-cached URL while the download's in flight -
	Paint runs every frame anyway, so the very next frame after the
	fetch completes picks the resolved Material up automatically without
	needing a callback threaded through every caller.

	Material()'s "../data/..." escape (well-established GMod trick - not
	an accident of this implementation) is what lets a Material() call
	load a loose file out of the data/ folder at all - materials/ is
	normally the only place it looks.
-----------------------------------------------------------]]
local IconMaterialCache = {} -- iconPath -> Material, or false while a fetch is in flight

function PDCity.GetIconMaterial(iconPath)
	if not iconPath or iconPath == "" then return nil end

	local cached = IconMaterialCache[iconPath]
	if cached ~= nil then
		return cached or nil -- false (pending) reads back as "not ready yet"
	end

	if not (iconPath:StartsWith("http://") or iconPath:StartsWith("https://")) then
		local mat = Material(iconPath)
		IconMaterialCache[iconPath] = mat
		return mat
	end

	local dataPath = "pdcity_icons/" .. util.CRC(iconPath) .. ".png"
	if file.Exists(dataPath, "DATA") then
		local mat = Material("../data/" .. dataPath)
		IconMaterialCache[iconPath] = mat
		return mat
	end

	IconMaterialCache[iconPath] = false -- mark pending so repeated Paint calls don't queue duplicate fetches
	file.CreateDir("pdcity_icons")
	http.Fetch(iconPath, function(body, len, headers, code)
		if code ~= 200 or not body or #body == 0 then
			IconMaterialCache[iconPath] = nil -- allow a later retry rather than caching the failure forever
			return
		end
		file.Write(dataPath, body)
		IconMaterialCache[iconPath] = Material("../data/" .. dataPath)
	end, function(err)
		IconMaterialCache[iconPath] = nil
	end)

	return nil
end

--[[---------------------------------------------------------
	Every DScrollPanel's vertical scrollbar, restyled globally instead of
	at each of the many places across this gamemode's menus that create
	one - reported as looking "like something out of Windows 98" (stock
	DVScrollBar's chunky 3D-bevelled up/down buttons and grip). Patches
	DScrollPanel's own Init once, here, so every one created from now on
	(anywhere, including any future menu) picks this up automatically.

	Only Paint functions are overridden - nothing about size, position,
	or behaviour changes, so this can't break anything relying on the
	stock scrollbar's geometry (including other addons' own scroll
	panels, which get the same restyle - a discreet flat bar is a strict
	improvement wherever it shows up, not something worth scoping out).
-----------------------------------------------------------]]
do
	local SCROLLPANEL = vgui.GetControlTable("DScrollPanel")
	local BaseInit = SCROLLPANEL.Init

	function SCROLLPANEL:Init()
		BaseInit(self)

		local bar = self:GetVBar()

		bar.Paint = function(self, w, h)
			draw.RoundedBox(0, 0, 0, w, h, PDCity.THEME.Background)
		end

		-- Left functional (still a click = step-scroll) but invisible -
		-- the up/down buttons are most of what reads as "Windows 98"
		-- about the stock skin.
		bar.btnUp.Paint = function() end
		bar.btnDown.Paint = function() end

		bar.btnGrip.Paint = function(self, w, h)
			local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.Border
			draw.RoundedBox(3, 2, 0, w - 4, h, col)
		end
	end
end

--[[---------------------------------------------------------
	DTextEntry, DComboBox, and DListView, restyled globally the same way
	as the scrollbar above - every one of these across every admin/menu
	panel was still stock Derma's white-box-black-text skin (reported as
	"all the white and blocky panels"), because nothing had ever reskinned
	them like DButton (PDCity.StyleButton) or DScrollPanel already were.
	Patching each control table once here means every existing creation
	site picks it up automatically, with nothing to change at any of them.
-----------------------------------------------------------]]

-- DTextEntry's own :Paint is just `derma.SkinHook("Paint","TextEntry",...)`
-- (lua/vgui/dtextentry.lua) - replacing it outright and re-implementing
-- the same placeholder-text hack the stock skin uses (lua/skins/
-- default.lua's SKIN:PaintTextEntry) is simpler and safer than trying to
-- recolour the skin hook itself, which is shared with every other skinned
-- control on the client (including other addons').
do
	local TEXTENTRY = vgui.GetControlTable("DTextEntry")
	local BaseInit = TEXTENTRY.Init

	function TEXTENTRY:Init()
		BaseInit(self)
		self:SetFont("PDCity_Body")
		self:SetTextInset(8, 0)
		self:SetCursor("beam")
	end

	function TEXTENTRY:Paint(w, h)
		local bg = not self:IsEnabled() and PDCity.THEME.Background or (self:HasFocus() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
		draw.RoundedBox(4, 0, 0, w, h, bg)
		surface.SetDrawColor(self:HasFocus() and PDCity.THEME.Accent or PDCity.THEME.Border)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		-- Same "type the placeholder in, draw it, put the real text back"
		-- trick the stock skin uses - DrawTextEntryText always draws
		-- whatever GetText() currently holds, so there's no separate hook
		-- for "draw this instead, only when empty".
		local placeholder = self:GetPlaceholderText()
		if placeholder and placeholder:Trim() ~= "" and (not self:GetText() or self:GetText() == "") then
			local oldText = self:GetText()
			local str = placeholder
			if str:StartsWith("#") then str = str:sub(2) end
			str = language.GetPhrase(str)
			self:SetText(str)
			self:DrawTextEntryText(PDCity.THEME.TextDim, PDCity.THEME.AccentDim, PDCity.THEME.Text)
			self:SetText(oldText)
			return
		end

		self:DrawTextEntryText(PDCity.THEME.Text, PDCity.THEME.AccentDim, PDCity.THEME.Text)
	end
end

-- DComboBox inherits DButton, whose own :Paint draws the skin box then
-- `return false` so the engine's native text-draw fallback still renders
-- the label - overriding :Paint here keeps that same `return false`, and
-- UpdateColours (called every frame DButton normally would recolour the
-- label for hover/down/disabled state) is overridden too so that native
-- text-draw always uses theme colours instead of the skin's near-black
-- default. The little dropdown arrow (self.DropButton, built inside
-- DComboBox's own :Init) is a plain DPanel with a per-instance Paint, so
-- it's re-pointed once here rather than needing its own control-table patch.
do
	local COMBOBOX = vgui.GetControlTable("DComboBox")
	local BaseInit = COMBOBOX.Init

	function COMBOBOX:Init()
		BaseInit(self)
		self:SetFont("PDCity_Body")

		self.DropButton.Paint = function(self, w, h)
			local col = self.ComboBox:IsEnabled() and PDCity.THEME.TextDim or PDCity.THEME.Border
			surface.SetDrawColor(col)
			local cx, cy = w / 2, h / 2
			surface.DrawLine(cx - 4, cy - 2, cx, cy + 2)
			surface.DrawLine(cx, cy + 2, cx + 4, cy - 2)
		end
	end

	function COMBOBOX:Paint(w, h)
		local bg = not self:IsEnabled() and PDCity.THEME.Background or ((self:IsMenuOpen() or self:IsHovered()) and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
		draw.RoundedBox(4, 0, 0, w, h, bg)
		surface.SetDrawColor(self:IsMenuOpen() and PDCity.THEME.Accent or PDCity.THEME.Border)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		return false
	end

	function COMBOBOX:UpdateColours(skin)
		self:SetTextStyleColor(self:IsEnabled() and PDCity.THEME.Text or PDCity.THEME.TextDim)
	end
end

-- DCheckBox (what every DCheckBoxLabel across every admin tab actually
-- wraps) - stock Derma draws it as a plain white box with a black
-- checkmark image, the one control this theme had never touched, which
-- is exactly why it stood out as a jarring white square everywhere else
-- had already been reskinned dark.
do
	local CHECKBOX = vgui.GetControlTable("DCheckBox")

	function CHECKBOX:Paint(w, h)
		local checked = self:GetChecked()
		local bg = checked and PDCity.THEME.Accent or (self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)

		draw.RoundedBox(3, 0, 0, w, h, bg)
		surface.SetDrawColor(checked and PDCity.THEME.Accent or PDCity.THEME.Border)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		if checked then
			surface.SetDrawColor(PDCity.THEME.Text)
			surface.DrawLine(w * 0.2, h * 0.5, w * 0.42, h * 0.72)
			surface.DrawLine(w * 0.42, h * 0.72, w * 0.8, h * 0.25)
		end
	end
end

-- DermaMenu() (the "DMenu" panel it returns, plus each "DMenuOption" row
-- AddOption creates) - never touched by this theme before, unlike every
-- other control here, which is exactly why a right-click menu or the
-- Flowchart's "+ Add Node" button stood out as a stock white Windows-98
-- popup against everything else already reskinned dark. Paint returns
-- false on the option row (same technique DComboBox above already uses)
-- so the native icon/text/submenu-arrow layout still renders - only the
-- background and text colour actually change.
do
	local MENU = vgui.GetControlTable("DMenu")
	function MENU:Paint(w, h)
		draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Background)
		surface.SetDrawColor(PDCity.THEME.Border)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	local OPTION = vgui.GetControlTable("DMenuOption")
	function OPTION:Paint(w, h)
		draw.RoundedBox(0, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Background)
		return false
	end

	function OPTION:UpdateColours(skin)
		self:SetTextStyleColor(self:IsEnabled() and PDCity.THEME.Text or PDCity.THEME.TextDim)
	end
end

-- DListView: the outer box, each row, each row's text, and each column
-- header all skin independently in stock Derma, so all four get patched.
do
	-- Outer box background (lua/skins/default.lua's SKIN:PaintListView
	-- just draws a white 9-slice - swapped for a plain dark panel).
	local LISTVIEW = vgui.GetControlTable("DListView")
	function LISTVIEW:Paint(w, h)
		draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Panel)
		surface.SetDrawColor(PDCity.THEME.Border)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	-- Each row's background (selected/hovered/alternating).
	local LINE = vgui.GetControlTable("DListView_Line")
	function LINE:Paint(w, h)
		local col
		if self:IsLineSelected() then
			col = PDCity.THEME.AccentDim
		elseif self.Hovered then
			col = PDCity.THEME.PanelHover
		elseif self:GetAltLine() then
			col = PDCity.THEME.Background
		else
			col = PDCity.THEME.Panel
		end
		draw.RoundedBox(0, 0, 0, w, h, col)
	end

	-- Each row's per-column text label (lua/vgui/dlistview_line.lua's
	-- "DListViewLabel" control) - stock UpdateColours picks near-black/
	-- near-white off the skin's Label colours depending on selection;
	-- theme text colour reads fine against every row state above either way.
	local ROWLABEL = vgui.GetControlTable("DListViewLabel")
	function ROWLABEL:UpdateColours(skin)
		self:SetTextStyleColor(PDCity.THEME.Text)
	end

	-- Column headers (lua/vgui/dlistview_column.lua) - each is a plain
	-- DButton (self.Header) built inside DListView_Column's own :Init, so
	-- restyled the same way as DComboBox's drop arrow above: re-point its
	-- Paint once here rather than patching DButton globally (which would
	-- reskin every button on the client, not just these).
	local COLUMN = vgui.GetControlTable("DListView_Column")
	local BaseColumnInit = COLUMN.Init
	local BaseSetName = COLUMN.SetName

	function COLUMN:Init()
		BaseColumnInit(self)

		self.Header.Paint = function(self, w, h)
			draw.RoundedBox(0, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.TitleBar)
			draw.SimpleText(self.PDCityLabel or "", "PDCity_Small", 6, h / 2, PDCity.THEME.TextDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	-- SetName is how AddColumn actually sets the header's text
	-- (lua/vgui/dlistview.lua) - blanking the real text after storing it
	-- separately avoids double-drawing it, same "blank + hand-draw"
	-- approach PDCity.StyleButton already uses for the same underlying
	-- DButton-text-survives-a-Paint-override reason.
	function COLUMN:SetName(strName)
		BaseSetName(self, strName)
		self.Header.PDCityLabel = strName
		self.Header:SetText("")
	end
end

-- Flat Accent alone read as far more "generic blue app" than "Miami" -
-- this is what actually sells the vibe, so it's worth the per-frame cost
-- of a segmented draw (there's no built-in two-colour gradient rect).
-- Segment count is a flat 48 regardless of width - plenty smooth for a
-- 2px-tall strip, and caps the cost on a very wide resized frame.
local function DrawGradientRect(x, y, w, h, colorA, colorB)
	local steps = 48
	local segW = w / steps
	for i = 0, steps - 1 do
		local t = i / (steps - 1)
		surface.SetDrawColor(
			Lerp(t, colorA.r, colorB.r),
			Lerp(t, colorA.g, colorB.g),
			Lerp(t, colorA.b, colorB.b),
			255
		)
		surface.DrawRect(x + i * segW, y, segW + 1, h)
	end
end

--[[---------------------------------------------------------
	"More depth" pass (requested: the flat single-colour fills every
	panel/button used were reading as "robotic"/plain - these two
	helpers are the fix, both centralized here so every menu built on
	this theme picks them up at once rather than needing dozens of
	individual file edits across every tab/card/list this gamemode has.

	PDCity.DrawShadow - a soft drop-shadow behind a panel, faked with
	several progressively larger, more transparent rounded rects (GMod's
	2D draw API has no real blur) offset downward for a consistent
	top-left light source. Used behind every PDCity.CreateModernFrame
	frame below.

	PDCity.DrawRaisedBox - a solid rounded box plus a soft white sheen
	over its top half (itself just a semi-transparent rounded rect, top
	corners only, sized to stay well clear of the outer shape's bottom
	corners so nothing clips oddly) - the standard cheap trick for a
	"raised/glossy" look without true gradient-clipped-to-a-rounded-shape
	rendering, which GMod's draw API doesn't support directly. Used by
	PDCity.StyleButton below; exported for any panel that wants the same
	raised treatment.
-----------------------------------------------------------]]

-- strength (optional, 0-1, default 1) fades the shadow, e.g. for a
-- semi-transparent panel that shouldn't sit on a full-strength shadow.
function PDCity.DrawShadow(x, y, w, h, radius, strength)
	strength = strength or 1
	if strength <= 0 then return end

	for i = 5, 1, -1 do
		local grow = i * 3
		draw.RoundedBox(radius + grow / 2, x - grow / 2, y - grow / 2 + 5, w + grow, h + grow, Color(0, 0, 0, (16 - i * 2) * strength))
	end
end

-- First version of this used a flat semi-transparent rectangle over the
-- top half as a "sheen" - looked like a hard visible seam/band partway
-- down the button instead of a highlight (any flat-alpha overlay with a
-- straight cutoff edge does that - there's no gradient softening the
-- transition). A tight drop shadow plus a single 1px near-white top
-- edge reads as "raised" without that artifact.
function PDCity.DrawRaisedBox(x, y, w, h, radius, baseColor)
	draw.RoundedBox(radius + 1, x - 1, y + 2, w + 2, h + 2, Color(0, 0, 0, 40))
	draw.RoundedBox(radius, x, y, w, h, baseColor)

	surface.SetDrawColor(255, 255, 255, 30)
	surface.DrawRect(x + radius, y + 1, math.max(0, w - radius * 2), 1)
end

--[[---------------------------------------------------------
	Every "themed" font in the gamemode, in one registry - name, size,
	weight. The FAMILY is the only thing that ever changes (owner-picked,
	Site Admin's "Site Theme" tab, cl_site_theme.lua's PDCity.RebuildFonts
	below) - size/weight per font stay fixed, so swapping families
	restyles the whole game's typography in one go without disturbing the
	sizing hierarchy every menu was actually laid out around.

	Used to be one-off surface.CreateFont calls scattered across whichever
	file first needed a given font (cl_character_select.lua's CharLink/
	CharacterName, cl_hud_card.lua's HUDStat/HUDName...) - centralised
	here instead so there's exactly one place that knows about all of
	them, which PDCity.RebuildFonts needs to be able to redo every one on
	a theme change. Every OTHER file just references these by name
	(:SetFont("PDCity_Whatever")) same as before - nothing about how
	they're consumed changed, only where they're declared.

	PDCity_Mono (cl_logviewer.lua) is deliberately NOT here - a log/code
	viewer needs a real monospaced font regardless of whatever family the
	owner's picked for the rest of the UI, so it keeps its own dedicated
	surface.CreateFont call untouched by retheming.
-----------------------------------------------------------]]
local FONT_SPECS = {
	{ Name = "PDCity_Title",           Size = 22, Weight = 700 },
	{ Name = "PDCity_Heading",         Size = 17, Weight = 600 },
	{ Name = "PDCity_Body",            Size = 15, Weight = 400 },
	{ Name = "PDCity_Small",           Size = 13, Weight = 400 },
	-- Bold + slightly larger than PDCity_Small, for anything that needs
	-- to stand out on a row rather than blend in with its label text -
	-- right now just the F4 shop's price tags (cl_f4_menu.lua).
	{ Name = "PDCity_PriceTag",        Size = 15, Weight = 800 },
	-- Server branding (the logo placeholder + server name text,
	-- cl_character_select.lua's header strip and cl_hud_card.lua's HUD
	-- card) - heavier weight and a couple sizes bigger so the server's
	-- own name actually reads as a wordmark/logotype wherever it shows.
	{ Name = "PDCity_Brand",           Size = 24, Weight = 900 },
	-- Bold text links (Select/Edit) on the character select screen, two
	-- sizes since GMod fonts are fixed-size - swapped based on
	-- :IsHovered() for the "gets slightly bigger" effect.
	{ Name = "PDCity_CharLink",        Size = 20, Weight = 800 },
	{ Name = "PDCity_CharLinkBig",     Size = 23, Weight = 800 },
	-- The name above each character's head on the select screen.
	{ Name = "PDCity_CharacterName",   Size = 26, Weight = 800 },
	-- (The HUD card builds its own owner-sizeable fonts - cl_hud_card.lua.)
}

-- The family the Site Theme picked - kept even while readable mode
-- (cl_accessibility.lua) swaps it out, so turning that off restores it.
PDCity.FONT_FAMILY = PDCity.FONT_FAMILY or "Roboto"

local function BuildFonts(family)
	PDCity.FONT_FAMILY = family

	local scale = 1
	if PDCity.IsReadableMode and PDCity.IsReadableMode() then
		family = PDCity.READABLE_FONT
		scale = PDCity.READABLE_TEXT_SCALE
	end

	for _, spec in ipairs(FONT_SPECS) do
		surface.CreateFont(spec.Name, {
			font = family,
			size = math.Round(spec.Size * scale),
			weight = spec.Weight,
			antialias = true,
		})
	end
end

-- Global (not local) - cl_site_theme.lua calls this again with the
-- owner's chosen family whenever the site theme syncs/changes, and the
-- Site Theme editor calls it for a live preview while picking one.
PDCity.RebuildFonts = BuildFonts

BuildFonts("Roboto") -- built-in default, overridden by cl_site_theme.lua's sync if the owner's set something else

--[[---------------------------------------------------------
	Restyles a stock DButton to match the theme - flat rounded rect,
	accent-colored, hover/press feedback - instead of Derma's own default
	skin (grey gradient bevel), which every admin-editor button was still
	using despite everything around it being hand-themed.

	Stock DButton text doesn't survive a Paint override intact (the
	background and label are the same draw call), so this blanks the
	button's own text and draws `label` by hand instead - same technique
	already used for the F4 shop's price tags/badges.

	opts.Accent/opts.AccentDim pick the color pair (defaults to the
	theme's own Accent/AccentDim) - pass PDCity.THEME.Panel/PanelHover
	for a secondary/quiet button (Cancel, Remove) instead of a primary
	one (Add, Save, Confirm).
-----------------------------------------------------------]]
function PDCity.StyleButton(btn, label, opts)
	opts = opts or {}
	local accent = opts.Accent or PDCity.THEME.Accent
	local accentDim = opts.AccentDim or PDCity.THEME.AccentDim
	local textColor = opts.TextColor or PDCity.THEME.Text

	btn:SetText("")
	btn.Paint = function(self, w, h)
		if not self:IsEnabled() then
			draw.RoundedBox(5, 0, 0, w, h, PDCity.THEME.Border)
			draw.SimpleText(label, "PDCity_Small", w / 2, h / 2, PDCity.THEME.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end

		local col = self:IsDown() and accentDim or (self:IsHovered() and accent or accentDim)
		PDCity.DrawRaisedBox(0, 0, w, h, 5, col)
		draw.SimpleText(label, "PDCity_Small", w / 2, h / 2, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

--[[---------------------------------------------------------
	Creates a borderless DFrame with a custom dark header, accent
	underline, close button, and a short fade-in - the base every
	PD City menu builds on so they share one look.

	Resizable (drag any edge/corner) down to a sensible minimum, not
	just a fixed size - the close button repositions itself on every
	resize regardless of caller. Callers with their own absolutely-
	positioned children (a sidebar/content split, in every menu built on
	this so far) need to reflow those too, which THIS constructor can't
	know how to do generically - pass `onResize(w, h)` and it's called
	on every resize, after the close button's own reposition, wired
	through Panel:OnSizeChanged (fires on every size change, drag-resize
	included, distinct from PerformLayout which is about children DFrame
	itself manages internally).
-----------------------------------------------------------]]
local MIN_FRAME_WIDE = 560
local MIN_FRAME_TALL = 360

-- Sizes a "browse a bunch of content" menu (F1, F4, Whitelist, F4 Admin,
-- Staff Menu) as a fraction of the CURRENT screen instead of a fixed pixel
-- size, so it actually uses the extra space on a big/high-res monitor
-- instead of sitting tiny in the middle of it - recomputed fresh every
-- time the menu is opened, so it's always responsive to whatever
-- resolution the client happens to be running right now. Capped at
-- maxW/maxH so it doesn't get absurdly large on an ultrawide/4K screen;
-- PDCity.CreateModernFrame's own clamp below still guards the other
-- direction (never below MIN_FRAME_WIDE/TALL) regardless of what this
-- returns. Small utility dialogs (confirm/warrant/bail/arrest/...) stay on
-- fixed sizes on purpose - blowing those up to 80% of a 4K screen would
-- look ridiculous for a two-button popup.
function PDCity.ResponsiveFrameSize(maxW, maxH, fraction)
	fraction = fraction or 0.8
	return math.min(maxW, ScrW() * fraction), math.min(maxH, ScrH() * fraction)
end

function PDCity.CreateModernFrame(title, w, h, onResize)

	-- Callers pass a fixed "ideal" size (e.g. F4's 880x560), which can be
	-- taller/wider than the actual screen on a short monitor, a laptop
	-- panel, or a resized window - DFrame:Center() doesn't clamp position
	-- to keep the whole frame on-screen, so an oversized frame ends up
	-- with its bottom (where fixed-position content like the job detail
	-- panel's Become button lives) pushed off the visible desktop
	-- entirely. Clamp to what actually fits, with a margin, same floor
	-- as the resize minimums so it's never smaller than those either.
	w = math.Clamp(w, MIN_FRAME_WIDE, math.max(MIN_FRAME_WIDE, ScrW() - 40))
	h = math.Clamp(h, MIN_FRAME_TALL, math.max(MIN_FRAME_TALL, ScrH() - 40))

	local frame = vgui.Create("DFrame")
	frame:SetSize(w, h)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(true)
	-- Not resizable - size is fully automatic (PDCity.ResponsiveFrameSize,
	-- clamped above to fit the screen), so there's nothing for a manual
	-- resize to do except let the frame get dragged too big/small or
	-- squish content out of view again.
	frame:SetSizable(false)
	frame:MakePopup()
	frame:SetAlpha(0)
	-- Fades the FRAME's own alpha in to fully opaque (255) - deliberately
	-- not the 90%-opacity mechanism (that's baked into PDCity.THEME's own
	-- colours below instead). Panel:SetAlpha's multiplier resets back to
	-- each CHILD panel's own GetAlpha() (255 by default) before that
	-- child's Paint runs, rather than compounding with its parent's - so
	-- setting it here alone only ever affected this frame's own direct
	-- Paint (background/titlebar/logo/title), never the sidebar/content/
	-- cards drawn by child panels, which is why that didn't show through.
	frame:AlphaTo(255, 0.15, 0)

	frame.Paint = function(self, panelW, panelH)
		PDCity.DrawShadow(0, 0, panelW, panelH, 8)
		draw.RoundedBox(8, 0, 0, panelW, panelH, PDCity.THEME.Background)
		draw.RoundedBoxEx(8, 0, 0, panelW, 46, PDCity.THEME.TitleBar, true, true, false, false)
		DrawGradientRect(0, 46, panelW, 2, PDCity.THEME.Accent, PDCity.THEME.Accent2)

		local titleX = 18
		if not PDCity.LOGO_MAT:IsError() then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(PDCity.LOGO_MAT)
			surface.DrawTexturedRect(18, 7, 32, 32)
			titleX = 58
		end

		draw.SimpleText(title, "PDCity_Title", titleX, 23, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local closeBtn = vgui.Create("DButton", frame)
	closeBtn:SetText("")
	closeBtn:SetSize(32, 32)
	closeBtn:SetPos(w - 42, 7)
	closeBtn.Paint = function(self, btnW, btnH)
		if self:IsHovered() then
			draw.RoundedBox(4, 0, 0, btnW, btnH, PDCity.THEME.Panel)
		end
		local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.TextDim
		draw.SimpleText("✕", "PDCity_Body", btnW / 2, btnH / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	closeBtn.DoClick = function() frame:Close() end

	-- Overriding the frame's own :Close(), not just this button's DoClick -
	-- stock DFrame:Close() only hides the panel (SetVisible(false)) and
	-- fires OnClose, it never actually removes it. Every caller's
	-- brightness/sound-dampening restore (cl_menu_dim.lua) is wired to
	-- OnRemove, which never fired through that path - a menu closed this
	-- way (the X button here, but also e.g. the F4 job detail panel's own
	-- Become button, which calls frame:Close() directly) hid but stayed
	-- alive, so the screen stayed dim until the NEXT F1/F4 press found the
	-- stale hidden frame and removed THAT instead of opening a new one.
	-- OnClose is still honoured first (the F4 admin editor's hook.Remove
	-- cleanup depends on it), then the panel is actually removed either way.
	frame.Close = function(self)
		if self.OnClose then self:OnClose() end
		self:Remove()
	end

	frame.OnSizeChanged = function(self, newW, newH)
		closeBtn:SetPos(newW - 42, 7)
		if onResize then onResize(newW, newH) end
	end

	return frame

end

--[[---------------------------------------------------------
	Which key an engine binding is actually sitting on right now -
	"gm_showhelp" is F1 and "gm_showspare2" is F4 on a default setup, but
	either can be rebound, so neither is hardcoded.

	Needed because a menu opened by one of those bindings can't be closed
	by pressing the same key again through the binding itself: the moment
	a panel is :MakePopup()'d with keyboard input on, the engine routes
	keystrokes into VGUI instead of running console binds, so the
	concommand that opened the menu never fires a second time and the
	"press F1 again to close" toggle inside it is never reached. Each menu
	therefore has to notice the keypress itself, from its own
	OnKeyCodePressed - the same reason they all handle Escape by hand
	rather than relying on the engine to close them.
-----------------------------------------------------------]]
function PDCity.BoundKey(binding, fallback)
	local name = input.LookupBinding(binding)
	if not name then return fallback end

	local code = input.GetKeyCode(name)
	if not code or code == KEY_NONE then return fallback end

	return code
end

--[[---------------------------------------------------------
	Pins a "picker" popup (entity/weapon class, player model, interface,
	the Developer Console's Find Entity lookup, ...) in front of whatever
	menu opened it, and stops it being dragged out of position - reported
	as these grids being able to end up hidden behind the menu that opened
	them (a stray click on the menu behind brings IT back to front) with
	no obvious way back except closing and reopening the picker itself.

	MoveToFront every Think, not just once on creation - a single
	MoveToFront when the picker opens doesn't survive the parent menu
	later being clicked (which brings IT back to front instead), so this
	re-asserts every frame instead. Purely a z-order push - unlike
	MakePopup, it doesn't touch keyboard focus, so it's safe to call
	constantly without fighting whatever child (a filter DTextEntry...)
	the player's actually typing into.

	Every picker calls this once, right after creating its own frame via
	PDCity.CreateModernFrame above - not baked into that function itself,
	since most menus built on it (F1, F4, the Flowchart editor...) are
	meant to behave like normal, independently-movable windows, not a
	locked-in-place picker.
-----------------------------------------------------------]]
function PDCity.LockFrameOnTop(frame)
	frame:SetDraggable(false)
	frame.Think = function(self)
		self:MoveToFront()
	end
end

--[[---------------------------------------------------------
	Pickers (icon, colour, model, weapon, entity class...) open INSIDE
	whichever F1 admin page is showing (Site Admin, Catalogue, Developer
	Console) as a side panel over the right of its content area, instead of
	a separate pop-out window. Pages opt in with PDCity.RegisterPickerHost.
	With no host on screen (e.g. opened from the Flowchart editor's own
	window) it falls back to the old locked-on-top pop-out.

	PDCity.OpenPicker(title, w, h) returns a panel of size w x h with a 48px
	title bar - the same shape and :Close() as PDCity.CreateModernFrame, so
	a picker lays out its contents exactly as it did inside a frame.
-----------------------------------------------------------]]
local pickerHosts = {}

function PDCity.RegisterPickerHost(anchor)
	table.insert(pickerHosts, anchor)
end

local function FindPickerHost()
	for i = #pickerHosts, 1, -1 do
		local host = pickerHosts[i]
		if not IsValid(host) then
			table.remove(pickerHosts, i)
		elseif PDCity.IsShownOnScreen(host) then
			return host
		end
	end
end

function PDCity.ClosePicker(host)
	if IsValid(host) and IsValid(host.PDCityPicker) then host.PDCityPicker:Remove() end
end

function PDCity.OpenPicker(title, w, h)
	local host = FindPickerHost()

	if not host then
		PDCity.PushMenuDim()
		local frame = PDCity.CreateModernFrame(title, w, h)
		PDCity.LockFrameOnTop(frame)

		-- A child's OnRemove, so the picker is still free to set the
		-- frame's own OnRemove without unbalancing the dim.
		local dimGuard = vgui.Create("Panel", frame)
		dimGuard:SetSize(0, 0)
		dimGuard.OnRemove = function() PDCity.PopMenuDim() end

		return frame
	end

	PDCity.ClosePicker(host)

	local card = vgui.Create("DPanel", host)
	card:SetSize(w, h)
	host.PDCityPicker = card

	card.Paint = function(self, cw, ch)
		draw.RoundedBox(8, 0, 0, cw, ch, PDCity.THEME.Background)
		draw.RoundedBoxEx(8, 0, 0, cw, 46, PDCity.THEME.TitleBar, true, true, false, false)
		DrawGradientRect(0, 46, cw, 2, PDCity.THEME.Accent, PDCity.THEME.Accent2)
		draw.SimpleText(title, "PDCity_Heading", 16, 23, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	-- Pinned to the host's top-right, shrinking to fit a short page.
	card.Think = function(self)
		self:SetPos(host:GetWide() - w - 8, 8)
		self:SetTall(math.min(h, host:GetTall() - 16))
	end
	card:Think()

	local closeBtn = vgui.Create("DButton", card)
	closeBtn:SetText("")
	closeBtn:SetSize(32, 32)
	closeBtn:SetPos(w - 42, 7)
	closeBtn.Paint = function(self, btnW, btnH)
		if self:IsHovered() then draw.RoundedBox(4, 0, 0, btnW, btnH, PDCity.THEME.Panel) end
		local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.TextDim
		draw.SimpleText("✕", "PDCity_Body", btnW / 2, btnH / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	closeBtn.DoClick = function() card:Close() end

	card.Close = function(self)
		if self.OnClose then self:OnClose() end
		self:Remove()
	end

	card:MoveToFront()
	return card
end

--[[---------------------------------------------------------
	Icon picker - a curated grid of GMod's bundled silk icons (materials/
	icon16/, confirmed present via vpk.exe against garrysmod_dir.vpk) plus
	a text entry for a pasted http(s) image URL, resolved the same way
	either way by PDCity.GetIconMaterial above. Shared, global version of
	the picker the Jobs tab (cl_f4_admin.lua's BuildJobsTab) originally
	built inline for itself - new "pick an icon" fields (Currencies, the
	HUD editor's health/armor icon override, ...) call this instead of
	each growing their own copy of the same grid.
-----------------------------------------------------------]]
local ICON16_CHOICES = {
	"icon16/car.png", "icon16/car_add.png", "icon16/shield.png", "icon16/shield_add.png",
	"icon16/gun.png", "icon16/key.png", "icon16/lock.png", "icon16/lock_open.png",
	"icon16/money.png", "icon16/coins.png", "icon16/cog.png", "icon16/wrench.png",
	"icon16/wrench_orange.png", "icon16/medal_gold_1.png", "icon16/award_star_gold_3.png", "icon16/house.png",
	"icon16/briefcase.png", "icon16/group.png", "icon16/user.png", "icon16/star.png",
	"icon16/flag_red.png", "icon16/fire.png", "icon16/pill.png", "icon16/table.png",
	"icon16/heart.png", "icon16/vcard.png", "icon16/box.png", "icon16/basket.png",
	"icon16/chart_bar.png", "icon16/clock.png", "icon16/eye.png", "icon16/find.png",
	"icon16/flag_blue.png", "icon16/flag_green.png", "icon16/gem.png", "icon16/heart_add.png",
}

function PDCity.OpenIconPicker(onPick)

	local frame = PDCity.OpenPicker("Choose an Icon", 380, 420)

	local top = 48

	local urlEntry = vgui.Create("DTextEntry", frame)
	urlEntry:SetPos(16, top + 10)
	urlEntry:SetSize(268, 26)
	urlEntry:SetPlaceholderText("...or paste an image URL")

	local urlBtn = vgui.Create("DButton", frame)
	urlBtn:SetPos(292, top + 10)
	PDCity.StyleButton(urlBtn, "Use")
	urlBtn:SetSize(72, 26)
	urlBtn.DoClick = function()
		local val = string.Trim(urlEntry:GetValue() or "")
		if val == "" then return end
		onPick(val)
		frame:Close()
	end

	local grid = vgui.Create("DScrollPanel", frame)
	grid:SetPos(16, top + 46)
	grid:SetSize(348, frame:GetTall() - top - 62)
	PDCity.ApplyFastScroll(grid)

	local layout = vgui.Create("DIconLayout", grid)
	layout:Dock(TOP)
	layout:SetSpaceX(4)
	layout:SetSpaceY(4)

	for _, path in ipairs(ICON16_CHOICES) do
		local mat = Material(path)
		local btn = vgui.Create("DButton", layout)
		btn:SetSize(48, 48)
		btn:SetText("")
		btn.Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(mat)
			surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
		end
		btn.DoClick = function()
			onPick(path)
			frame:Close()
		end
	end

end

-- Stock DScrollPanel's wheel-scroll increment is tiny relative to how
-- tall these card/row grids get across every menu built on this theme -
-- reported as "scrolling is really slow" on the F4 menu, true of any
-- similarly long list. SetScroll'ing the bar directly by a fixed pixel
-- amount per notch sidesteps whatever the default per-notch increment
-- is, rather than trying to tune it.
local FAST_SCROLL_PIXELS = 120

function PDCity.ApplyFastScroll(scroll)
	scroll.OnMouseWheeled = function(self, delta)
		local bar = self:GetVBar()
		bar:SetScroll(bar:GetScroll() - delta * FAST_SCROLL_PIXELS)
		return true
	end
end

--[[---------------------------------------------------------
	Every DComboBox's open list is its own top-level popup, placed once at
	the box's screen position - scrolling the panel behind it moved the
	box but left the list floating where it opened. Patched once here for
	every dropdown in the gamemode: while open, the list follows its box,
	and closes if the box is removed, hidden, or scrolled out of view.
	Clicking an option or anywhere else still closes it as normal.
-----------------------------------------------------------]]
function PDCity.IsShownOnScreen(panel)
	local x, y = panel:LocalToScreen(0, 0)
	local w, h = panel:GetSize()

	local current = panel
	while IsValid(current) do
		if not current:IsVisible() then return false end

		local parent = current:GetParent()
		if not IsValid(parent) then break end

		-- Must overlap every ancestor, or it's been scrolled/clipped away.
		local px, py = parent:LocalToScreen(0, 0)
		local pw, ph = parent:GetSize()
		if x + w <= px or x >= px + pw or y + h <= py or y >= py + ph then return false end

		current = parent
	end

	return true
end

local comboTable = vgui.GetControlTable("DComboBox")
if comboTable and not comboTable.PDCityFollowPatched then
	comboTable.PDCityFollowPatched = true

	local baseOpenMenu = comboTable.OpenMenu
	comboTable.OpenMenu = function(self, ...)
		baseOpenMenu(self, ...)

		local menu = self.Menu
		if not IsValid(menu) then return end

		-- Kept as an offset rather than recomputed from scratch, so a list
		-- DMenu flipped above the box (no room below) stays flipped.
		local boxX, boxY = self:LocalToScreen(0, 0)
		local menuX, menuY = menu:GetPos()
		local offsetX, offsetY = menuX - boxX, menuY - boxY

		local combo = self
		local baseThink = menu.Think
		menu.Think = function(m, ...)
			if baseThink then baseThink(m, ...) end

			if not IsValid(combo) or not PDCity.IsShownOnScreen(combo) then
				if IsValid(combo) then combo:CloseMenu() else m:Remove() end
				return
			end

			local x, y = combo:LocalToScreen(0, 0)
			m:SetPos(x + offsetX, y + offsetY)
		end
	end
end

--[[---------------------------------------------------------
	Owner admin page shown inside the F1 menu (Site Admin, Catalogue):
	a titled tab list on the left, the selected tab's editor on the right,
	the output console (cl_toast.lua) below it. Pickers open inside the
	editor area (PDCity.OpenPicker, above).

	tabs: { { Name = "...", Build = function(parent) return panel end }, ... }
	onSelect(index), optional, runs after each tab switch.

	Returns root, sidebar, and the y just below the last tab button (for
	anything extra the caller adds to the sidebar). root.PDCityRefreshAll()
	calls every tab's own PDCityRefresh.
-----------------------------------------------------------]]
local ADMIN_NAV_W = 180

function PDCity.BuildAdminPage(parent, title, tabs, onSelect)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root:DockMargin(24, 18, 24, 18)
	root.Paint = function() end

	local sidebar = vgui.Create("DPanel", root)
	sidebar:Dock(LEFT)
	sidebar:SetWide(ADMIN_NAV_W)
	sidebar.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel)
	end

	local heading = vgui.Create("DLabel", sidebar)
	heading:SetPos(16, 12)
	heading:SetSize(ADMIN_NAV_W - 32, 24)
	heading:SetFont("PDCity_Heading")
	heading:SetText(title)
	heading:SetTextColor(PDCity.THEME.Text)

	-- Before content: a BOTTOM dock must come before the FILL one.
	local console = PDCity.BuildMessageConsole(root)
	console:DockMargin(16, 12, 0, 0)

	local content = vgui.Create("DPanel", root)
	content:Dock(FILL)
	content:DockMargin(16, 0, 0, 0)
	content:DockPadding(16, 16, 16, 16)
	content.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel)
	end

	PDCity.RegisterPickerHost(content)

	local panels = {}
	local tabButtons = {}
	local y = 48

	local function SelectTab(index)
		PDCity.ClosePicker(content) -- an open picker belongs to the tab being left
		for i, btn in ipairs(tabButtons) do btn:SetActive(i == index) end
		for i, panel in ipairs(panels) do panel:SetVisible(i == index) end
		if onSelect then onSelect(index) end
	end

	for i, tab in ipairs(tabs) do
		local panel = tab.Build(content)
		panel:SetVisible(false)
		panels[i] = panel

		local btn = vgui.Create("PDCitySidebarTab", sidebar)
		btn:SetLabel(tab.Name)
		btn:SetPos(8, y)
		btn:SetSize(ADMIN_NAV_W - 16, 34)
		btn.DoClick = function() SelectTab(i) end
		tabButtons[i] = btn

		y = y + 38
	end

	SelectTab(1)

	root.PDCityRefreshAll = function()
		for _, panel in ipairs(panels) do
			if IsValid(panel) and panel.PDCityRefresh then panel.PDCityRefresh() end
		end
	end

	return root, sidebar, y

end

--[[---------------------------------------------------------
	A thin drag handle between two panels stacked vertically, so a fixed
	pixel split baked into a tab's layout (e.g. the Inventory Items tab's
	search-list-over-allowed-list) can be resized by hand instead -
	requested as "drag to make the top bigger and bottom smaller".

	panelA/panelB are plain child panels of `parent` with NO Dock of
	their own - this owns their position/size entirely, called fresh on
	every reflow (a drag tick, and the caller's own PerformLayout) so it
	never goes stale relative to parent's actual current size.

	`splitState` is a plain {Top = pixels} table (Top optional - left out,
	it starts at DefaultFrac, default 0.6, of the height) the CALLER creates and
	keeps alive for as long as `parent` exists (a tab-local, typically) -
	passing a fresh table on every call would forget the resize the
	moment anything else rebuilds the tab. Returns `Reflow(w, h)` for the
	caller to invoke from its own PerformLayout.
-----------------------------------------------------------]]
local SPLIT_HANDLE_TALL = 9
local SPLIT_MIN = 60

function PDCity.MakeSplitter(parent, panelA, panelB, splitState)
	-- No saved Top yet: start the split at DEFAULT_FRAC of the real height
	-- on the first layout pass that has one, rather than a fixed pixel value
	-- that leaves the top pane cramped on a full-screen menu.
	local DEFAULT_FRAC = splitState.DefaultFrac or 0.6

	local handle = vgui.Create("DPanel", parent)
	handle:SetCursor("sizens")
	handle.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.TitleBar)
		surface.SetDrawColor(PDCity.THEME.Border)
		local cx, cy = w / 2, h / 2
		for i = -1, 1 do
			surface.DrawRect(cx + i * 7 - 1, cy - 1, 3, 2)
		end
	end

	local function Reflow(w, h)
		if not splitState.Top then
			if h < SPLIT_MIN * 2 + SPLIT_HANDLE_TALL then return end
			splitState.Top = math.floor(h * DEFAULT_FRAC)
		end
		local top = math.Clamp(splitState.Top, SPLIT_MIN, math.max(SPLIT_MIN, h - SPLIT_MIN - SPLIT_HANDLE_TALL))
		splitState.Top = top

		panelA:SetPos(0, 0)
		panelA:SetSize(w, top)
		handle:SetPos(0, top)
		handle:SetSize(w, SPLIT_HANDLE_TALL)
		panelB:SetPos(0, top + SPLIT_HANDLE_TALL)
		panelB:SetSize(w, math.max(SPLIT_MIN, h - top - SPLIT_HANDLE_TALL))
	end

	handle.OnMousePressed = function(self, mcode)
		if mcode ~= MOUSE_LEFT or not splitState.Top then return end
		self.pdcity_Dragging = true
		self.pdcity_StartMouseY = gui.MouseY()
		self.pdcity_StartTop = splitState.Top
		self:MouseCapture(true)
	end

	handle.OnMouseReleased = function(self, mcode)
		self.pdcity_Dragging = false
		self:MouseCapture(false)
	end

	handle.Think = function(self)
		if not self.pdcity_Dragging then return end
		splitState.Top = self.pdcity_StartTop + (gui.MouseY() - self.pdcity_StartMouseY)
		Reflow(parent:GetWide(), parent:GetTall())
	end

	return Reflow
end

-- Shared by every row-card/detail-panel portrait across every menu built
-- on this theme (originally the F4 job cards and job detail panel, now
-- also the Staff Menu's player rows) - same head-and-shoulders framing
-- logic either way, just at a different size. `parent` must already
-- have a real, immediately-known size (an explicit SetSize/SetTall, not
-- a Dock auto-stretch that only resolves next layout pass) - a Dock(LEFT)
-- holder with no explicit SetTall parented a DModelPanel here into a
-- still-zero-height panel that never picked up a real size afterwards,
-- which is what first surfaced this requirement (rendered as an empty
-- portrait).
-- A job with no Models of its own (core/sh_jobs.lua - it just keeps
-- whatever model the character already had, player_class/player_sandbox.lua's
-- PLAYER:SetModel) has nothing job-specific to preview - falls back to
-- the local player's OWN current model instead of leaving the card
-- blank, since that's genuinely what picking this job would leave them
-- looking like. Both F4 job cards (cl_f4_menu.lua's grid card and detail
-- panel) call this rather than duplicating the fallback themselves.
function PDCity.GetJobPortraitModel(job)
	if job and job.Models and job.Models[1] then return job.Models[1] end
	local ply = LocalPlayer()
	return IsValid(ply) and ply:GetModel() or nil
end

function PDCity.BuildPortrait(parent, model)
	if not model then return end

	-- Deliberately NOT overriding Paint here (used to, to draw a themed
	-- background behind the model via self:PaintModel()) - that method
	-- turned out not to be safely callable this way on this server
	-- ("attempt to call method 'PaintModel' (a nil value)"), throwing on
	-- every single paint and leaving the portrait blank. The containing
	-- holder panel already paints a themed background underneath this,
	-- so stock DModelPanel rendering on top is enough.
	local portrait = vgui.Create("DModelPanel", parent)
	portrait:Dock(FILL)
	portrait:DockMargin(1, 1, 1, 1)
	portrait:SetModel(model)
	portrait:SetMouseInputEnabled(false)

	local ent = portrait:GetEntity()
	if IsValid(ent) then
		local mn, mx = ent:GetRenderBounds()
		local height = mx.z - mn.z

		-- Weighted toward the top of the head rather than the midpoint
		-- between head and shoulders - aiming at the midpoint left a
		-- visible gap of empty space above the head; this framing has
		-- already been through three rounds of user-screenshot feedback
		-- to land here.
		local headTop = mx.z - height * 0.03
		local shoulders = mx.z - height * 0.32
		local midZ = headTop - (headTop - shoulders) * 0.3

		portrait:SetFOV(28)
		portrait:SetCamPos(Vector(height * 0.6, 0, midZ + height * 0.02))
		portrait:SetLookAt(Vector(0, 0, midZ))
	end

	-- Stock DModelPanel slowly auto-rotates the model in LayoutEntity -
	-- fine for one preview, distracting across a whole grid of them all
	-- spinning independently, so this holds it still instead.
	portrait.LayoutEntity = function() end

	return portrait
end

--[[---------------------------------------------------------
	A left-hand sidebar tab button used by the F1 menu. Handles its
	own hover/active lerp so callers just toggle :SetActive(bool).
-----------------------------------------------------------]]
local SIDEBAR_TAB = {}

function SIDEBAR_TAB:Init()
	self.HoverAlpha = 0
	self.Active = false
	-- The underlying DButton must never hold text of its own: it paints
	-- its engine-side label on top of whatever Paint draws, which shows
	-- as doubled/overlapping text. Callers use SetLabel instead.
	self:SetText("")
end

function SIDEBAR_TAB:SetLabel(text)
	self.LabelText = text
end

function SIDEBAR_TAB:SetActive(active)
	self.Active = active
end

function SIDEBAR_TAB:SetIcon(path)
	local mat = path and Material(path) or nil

	-- Falls back to no icon (just the label, same as never calling
	-- SetIcon) rather than drawing the material at all - unguarded, a
	-- failed load draws the engine's own checkerboard "unknown texture"
	-- placeholder, not nothing. Same per-path session caching caveat as
	-- the logo (cl_theme.lua's own PDCity.LOGO_MAT check): if this prints,
	-- fixing the file alone won't clear a failure already cached this
	-- session - needs a full client restart, not just a reconnect.
	if mat and mat:IsError() then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Sidebar icon failed to load: " .. path .. " - check the file exists there and try fully restarting your GMod client (not just reconnecting).\n")
		mat = nil
	end

	self.IconMat = mat
end

function SIDEBAR_TAB:Think()
	local target = (self:IsHovered() or self.Active) and 1 or 0
	self.HoverAlpha = Lerp(FrameTime() * 8, self.HoverAlpha, target)
end

function SIDEBAR_TAB:Paint(w, h)
	if self.Active then
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
		surface.SetDrawColor(PDCity.THEME.Accent)
		surface.DrawRect(0, 6, 3, h - 12)
	elseif self.HoverAlpha > 0.01 then
		draw.RoundedBox(6, 0, 0, w, h, ColorAlpha(PDCity.THEME.Panel, 255 * self.HoverAlpha * 0.6))
	end

	local col = self.Active and PDCity.THEME.Text or PDCity.THEME.TextDim
	local textX = 16

	if self.IconMat then
		surface.SetDrawColor(col.r, col.g, col.b, 255)
		surface.SetMaterial(self.IconMat)
		surface.DrawTexturedRect(16, h / 2 - 8, 16, 16)
		textX = 40
	end

	draw.SimpleText(self.LabelText or "", "PDCity_Body", textX, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("PDCitySidebarTab", SIDEBAR_TAB, "DButton")
