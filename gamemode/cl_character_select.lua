--[[---------------------------------------------------------
	Character Selection tab content - used by cl_f1_menu.lua's single
	full-screen dashboard (PDCity.OpenF1Menu) both as the mandatory join
	screen (server pushes fresh data unprompted right after
	PlayerInitialSpawn, core/sv_characters.lua) and as an ordinary F1 tab
	during normal play (starts empty with a "Switch Character" button,
	since nothing pushed it data yet - clicking it asks the server via
	"pdcity_request_character_screen").

	This file used to build its OWN separate full-screen frame - it's now
	just the tab's CONTENT (PDCity.BuildCharacterSelectTab) plus the one
	net receiver that decides whether to open a fresh mandatory dashboard
	or just refresh an already-open one's Character Selection tab in place.
-----------------------------------------------------------]]

-- PDCity_CharLink/CharLinkBig (bold yellow Select/Edit text links, two
-- sizes since GMod fonts are fixed-size - swapped based on :IsHovered()
-- for the "gets slightly bigger" effect) and PDCity_CharacterName (the
-- name above each character's head) are all defined centrally now, in
-- cl_theme.lua's FONT_SPECS - so PDCity.RebuildFonts (Site Admin's "Site
-- Theme" tab, cl_site_theme.lua) can re-create every themed font across
-- every file with one owner-picked family, rather than each file that
-- wants a themed font owning its own surface.CreateFont call.

local LINK_COLOR = Color(255, 205, 55)
local LINK_COLOR_DISABLED = Color(120, 108, 70)

local function StyleTextLink(btn, label)
	btn:SetText("")
	btn.Paint = function(self, w, h)
		local enabled = self:IsEnabled()
		local hovered = enabled and self:IsHovered()
		local font = hovered and "PDCity_CharLinkBig" or "PDCity_CharLink"
		local col = enabled and LINK_COLOR or LINK_COLOR_DISABLED

		surface.SetFont(font)
		local tw, th = surface.GetTextSize(label)

		draw.SimpleText(label, font, w / 2, h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		if hovered then
			surface.SetDrawColor(col)
			surface.DrawRect(w / 2 - tw / 2, h / 2 + th / 2 - 1, tw, 2)
		end
	end
end

-- Synced from the server (core/sv_character_models.lua) on join and
-- whenever Site Admin's "Character Models" tab saves - the default list
-- everyone can pick from, plus a per-SteamID whitelist of extras. This
-- is only client-side UX filtering; the server re-validates every
-- choice against the same config regardless (core/sv_characters.lua's
-- IsChoosableModel).
net.Receive("pdcity_character_models_sync", function()
	PDCity.CHARACTER_MODEL_CONFIG = util.JSONToTable(net.ReadString() or "{}") or { Models = {}, Whitelist = {} }
end)

local function GetAllowedCharacterModels()
	local cfg = PDCity.CHARACTER_MODEL_CONFIG or { Models = {}, Whitelist = {} }
	local out = table.Copy(cfg.Models or {})

	local extra = cfg.Whitelist and cfg.Whitelist[LocalPlayer():SteamID()]
	if istable(extra) then
		for _, model in ipairs(extra) do
			if not table.HasValue(out, model) then table.insert(out, model) end
		end
	end

	return out
end

--[[---------------------------------------------------------
	Live 3D preview for a character's flashcard - a relaxed idle pose,
	not a static icon. Every stock citizen player model already ships
	with a stock library of animation sequences (idle variants, gestures,
	etc.) since they all share HL2's standard skeleton, so this needs no
	extra content at all - just picking one of those sequences via
	LookupSequence/ResetSequence. Falls through the list quietly (tries
	the next name) if a given model doesn't happen to have that one;
	worst case it just keeps whatever its default reference pose is.

	Locked front-facing, same reasoning PDCity.BuildPortrait (cl_theme.lua)
	already uses for the same purpose - LayoutEntity is stock DModelPanel's
	slow auto-rotate, overridden to a no-op here, with a fixed camera
	position/LookAt set once instead (same +X-axis framing convention
	PDCity.BuildPortrait uses, just pulled back further to fit more of
	the body instead of a tight head shot).
-----------------------------------------------------------]]
-- Tried in order, first match wins - a "thumbs up" gesture isn't a
-- guaranteed standard name the way the plain idles are (naming varies
-- more for gestures across different citizen model sets), so this
-- tries the plausible names first and quietly falls through to a
-- relaxed idle if none of them exist on a given model rather than
-- erroring or leaving it in its raw reference pose.
local POSE_SEQUENCES = {
	"gesture_thumbs_up", "thumbsup", "gesture_yes",
	"idle_all_01", "idle_unarmed_01", "idle_calm_all_01", "Idle",
}

local function BuildCharacterPreview(parent, model, w, h)
	local panel = vgui.Create("DModelPanel", parent)
	panel:SetSize(w, h)
	panel:SetModel(model)
	panel:SetMouseInputEnabled(false)

	-- The black box isn't a derma skin background - checked stock
	-- DModelPanel's actual source (lua/vgui/dmodelpanel.lua): its Paint
	-- IS the whole 3D render (cam.Start3D/DrawModel/cam.End3D), no
	-- separate backdrop call, and no colour clear anywhere in that path
	-- - only render.ClearDepth. Overriding Paint outright (tried first)
	-- skips the model along with it, since they're the same call. Since
	-- there's no colour clear, whatever's drawn immediately BEFORE the
	-- real Paint in the same pass survives in the areas the model
	-- doesn't cover - so wrap the original instead of replacing it: our
	-- own fill first, then the real (unmodified) model render on top.
	-- Solid black, no opacity - matches the character selection screen's
	-- own background (PDCity.BuildCharacterSelectTab's root.Paint below).
	local basePaint = panel.Paint
	panel.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 255))
		basePaint(self, w, h)
	end

	-- Real 3D lighting on the model itself (a proper DModelPanel feature,
	-- not something drawn in 2D over the top) - a soft cool ambient fill
	-- so nothing's pitch black, plus a bright key light from directly
	-- overhead for the actual "spotlit" look. Replaces an earlier attempt
	-- at faking this with a flat painted glow/oval underneath the model
	-- in PaintOver (BuildLane, below) - that read as a 2D sticker sitting
	-- under the character rather than actual light falling on them; real
	-- per-vertex lighting from GMod's own renderer looks like light
	-- because it IS light.
	panel:SetAmbientLight(Color(70, 70, 82))
	panel:SetDirectionalLight(BOX_TOP, Color(255, 248, 232))

	local ent = panel:GetEntity()
	if IsValid(ent) then
		for _, seqName in ipairs(POSE_SEQUENCES) do
			local seq = ent:LookupSequence(seqName)
			if seq and seq > 0 then
				ent:ResetSequence(seq)
				break
			end
		end

		-- Centred on the true vertical midpoint so head and feet get
		-- equal headroom. Pulled back enough to keep the whole figure in
		-- frame without cropping, but no further - it was FAR too small
		-- against its own background at the earlier 1.9x/FOV 40.
		local mn, mx = ent:GetRenderBounds()
		local height = mx.z - mn.z
		local midZ = mn.z + height * 0.5

		panel:SetFOV(30)
		panel:SetCamPos(Vector(height * 1.35, 0, midZ))
		panel:SetLookAt(Vector(0, 0, midZ))
	end

	-- Stops the stock slow auto-rotate - front-facing has to mean ALWAYS
	-- front-facing, not "starts front-facing then turns".
	panel.LayoutEntity = function() end

	return panel
end

--[[---------------------------------------------------------
	Player model picker - a grid of every model this player is currently
	allowed to choose (GetAllowedCharacterModels above - Site Admin's
	default list plus anything whitelisted to their own SteamID),
	filterable by name. Picking one calls onSelect(modelPath) and
	closes. Shared by the "Create New Character" bar and each existing
	character's "Change Model" button below.
-----------------------------------------------------------]]
local function OpenModelPicker(currentModel, onSelect)

	PDCity.PushMenuDim()
	local frame = PDCity.CreateModernFrame("Choose a Player Model", 700, 620)
	frame:Center()
	-- No PDCity.LockFrameOnTop - see OpenRenameDialog's own comment
	-- (below in this file) for why: a filter text entry + a grid of
	-- clickable icons is exactly the kind of screen its continuous
	-- MoveToFront can eat clicks on.
	frame.OnRemove = function() PDCity.PopMenuDim() end

	local top = 48

	local filterEntry = vgui.Create("DTextEntry", frame)
	filterEntry:SetPos(20, top + 14)
	filterEntry:SetSize(660, 32)
	filterEntry:SetPlaceholderText("Filter player models...")

	local gridScroll = vgui.Create("DScrollPanel", frame)
	gridScroll:SetPos(20, top + 54)
	gridScroll:SetSize(660, 500)
	PDCity.ApplyFastScroll(gridScroll)

	local grid = vgui.Create("DIconLayout", gridScroll)
	grid:Dock(TOP)
	grid:SetSpaceX(6)
	grid:SetSpaceY(6)

	local allModels = {}
	for _, model in ipairs(GetAllowedCharacterModels()) do
		local name = string.match(model, "([^/]+)%.mdl$") or model
		table.insert(allModels, { Model = model, Name = name })
	end
	table.sort(allModels, function(a, b) return a.Name < b.Name end)

	if #allModels == 0 then
		local empty = vgui.Create("DLabel", frame)
		empty:SetPos(20, top + 54)
		empty:SetSize(660, 60)
		empty:SetFont("PDCity_Small")
		empty:SetWrap(true)
		empty:SetText("No player models are available to choose from yet - ask an admin to add some in Site Admin's \"Character Models\" tab.")
		empty:SetTextColor(PDCity.THEME.TextDim)
	end

	local function RefreshGrid(filter)
		grid:Clear()
		filter = filter and filter:lower() or ""
		local shown = 0
		for _, entry in ipairs(allModels) do
			if shown >= 150 then break end
			if filter == "" or entry.Name:lower():find(filter, 1, true) or entry.Model:lower():find(filter, 1, true) then
				local icon = vgui.Create("SpawnIcon", grid)
				icon:SetSize(64, 64)
				icon:SetModel(entry.Model)
				icon:SetTooltip(entry.Name)
				if entry.Model == currentModel then
					icon.PaintOver = function(self, w, h)
						surface.SetDrawColor(PDCity.THEME.Accent)
						surface.DrawOutlinedRect(0, 0, w, h, 2)
					end
				end
				icon.DoClick = function()
					onSelect(entry.Model)
					frame:Close()
				end
				shown = shown + 1
			end
		end
	end
	RefreshGrid("")

	filterEntry.OnValueChange = function(self, val) RefreshGrid(val) end

end

--[[---------------------------------------------------------
	A smaller, undecorated cousin of cl_theme.lua's PDCity.CreateModernFrame
	for the three small prompts below (Rename/Delete) - that one enforces
	a 560x360 MINIMUM (shared by every other menu, sized for actual
	content-heavy screens), which left these tiny prompts mostly empty
	space no matter how little they actually needed to show. Same visual
	language (shadow, dark title bar, accent underline, logo, X to
	close) at whatever size is actually asked for, down to
	MIN_PROMPT_WIDE/TALL rather than that much bigger floor.
-----------------------------------------------------------]]
local MIN_PROMPT_WIDE, MIN_PROMPT_TALL = 360, 190

local function CreatePromptFrame(title, w, h)
	w = math.Clamp(w, MIN_PROMPT_WIDE, math.max(MIN_PROMPT_WIDE, ScrW() - 40))
	h = math.Clamp(h, MIN_PROMPT_TALL, math.max(MIN_PROMPT_TALL, ScrH() - 40))

	local frame = vgui.Create("DFrame")
	frame:SetSize(w, h)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(true)
	frame:SetSizable(false)
	frame:MakePopup()
	frame:SetAlpha(0)
	frame:AlphaTo(255, 0.15, 0)

	frame.Paint = function(self, panelW, panelH)
		PDCity.DrawShadow(0, 0, panelW, panelH, 8)
		draw.RoundedBox(8, 0, 0, panelW, panelH, PDCity.THEME.Background)
		draw.RoundedBoxEx(8, 0, 0, panelW, 46, PDCity.THEME.TitleBar, true, true, false, false)
		surface.SetDrawColor(PDCity.THEME.Accent)
		surface.DrawRect(0, 46, panelW, 2)

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
		if self:IsHovered() then draw.RoundedBox(4, 0, 0, btnW, btnH, PDCity.THEME.Panel) end
		local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.TextDim
		draw.SimpleText("\226\156\149", "PDCity_Body", btnW / 2, btnH / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	closeBtn.DoClick = function() frame:Close() end

	-- Same "actually remove, not just hide" override PDCity.CreateModernFrame
	-- uses - stock DFrame:Close() only SetVisible(false)s, which would
	-- leave PDCity.PopMenuDim() (wired to OnRemove below) never firing.
	frame.Close = function(self)
		if self.OnClose then self:OnClose() end
		self:Remove()
	end

	return frame
end

--[[---------------------------------------------------------
	"Rename" - a small text-entry dialog. Sends net "pdcity_rename_character"
	(core/sv_rpname.lua's PDCity.TryRenameCharacterSlot) and, since a
	successful rename does NOT trigger a full character-list resend (that
	would rebuild the whole lineup and lose which character is currently
	centred - see that file's own comment on why), calls onRenamed(name)
	immediately so the caller can update what it's showing right away,
	optimistically. A rejected rename (cooldown, name taken, admin lock...)
	DOES get a fresh list resent by the server, which lands via the
	ordinary "pdcity_character_screen" receiver below and rebuilds
	everything anyway, so nothing further is needed here for that case.
-----------------------------------------------------------]]
local function OpenRenameDialog(char, onRenamed)

	PDCity.PushMenuDim()
	local frame = CreatePromptFrame("Rename Character", 480, 220)
	-- Deliberately no PDCity.LockFrameOnTop - :MakePopup() already put
	-- this at the front, and continuously re-asserting that every frame
	-- (what LockFrameOnTop does) can interrupt a click's press/release
	-- cycle mid-interaction on a screen with real text entry + buttons
	-- like this one, eating the click outright - the exact bug that made
	-- the mandatory join screen unresponsive earlier, fixed the same way.
	frame.OnRemove = function() PDCity.PopMenuDim() end

	-- PDCity.CreateModernFrame enforces its own 560x360 MINIMUM
	-- (cl_theme.lua), regardless of what's requested above - the frame's
	-- ACTUAL size can end up bigger than that, so content has to be laid
	-- out from the real size read back here, not the requested numbers,
	-- or it ends up crammed into the top-left with unaccounted empty
	-- space on the right and along the bottom.
	local fw, fh = frame:GetWide(), frame:GetTall()
	local pad = 24
	local contentW = fw - pad * 2

	local blockH = 24 + 8 + 40 + 16 + 42 -- label + gap + entry + gap + button
	local top = 46 + (fh - 46 - blockH) / 2

	local label = vgui.Create("DLabel", frame)
	label:SetPos(pad, top)
	label:SetSize(contentW, 24)
	label:SetFont("PDCity_Body")
	label:SetText("New name for \"" .. char.Name .. "\":")
	label:SetTextColor(PDCity.THEME.TextDim)

	local nameEntry = vgui.Create("DTextEntry", frame)
	nameEntry:SetPos(pad, top + 24 + 8)
	nameEntry:SetSize(contentW, 40)
	nameEntry:SetValue(char.Name)
	nameEntry:RequestFocus()
	nameEntry:SelectAllOnFocus()

	local confirmBtn = vgui.Create("DButton", frame)
	confirmBtn:SetPos(pad, top + 24 + 8 + 40 + 16)
	confirmBtn:SetSize(contentW, 42)
	PDCity.StyleButton(confirmBtn, "Rename")

	local function TryRename()
		local name = string.Trim(nameEntry:GetValue() or "")
		if name == "" then
			nameEntry:SetPlaceholderText("Name required - type something first")
			nameEntry:SetValue("")
			nameEntry:RequestFocus()
			return
		end

		net.Start("pdcity_rename_character")
			net.WriteString(util.TableToJSON({ Slot = char.Slot, Name = name }))
		net.SendToServer()

		onRenamed(name)
		frame:Close()
	end
	confirmBtn.DoClick = TryRename
	nameEntry.OnEnter = TryRename

end

--[[---------------------------------------------------------
	"Delete Character" - two steps, both cancellable at any point:
	  1. A plain yes/cancel warning.
	  2. Type the character's exact name to actually confirm - the real
	     friction step, so a stray click can't delete anything on its
	     own. The server re-checks the typed name matches too
	     (core/sv_characters.lua's "delete" action) - this is just UX,
	     not the actual enforcement.
-----------------------------------------------------------]]
local function OpenDeleteConfirmStep2(char)

	PDCity.PushMenuDim()
	local frame = CreatePromptFrame("Confirm Deletion", 480, 260)
	-- No PDCity.LockFrameOnTop - see OpenRenameDialog's own comment above.
	frame.OnRemove = function() PDCity.PopMenuDim() end

	-- CreatePromptFrame's own MIN_PROMPT_WIDE/TALL floor is still lower
	-- than what's requested above, but reading the actual size back
	-- rather than assumed.
	local fw, fh = frame:GetWide(), frame:GetTall()
	local pad = 24
	local contentW = fw - pad * 2
	local btnW = (contentW - 12) / 2

	local blockH = 48 + 16 + 40 + 16 + 42 -- label + gap + entry + gap + buttons
	local top = 46 + (fh - 46 - blockH) / 2

	local label = vgui.Create("DLabel", frame)
	label:SetPos(pad, top)
	label:SetSize(contentW, 48)
	label:SetFont("PDCity_Body")
	label:SetWrap(true)
	label:SetText("Type \"" .. char.Name .. "\" below to permanently delete this character.")
	label:SetTextColor(PDCity.THEME.TextDim)

	local nameEntry = vgui.Create("DTextEntry", frame)
	nameEntry:SetPos(pad, top + 48 + 16)
	nameEntry:SetSize(contentW, 40)
	nameEntry:SetPlaceholderText(char.Name)
	nameEntry:RequestFocus()

	local deleteBtn = vgui.Create("DButton", frame)
	deleteBtn:SetPos(pad, top + 48 + 16 + 40 + 16)
	deleteBtn:SetSize(btnW, 42)
	PDCity.StyleButton(deleteBtn, "Delete", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })

	local cancelBtn = vgui.Create("DButton", frame)
	cancelBtn:SetPos(pad + btnW + 12, top + 48 + 16 + 40 + 16)
	cancelBtn:SetSize(btnW, 42)
	PDCity.StyleButton(cancelBtn, "Cancel",
		{ Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelBtn.DoClick = function() frame:Close() end

	local function TryDelete()
		local typed = string.Trim(nameEntry:GetValue() or "")
		if typed ~= char.Name then
			nameEntry:SetPlaceholderText("Name doesn't match - try again")
			nameEntry:SetValue("")
			nameEntry:RequestFocus()
			return
		end

		net.Start("pdcity_character_select")
			net.WriteString(util.TableToJSON({ Action = "delete", Slot = char.Slot, ConfirmName = typed }))
		net.SendToServer()

		frame:Close()
	end
	deleteBtn.DoClick = TryDelete
	nameEntry.OnEnter = TryDelete

end

local function OpenDeleteConfirmStep1(char)

	PDCity.PushMenuDim()
	local frame = CreatePromptFrame("Delete Character", 480, 220)
	-- No PDCity.LockFrameOnTop - see OpenRenameDialog's own comment above.
	frame.OnRemove = function() PDCity.PopMenuDim() end

	-- Read the actual size back rather than assuming the requested one -
	-- see OpenRenameDialog's own comment above.
	local fw, fh = frame:GetWide(), frame:GetTall()
	local pad = 24
	local contentW = fw - pad * 2
	local btnW = (contentW - 12) / 2

	local blockH = 72 + 16 + 42 -- label + gap + buttons
	local top = 46 + (fh - 46 - blockH) / 2

	local label = vgui.Create("DLabel", frame)
	label:SetPos(pad, top)
	label:SetSize(contentW, 72)
	label:SetFont("PDCity_Body")
	label:SetWrap(true)
	label:SetText("Are you sure you wish to delete your character and all of its progress?")
	label:SetTextColor(PDCity.THEME.TextDim)

	local yesBtn = vgui.Create("DButton", frame)
	yesBtn:SetPos(pad, top + 72 + 16)
	yesBtn:SetSize(btnW, 42)
	PDCity.StyleButton(yesBtn, "Yes", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })
	yesBtn.DoClick = function()
		frame:Close()
		OpenDeleteConfirmStep2(char)
	end

	local cancelBtn = vgui.Create("DButton", frame)
	cancelBtn:SetPos(pad + btnW + 12, top + 72 + 16)
	cancelBtn:SetSize(btnW, 42)
	PDCity.StyleButton(cancelBtn, "Cancel",
		{ Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })
	cancelBtn.DoClick = function() frame:Close() end

end

--[[---------------------------------------------------------
	Returns a panel for the Character Selection tab. `characters`/`limit`
	are optional - nil means "not loaded yet", and immediately requests
	the real list from the server (RequestFreshData) rather than making
	the player click a button first. The returned panel exposes
	PDCitySetData(characters, limit) so cl_f1_menu.lua can populate/
	refresh it later without rebuilding the whole tab.
-----------------------------------------------------------]]
function PDCity.BuildCharacterSelectTab(parent, characters, limit)

	-- The true edge-to-edge black fill happens on cl_f1_menu.lua's own
	-- `content` panel (UpdateChromeForTab) - a child can't paint past its
	-- own bounds (GMod clips every panel's draw calls to its own rect),
	-- so filling THIS panel alone would only ever reach as far as
	-- content's 48px DockPadding inset, not the actual screen edges.
	-- This still needs its own opaque fill though, for the ordinary
	-- (non-mandatory, sidebar-still-showing) F1 tab case.
	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 255))
	end

	-- Server branding strip - a small logo placeholder (swap for
	-- SetImage/DImage once there's an actual logo asset) and the server
	-- name beside it, top-left above the "Choose Your Character" title.
	local brand = vgui.Create("DPanel", root)
	brand:Dock(TOP)
	brand:SetTall(48)
	brand:DockMargin(20, 16, 20, 0)
	brand.Paint = function() end

	local brandLogo = vgui.Create("DPanel", brand)
	brandLogo:Dock(LEFT)
	brandLogo:SetWide(48)
	-- The server's logo (Site Admin > Site Theme, or materials/pdcity/
	-- PDCity.png). With no logo set, this slot is simply left empty.
	brandLogo.Paint = function(self, w, h)
		if PDCity.LOGO_MAT and not PDCity.LOGO_MAT:IsError() then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(PDCity.LOGO_MAT)
			surface.DrawTexturedRect(0, 0, w, h)
		end
	end

	local brandName = vgui.Create("DLabel", brand)
	brandName:Dock(LEFT)
	brandName:DockMargin(14, 0, 0, 0)
	brandName:SetWide(500)
	brandName:SetFont("PDCity_Brand")
	brandName:SetText(PDCity.BRAND_NAME)
	-- This screen can open before the Site Theme (server name) has synced.
	brandName.Think = function(self)
		if self:GetText() ~= PDCity.BRAND_NAME then self:SetText(PDCity.BRAND_NAME) end
	end
	brandName:SetTextColor(PDCity.THEME.Text)
	brandName:SetContentAlignment(4)

	-- Centred - takes the "X / Y character slots used" line's old spot
	-- (removed; not shown any more) rather than sitting left-aligned
	-- above it.
	local title = vgui.Create("DLabel", root)
	title:Dock(TOP)
	title:SetTall(34)
	title:SetFont("PDCity_Title")
	title:SetText("Choose Your Character")
	title:SetTextColor(PDCity.THEME.Text)
	title:SetContentAlignment(5)

	-- Dock(FILL), not Dock(TOP) - a DPanel doesn't auto-size to its
	-- children, and nothing here ever gave this an explicit SetTall, so
	-- it was collapsing to zero height and silently hiding everything
	-- inside it (the character list, or the "Switch Character" button)
	-- regardless of what PopulateList/the button actually built.
	local body = vgui.Create("DPanel", root)
	body:Dock(FILL)
	body:DockMargin(0, 16, 0, 0)
	body.Paint = function() end

	local function RequestFreshData()
		body:Clear(true)

		local loading = vgui.Create("DLabel", body)
		loading:Dock(TOP)
		loading:SetTall(30)
		loading:SetFont("PDCity_Small")
		loading:SetText("Requesting your character list...")
		loading:SetTextColor(PDCity.THEME.TextDim)

		net.Start("pdcity_request_character_screen")
		net.SendToServer()
	end

	local mandatory = false

	local function PopulateList(characterList, slotLimit, isMandatory)
		mandatory = isMandatory or false
		body:Clear(true)

		local function SendSelection(payload)
			net.Start("pdcity_character_select")
				net.WriteString(util.TableToJSON(payload))
			net.SendToServer()

			-- Optimistic close - nothing else ever closes this dashboard
			-- after a successful pick (the server unfreezing them doesn't,
			-- by itself, touch this client-side popup at all), so without
			-- this the screen just sat there forever even once selection
			-- actually went through. Safe to close eagerly: a REJECTED
			-- selection (limit hit, bad name...) gets this whole screen
			-- re-sent fresh by the server on every failure path anyway
			-- (core/sv_characters.lua's SendCharacterScreen), which
			-- reopens everything via the same "pdcity_character_screen"
			-- receiver either way.
			if IsValid(GAMEMODE.PDCityHelpFrame) then
				GAMEMODE.PDCityHelpFrame:Remove()
			end
		end

		local atLimit = #characterList >= slotLimit

		-- Docked BOTTOM, created before the FILL stage below so it claims
		-- its space first. Starts as a single button; clicking it swaps
		-- in a name field + confirm/cancel in place.
		local createBar = vgui.Create("DPanel", body)
		createBar:Dock(BOTTOM)
		createBar:SetTall(44)
		createBar:DockMargin(0, 12, 0, 0)
		createBar.Paint = function() end

		local expanded = false
		local selectedModel = ""

		local function RebuildCreateBar()
			createBar:Clear(true)

			if not expanded then
				local toggleBtn = vgui.Create("DButton", createBar)
				toggleBtn:SetSize(260, 36)
				PDCity.StyleButton(toggleBtn, atLimit and "Character Slots Full" or "+ Create New Character",
					atLimit and { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim } or nil)
				toggleBtn:SetEnabled(not atLimit)
				toggleBtn.DoClick = function()
					expanded = true
					RebuildCreateBar()
				end
				createBar.PDCityLayout = function(w) toggleBtn:SetPos((w - 260) / 2, 4) end
				return
			end

			local nameEntry = vgui.Create("DTextEntry", createBar)
			nameEntry:SetSize(260, 36)
			nameEntry:SetPlaceholderText("New character's name...")

			local modelBtn = vgui.Create("DButton", createBar)
			modelBtn:SetSize(130, 36)
			local function RefreshModelBtn()
				PDCity.StyleButton(modelBtn, selectedModel ~= "" and "Model Chosen" or "Choose Model...")
			end
			RefreshModelBtn()
			modelBtn.DoClick = function()
				OpenModelPicker(selectedModel, function(model)
					selectedModel = model
					RefreshModelBtn()
				end)
			end

			local confirmBtn = vgui.Create("DButton", createBar)
			confirmBtn:SetSize(90, 36)
			PDCity.StyleButton(confirmBtn, "Create")

			local cancelBtn = vgui.Create("DButton", createBar)
			cancelBtn:SetSize(36, 36)
			cancelBtn:SetText("")
			cancelBtn.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
				draw.SimpleText("\226\156\149", "PDCity_Small", w / 2, h / 2, PDCity.THEME.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			cancelBtn.DoClick = function()
				expanded = false
				RebuildCreateBar()
			end

			local function TryCreate()
				local name = string.Trim(nameEntry:GetValue() or "")
				if name == "" then
					nameEntry:SetPlaceholderText("Name required - type something first")
					nameEntry:RequestFocus()
					return
				end
				SendSelection({ Action = "create", Name = name, Model = selectedModel })
			end
			confirmBtn.DoClick = TryCreate
			nameEntry.OnEnter = TryCreate

			createBar.PDCityLayout = function(w)
				local totalW = 260 + 8 + 130 + 8 + 90 + 8 + 36
				local x = (w - totalW) / 2
				nameEntry:SetPos(x, 4)
				modelBtn:SetPos(x + 260 + 8, 4)
				confirmBtn:SetPos(x + 260 + 8 + 130 + 8, 4)
				cancelBtn:SetPos(x + 260 + 8 + 130 + 8 + 90 + 8, 4)
			end

			nameEntry:RequestFocus()
		end

		createBar.PerformLayout = function(self, w, h)
			if self.PDCityLayout then self.PDCityLayout(w) end
		end

		RebuildCreateBar()

		local deck = characterList

		local stage = vgui.Create("DPanel", body)
		stage:Dock(FILL)
		stage:DockMargin(0, 12, 0, 0)
		stage.Paint = function() end

		if #deck == 0 then
			local empty = vgui.Create("DLabel", stage)
			empty:Dock(TOP)
			empty:SetTall(40)
			empty:SetFont("PDCity_Small")
			empty:SetContentAlignment(5)
			empty:SetText("No characters yet - create one below to get started.")
			empty:SetTextColor(PDCity.THEME.TextDim)

			if mandatory then
				expanded = true
				RebuildCreateBar()
			end
			return
		end

		-- Carousel-style filmstrip: every character in a fixed-order row,
		-- but only the CENTRED one is fully visible (Select/Edit buttons,
		-- a faint ground spotlight) - every other one is dimmed down to
		-- barely-there. Clicking a dimmed one just slides it into the
		-- centre (highlightIndex changes, stage.Think eases the whole
		-- row's offset toward the new target) - it does NOT switch
		-- character. Only the dedicated Select button under the centred
		-- one actually does that.
		--
		-- Sized proportionally to the stage itself (not fixed pixels) so
		-- it scales with the window/dashboard rather than a magic number
		-- that only looks right at one resolution.
		-- Name sits ABOVE the model now (a nameplate over the character's
		-- head), not below it - NAME_H bumped to match the bigger
		-- PDCity_CharacterName font it uses.
		local NAME_H, NAME_GAP, BTN_H, BTN_GAP = 40, 10, 32, 8
		local LANE_GAP = 50
		local MAX_BTN_ROWS = 4 -- Rename/Choose Model/Delete/Back - the edit submenu, the tallest state a lane's button stack ever needs

		local lanes = {}
		local highlightIndex = 1
		local rowOffset = 0
		local metrics = { laneW = 260, previewH = 340, laneH = 0 }

		local function RecomputeMetrics(stageW, stageH)
			metrics.previewH = math.Clamp(stageH * 0.62, 260, 560)
			metrics.laneW = math.Clamp(metrics.previewH * 0.55, 160, 340)
			metrics.laneH = NAME_H + NAME_GAP + metrics.previewH + 10 + MAX_BTN_ROWS * (BTN_H + BTN_GAP)
		end

		-- Where the model preview starts - name (+ its gap) sits above it.
		local function PreviewY()
			return NAME_H + NAME_GAP
		end

		-- Every button's Y position by row (1-based) within a lane's
		-- button stack - same for every lane, only WHICH buttons occupy
		-- which row differs (Select/Edit normally, Rename/Choose Model/
		-- Delete/Back once "Edit" has been clicked).
		local function ButtonRowY(row)
			return PreviewY() + metrics.previewH + 10 + BTN_GAP + (row - 1) * (BTN_H + BTN_GAP)
		end

		-- Only the CENTRED lane ever shows any buttons at all; every
		-- other lane hides all of them regardless of its own edit-mode
		-- flag, and loses that flag the moment it stops being centred -
		-- clicking Edit, then clicking away and back, always starts
		-- fresh at Select/Edit rather than reopening mid-edit.
		local function RefreshHighlight()
			for i, lane in ipairs(lanes) do
				if i ~= highlightIndex then lane.PDCityEditMode = false end

				local isHi = (i == highlightIndex)
				local editMode = isHi and lane.PDCityEditMode and not lane.PDCityIsStaffSlot

				lane.PDCitySelectBtn:SetVisible(isHi and not editMode)
				-- "Staff on Duty" (server-forced name/model, core/sv_accounts.lua)
				-- has nothing to edit - no Rename, no Choose Model, no
				-- Delete - so it never even shows the Edit link.
				lane.PDCityEditBtn:SetVisible(isHi and not editMode and not lane.PDCityIsStaffSlot)

				lane.PDCityRenameBtn:SetVisible(isHi and editMode)
				lane.PDCityChooseModelBtn:SetVisible(isHi and editMode)
				lane.PDCityDeleteBtn:SetVisible(isHi and editMode)
				lane.PDCityBackBtn:SetVisible(isHi and editMode)

				-- Dims via TRANSPARENCY (Panel:SetAlpha, which DModelPanel's
				-- own Paint feeds straight into render.SetBlend), not colour
				-- modulation - both tried and reverted (see PaintOver's own
				-- comment below on why: colour modulation shifted skin
				-- tone, panel alpha rendered the head transparent since
				-- DModelPanel blends its different materials/shaders
				-- inconsistently). Dimming is a 2D rectangle drawn in
				-- PaintOver instead - fully within our own control, no
				-- engine shader quirks. This just keeps the preview/avatar
				-- themselves at full brightness; PaintOver does the work.
				if IsValid(lane.PDCityPreview) then lane.PDCityPreview:SetAlpha(255) end
				if IsValid(lane.PDCityAvatar) then lane.PDCityAvatar:SetAlpha(255) end
				if IsValid(lane.PDCityName) then
					lane.PDCityName:SetTextColor(isHi and PDCity.THEME.Text or PDCity.THEME.TextDim)
				end
			end
		end

		local function BuildLane(char, index)
			local lane = vgui.Create("DButton", stage)
			lane:SetText("")
			lane.PDCityIsStaffSlot = (char.Slot == PDCity.STAFF_SLOT)
			-- Without this, lane falls back to DButton's own default skin
			-- (a light grey/white box) wherever no child panel covers it -
			-- exactly the name/button strip below the model, which isn't
			-- fully covered by anything.
			lane.Paint = function() end

			-- PaintOver runs AFTER children (the model panel included), so
			-- this is what actually layers on TOP of the rendered
			-- character - drawing the dim overlay in an earlier .Paint
			-- hook put it BEHIND the model panel's own (opaque)
			-- background, where it was invisible.
			--
			-- Dimming non-centred lanes went through two engine-level
			-- attempts first, both reverted: colour modulation
			-- (render.SetColorModulation) shifted skin tone toward a
			-- completely different colour at the darkness needed to read
			-- as "dimmed" - a bad look regardless of intent; panel alpha
			-- (render.SetBlend) rendered the HEAD transparent while the
			-- body just dimmed normally, since DModelPanel's different
			-- materials/shaders (skin/eyes vs cloth) don't respond to a
			-- reduced blend value the same way. A plain 2D rectangle here
			-- avoids both - fully within our own control, no shader
			-- inconsistency possible. True black at HIGH opacity so it
			-- reads as "almost fully hidden in the dark" rather than
			-- leaving enough of the character showing through for any
			-- edge-vs-backdrop mismatch to be visible at all.
			--
			-- The centred lane used to also get a painted glow/oval here
			-- standing in for a spotlight - looked like a flat 2D sticker
			-- sitting under the character rather than actual light on
			-- them. Replaced by real per-vertex lighting on the model
			-- itself instead (BuildCharacterPreview's SetAmbientLight/
			-- SetDirectionalLight above), so there's nothing left to draw
			-- here for the highlighted lane at all.
			lane.PaintOver = function(self, w, h)
				if index == highlightIndex then return end
				draw.RoundedBox(0, 0, 0, w, PreviewY() + metrics.previewH, Color(0, 0, 0, 235))
			end

			-- Re-centres on click - never switches character, no matter
			-- which lane (even the already-centred one) is clicked.
			lane.DoClick = function()
				if highlightIndex == index then return end
				highlightIndex = index
				RefreshHighlight()
			end

			local function BuildVisual()
				if char.Model and char.Model ~= "" then
					local preview = BuildCharacterPreview(lane, char.Model, metrics.laneW, metrics.previewH)
					preview:SetMouseInputEnabled(false)
					lane.PDCityPreview = preview
				else
					local initial = string.upper(string.sub(char.Name, 1, 1))
					local avatar = vgui.Create("DPanel", lane)
					avatar:SetMouseInputEnabled(false)
					avatar.Paint = function(self, w, h)
						draw.RoundedBox(w / 2, 0, 0, w, h, PDCity.THEME.Accent)
						draw.SimpleText(initial, "PDCity_Title", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
					lane.PDCityAvatar = avatar
				end
			end
			BuildVisual()

			local nameLabel = vgui.Create("DLabel", lane)
			nameLabel:SetFont("PDCity_CharacterName")
			nameLabel:SetContentAlignment(5)
			nameLabel:SetText(char.Name)
			nameLabel:SetTextColor(PDCity.THEME.Text)
			nameLabel:SetMouseInputEnabled(false)
			lane.PDCityName = nameLabel

			local selectBtn = vgui.Create("DButton", lane)
			StyleTextLink(selectBtn, "Select")
			selectBtn.DoClick = function() SendSelection({ Action = "select", Slot = char.Slot }) end
			lane.PDCitySelectBtn = selectBtn

			-- "Edit" now just opens the Rename/Choose Model/Delete/Back
			-- submenu in place, rather than jumping straight to the model
			-- picker like it used to.
			local editBtn = vgui.Create("DButton", lane)
			StyleTextLink(editBtn, "Edit")
			editBtn.DoClick = function()
				lane.PDCityEditMode = true
				RefreshHighlight()
			end
			lane.PDCityEditBtn = editBtn

			local renameBtn = vgui.Create("DButton", lane)
			StyleTextLink(renameBtn, "Rename")
			renameBtn.DoClick = function()
				OpenRenameDialog(char, function(newName)
					char.Name = newName
					nameLabel:SetText(newName)

					lane.PDCityEditMode = false
					RefreshHighlight()
				end)
			end
			lane.PDCityRenameBtn = renameBtn

			local chooseModelBtn = vgui.Create("DButton", lane)
			StyleTextLink(chooseModelBtn, "Choose Model")
			chooseModelBtn.DoClick = function()
				OpenModelPicker(char.Model, function(model)
					char.Model = model
					net.Start("pdcity_set_character_model")
						net.WriteString(util.TableToJSON({ Slot = char.Slot, Model = model }))
					net.SendToServer()
					if IsValid(lane.PDCityPreview) then lane.PDCityPreview:Remove() end
					if IsValid(lane.PDCityAvatar) then lane.PDCityAvatar:Remove() end
					lane.PDCityPreview, lane.PDCityAvatar = nil, nil
					BuildVisual()
					stage:InvalidateLayout(true)

					lane.PDCityEditMode = false
					RefreshHighlight()
				end)
			end
			lane.PDCityChooseModelBtn = chooseModelBtn

			local deleteBtn = vgui.Create("DButton", lane)
			StyleTextLink(deleteBtn, "Delete Character")
			deleteBtn.DoClick = function() OpenDeleteConfirmStep1(char) end
			lane.PDCityDeleteBtn = deleteBtn

			local backBtn = vgui.Create("DButton", lane)
			StyleTextLink(backBtn, "Back")
			backBtn.DoClick = function()
				lane.PDCityEditMode = false
				RefreshHighlight()
			end
			lane.PDCityBackBtn = backBtn

			return lane
		end

		for i, char in ipairs(deck) do
			table.insert(lanes, BuildLane(char, i))
		end
		RefreshHighlight()

		local function TargetOffset(w)
			local centreLaneX = (highlightIndex - 1) * (metrics.laneW + LANE_GAP)
			return w / 2 - (centreLaneX + metrics.laneW / 2)
		end

		local function PositionLanes(w)
			local m = metrics
			local y = math.max(0, (stage:GetTall() - m.laneH) / 2)

			for i, lane in ipairs(lanes) do
				local x = (i - 1) * (m.laneW + LANE_GAP) + rowOffset
				lane:SetPos(x, y)
				lane:SetSize(m.laneW, m.laneH)

				local previewY = PreviewY()

				if IsValid(lane.PDCityPreview) then
					lane.PDCityPreview:SetPos(0, previewY)
					lane.PDCityPreview:SetSize(m.laneW, m.previewH)
				elseif IsValid(lane.PDCityAvatar) then
					local avatarSize = math.min(m.laneW, m.previewH) * 0.6
					lane.PDCityAvatar:SetSize(avatarSize, avatarSize)
					lane.PDCityAvatar:SetPos((m.laneW - avatarSize) / 2, previewY + (m.previewH - avatarSize) / 2)
				end

				-- Above the model - a nameplate over the character's head,
				-- not a caption underneath it.
				lane.PDCityName:SetPos(0, 0)
				lane.PDCityName:SetSize(m.laneW, NAME_H)

				-- Select/Edit (normal) and Rename/Choose Model/Delete/Back
				-- (edit mode) share the same 4 row slots - RefreshHighlight
				-- decides which set is actually VISIBLE, this just makes
				-- sure every button is somewhere sane regardless.
				lane.PDCitySelectBtn:SetPos(0, ButtonRowY(1))
				lane.PDCitySelectBtn:SetSize(m.laneW, BTN_H)
				lane.PDCityEditBtn:SetPos(0, ButtonRowY(2))
				lane.PDCityEditBtn:SetSize(m.laneW, BTN_H)

				lane.PDCityRenameBtn:SetPos(0, ButtonRowY(1))
				lane.PDCityRenameBtn:SetSize(m.laneW, BTN_H)
				lane.PDCityChooseModelBtn:SetPos(0, ButtonRowY(2))
				lane.PDCityChooseModelBtn:SetSize(m.laneW, BTN_H)
				lane.PDCityDeleteBtn:SetPos(0, ButtonRowY(3))
				lane.PDCityDeleteBtn:SetSize(m.laneW, BTN_H)
				lane.PDCityBackBtn:SetPos(0, ButtonRowY(4))
				lane.PDCityBackBtn:SetSize(m.laneW, BTN_H)
			end
		end

		stage.PerformLayout = function(self, w, h)
			RecomputeMetrics(w, h)
			rowOffset = TargetOffset(w) -- snap on first layout/resize, don't animate that
			PositionLanes(w)
		end

		stage.Think = function(self)
			local target = TargetOffset(self:GetWide())
			if math.abs(rowOffset - target) > 0.5 then
				rowOffset = Lerp(FrameTime() * 8, rowOffset, target)
				PositionLanes(self:GetWide())
			end
		end
	end

	root.PDCitySetData = function(characterList, slotLimit, isMandatory)
		PopulateList(characterList, slotLimit, isMandatory)
	end

	if characters then
		PopulateList(characters, limit, mandatory)
	else
		-- Every F1 tab (including this one) is built up front the moment
		-- F1 opens, regardless of which tab is actually showing
		-- (cl_f1_menu.lua's own tab loop) - calling RequestFreshData
		-- HERE used to fire this request on every single F1 open no
		-- matter which tab someone actually wanted, and the server's
		-- reply (core/sv_characters.lua's SendCharacterScreen, received
		-- below) always force-switches to this tab and takes over the
		-- whole screen once it lands - so simply opening F1 for any
		-- reason got hijacked straight into Character Selection with the
		-- rest of the dashboard gone. Exposed instead, for
		-- cl_f1_menu.lua to call ONLY once this tab is actually clicked.
		root.PDCityRequestData = RequestFreshData
	end

	return root

end

--[[---------------------------------------------------------
	Server pushes this two ways: unprompted right after
	PlayerInitialSpawn (the mandatory join screen has no frame open yet -
	build one fresh, full-screen, no close button), or in response to a
	request from an already-open F1 session's Character Selection tab
	(refresh that tab in place instead of opening a second dashboard on
	top of the first).
-----------------------------------------------------------]]
net.Receive("pdcity_character_screen", function()
	local characters = util.JSONToTable(net.ReadString() or "[]") or {}
	local limit = net.ReadUInt(8)
	local mandatory = net.ReadBool()

	if IsValid(GAMEMODE.PDCityHelpFrame) then
		GAMEMODE.PDCityHelpFrame.PDCitySelectTabByName("Character Selection")
		GAMEMODE.PDCityHelpFrame.PDCitySetCharacterData({ Characters = characters, Limit = limit, Mandatory = mandatory })
		return
	end

	PDCity.OpenF1Menu("Character Selection", true, { Characters = characters, Limit = limit, Mandatory = mandatory })
end)
