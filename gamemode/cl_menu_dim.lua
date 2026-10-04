--[[---------------------------------------------------------
	Shared "pause menu" backdrop for modal menus (F1, F4) - a
	semi-transparent full-screen panel behind the frame, plus the
	client's own "volume" convar temporarily lowered rather than muted
	outright, both restored when the menu closes.

	Reference-counted (PushMenuDim/PopMenuDim), not a plain on/off flag:
	F1 and F4 can each be open independently, and closing whichever one
	was opened SECOND shouldn't undim/un-dampen while the other is still
	open. Only the count reaching zero actually restores anything.

	Callers: call PushMenuDim() right before creating the frame (so the
	dim panel, created here, ends up BEHIND it in the popup stack), and
	PopMenuDim() from the frame's OnRemove - not OnClose, which doesn't
	fire for a bare :Remove() (both F1 and F4 close themselves that way
	on a second keypress, see cl_f1_menu.lua's own comment on exactly
	this - OnRemove is the only hook guaranteed to fire either way).
-----------------------------------------------------------]]

local DIM_ALPHA = 215
local DUCK_FACTOR = 0.35
local FADE_TIME = 0.15

local dimCount = 0
local savedVolume
local dimPanel
local menuOpen = false -- read by the client-side PlayerBindPress suppression, near the bottom of this file

-- Derma_DrawBlur (the usual shortcut for this) isn't available here -
-- pdcity defines its own init.lua/cl_init.lua rather than deriving from
-- sandbox, and whatever normally pulls the derma helper library in
-- doesn't run for this gamemode. pp/blurscreen is a base engine material
-- with no such dependency, so drawn by hand instead: a few passes at
-- increasing blur radius, sampling the screen texture updated fresh
-- each frame.
local BlurMat = Material("pp/blurscreen")

local function DrawBlur(panel, amount)
	local x, y = panel:LocalToScreen(0, 0)

	surface.SetMaterial(BlurMat)
	surface.SetDrawColor(255, 255, 255)

	for i = 1, 3 do
		BlurMat:SetFloat("$blur", (i / 3) * amount)
		BlurMat:Recompute()
		render.UpdateScreenEffectTexture()
		surface.DrawTexturedRect(-x, -y, ScrW(), ScrH())
	end
end

-- The actual "turn it on/off" side effects, pulled out of Push/PopMenuDim
-- so the watchdog below can drive them directly too, on whatever it
-- observes is ACTUALLY true, without needing to fake a matching push/pop
-- pair through the reference count to get there.
-- Tells the server whether ANY PD Roleplay menu is currently open, so it
-- can suppress native game binds (weapon slots, reload...) while one is -
-- core/sv_keybinds.lua's own "pdcity_menu_open_state" receiver, added
-- after "the game's other hotkeys activate while typing" was reported.
-- Piggybacking on Enable/DisableDim rather than tracking this
-- separately: those two already run exactly once per real open/close
-- transition (including the watchdog's own correction below), so this
-- can't drift out of sync with them by adding its own duplicate logic.
local function SendMenuOpenState(open)
	net.Start("pdcity_menu_open_state")
		net.WriteBool(open)
	net.SendToServer()
end

local function EnableDim()
	if IsValid(dimPanel) then return end -- already on

	menuOpen = true
	SendMenuOpenState(true)

	local volConVar = GetConVar("volume")
	if IsValid(volConVar) then
		savedVolume = volConVar:GetFloat()
		RunConsoleCommand("volume", tostring(savedVolume * DUCK_FACTOR))
	end

	dimPanel = vgui.Create("DPanel")
	dimPanel:SetSize(ScrW(), ScrH())
	dimPanel:SetPos(0, 0)
	dimPanel:SetMouseInputEnabled(false)
	dimPanel:SetAlpha(0)
	dimPanel:AlphaTo(255, FADE_TIME, 0)
	dimPanel.Paint = function(self, w, h)
		-- Very slight - this is meant to soften the world behind an open
		-- menu, not obscure it; a heavy blur here would fight the menu's
		-- own translucency (PDCity.THEME's 90%-opaque panels, cl_theme.lua).
		DrawBlur(self, 2)
		draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, DIM_ALPHA))
	end
end

local function DisableDim()
	menuOpen = false
	SendMenuOpenState(false)

	if savedVolume then
		RunConsoleCommand("volume", tostring(savedVolume))
		savedVolume = nil
	end

	if IsValid(dimPanel) then
		local panel = dimPanel
		panel:AlphaTo(0, FADE_TIME, 0, function()
			if IsValid(panel) then panel:Remove() end
		end)
	end
	dimPanel = nil
end

function PDCity.PushMenuDim()
	dimCount = dimCount + 1
	if dimCount == 1 then EnableDim() end -- already dimmed/dampened by another open menu otherwise
end

function PDCity.PopMenuDim()
	dimCount = math.max(0, dimCount - 1)
	if dimCount == 0 then DisableDim() end -- another menu using this is still open otherwise
end

--[[---------------------------------------------------------
	Safety net: every Push here is meant to be matched by exactly one Pop
	(each menu's OnRemove), but there's no way to guarantee some future
	caller - or an addon conflict, or a Lua error thrown mid-close by
	something else entirely - never breaks that pairing. Getting this
	wrong in the "stuck dim" direction is uniquely bad: unlike most bugs,
	the player has no way to fix it themselves (the screen being dark
	doesn't stop them finding a menu that isn't there to close).

	Checks BOTH directions every 10 seconds - dimmed with nothing open
	(the stuck-dark case above), and equally, something open that never
	dimmed at all (a menu that skipped PushMenuDim, or got out of sync
	the other way) - rather than only ever correcting one of them.
	Drives EnableDim/DisableDim directly off what's actually on screen,
	not the push/pop count (which a push nobody called can't retroactively
	fix) - dimCount is nudged to match afterwards purely so a real close
	later still pops back to a sane state instead of underflowing.
-----------------------------------------------------------]]
-- Checked by NAME PATTERN, not a hardcoded list of specific frames
-- (GAMEMODE.PDCityJobFrame, PDCityHelpFrame, ...) - every menu built on
-- PDCity.CreateModernFrame already stores its frame as GAMEMODE.PDCity*Frame
-- by convention (see cl_f1_menu.lua, cl_f4_menu.lua, cl_staff_menu.lua,
-- cl_f4_admin.lua), so this catches every one of them, including future
-- ones, automatically - a hardcoded list here silently stops covering a
-- menu the moment a new one is added and someone forgets to update it
-- (exactly what happened when the Staff Menu was added after this watchdog
-- already existed: it pushes/pops the same dim but wasn't in the list,
-- so opening ONLY it would have this force the dim off while it was
-- still legitimately open).
local function AnyMenuFrameOpen()
	for key, value in pairs(GAMEMODE) do
		if isstring(key) and key:find("^PDCity.*Frame$") and IsValid(value) then
			return true
		end
	end
	return false
end

timer.Create("pdcity_MenuDimWatchdog", 0.5, 0, function()
	local frameOpen = AnyMenuFrameOpen()
	local dimmed = IsValid(dimPanel)

	if frameOpen and not dimmed then
		dimCount = math.max(dimCount, 1)
		EnableDim()
	elseif dimmed and not frameOpen then
		dimCount = 0
		DisableDim()
	end
end)

timer.Create("pdcity_MenuDimEmergencyReset", 5, 0, function()
	if not AnyMenuFrameOpen() and IsValid(dimPanel) then
		dimCount = 0
		DisableDim()
	end
end)

--[[---------------------------------------------------------
	Suppressing CLIENT-ONLY game binds (the Context Menu's default "C"
	key chief among them) while a PD Roleplay menu is open - reported as
	still leaking through even after core/sv_keybinds.lua's own
	PlayerBindPress suppression was added for the same complaint.

	That fix only ever covered binds the SERVER gets told about -
	weapon slots, reload, and the like. Opening the Context Menu is a
	purely client-side UI action (no server round-trip at all), so it
	never reached that hook in the first place; PlayerBindPress fires
	client-side too, for every local bind press regardless of whether
	it's later relayed to the server, which is what this actually needs.

	Same F1/F4 exemption as the server-side version, for the same
	reason - those two are documented (cl_staff_menu.lua's own header)
	as deliberately bypassing normal focus suppression so the same key
	that opened a menu also closes it.

	`menuOpen` alone isn't enough, though - it only tracks OUR OWN menus
	that actually call PDCity.PushMenuDim (every PDCity.CreateModernFrame-
	based one does), but plenty of smaller, standalone popups in this
	gamemode (the Prop Copier's naming prompt, its removal confirmation,
	...) are plain DFrames that never touch the dim system at all, since
	they don't need the dim/blur effect. Typing Ctrl+C to copy text out of
	ANY text field, in ANY of those, hit exactly this: menuOpen was false,
	so "C" (gm_showspare1) sailed straight through to the Context Menu.
	Checking the actual keyboard-focused panel instead covers every text
	field in the gamemode regardless of which popup it's in, with no
	per-popup opt-in required.
-----------------------------------------------------------]]
local EXEMPT_BINDS = {
	["gm_showhelp"] = true,  -- F1
	["gm_showspare2"] = true, -- F4
}

local function TextEntryHasFocus()
	local focus = vgui.GetKeyboardFocus()
	return IsValid(focus) and focus.GetClassName and focus:GetClassName() == "DTextEntry"
end

hook.Add("PlayerBindPress", "pdcity_SuppressClientBindsWhileMenuOpen", function(ply, bind, pressed)
	if EXEMPT_BINDS[bind] then return end
	if menuOpen or TextEntryHasFocus() then return true end
end)
