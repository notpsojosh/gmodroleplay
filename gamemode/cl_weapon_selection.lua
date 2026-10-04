--[[---------------------------------------------------------
	Fully custom weapon selector, replacing the stock CHudWeaponSelection
	entirely (hidden below via GM:HUDShouldDraw). A per-weapon Lua hook
	(SWEP:DrawWeaponSelection) exists for restyling the icon preview box,
	but the number/name PILL ROW around it is drawn by the engine in C++
	with no Lua override point at all - there's nothing in
	gamemodes/base for it to hook. Full replacement was the only way to
	theme the whole thing, so this reimplements just enough of the
	actual switching behaviour to feel the same:

	  - Number keys (slot1..slot6) highlight that slot's weapon (or cycle
	    within it on repeated presses if it holds several) - never an
	    instant switch, same as scrolling.
	  - Mouse wheel (invnext/invprev) cycles through every weapon across
	    every slot, highlighting as it goes.
	  - Nothing switches until you left-click while the selector's open -
	    that's the ONLY way a switch happens. If you stop giving it input
	    and never click, the row just fades back out on its own
	    (VISIBLE_HOLD) with whatever was already active left untouched.
	  - "lastinv" (usually Q) is left alone entirely - stock behaviour,
	    no custom visual, since it doesn't need browsing.

	Everything else (reload/attack binds, holstering, ammo, weapon
	pickup auto-switch) is untouched - this only ever decides WHICH
	weapon ends up active, the same thing a number key or the scroll
	wheel always did, just requested via RunConsoleCommand("use", ...)
	instead of leaving it to the engine's own now-hidden selector.
-----------------------------------------------------------]]

-- How long the row stays visible with no further input before fading
-- back out - display timing only now, NOT a "commit the switch" clock.
local VISIBLE_HOLD = 3

local selectorOpen = false
local openUntil = 0
local highlightWeapon = nil

local function GetSortedWeapons()
	local ply = LocalPlayer()
	if not IsValid(ply) then return {} end

	local list = ply:GetWeapons()
	table.sort(list, function(a, b)
		if a:GetSlot() ~= b:GetSlot() then return a:GetSlot() < b:GetSlot() end
		return a:GetSlotPos() < b:GetSlotPos()
	end)
	return list
end

local function OpenSelector(target)
	if not IsValid(target) then return end
	selectorOpen = true
	openUntil = CurTime() + VISIBLE_HOLD
	highlightWeapon = target
end

-- Left-click only - actually switches to whatever's highlighted.
local function ConfirmSelection()
	local ply = LocalPlayer()
	if IsValid(highlightWeapon) and IsValid(ply) and highlightWeapon ~= ply:GetActiveWeapon() then
		RunConsoleCommand("use", highlightWeapon:GetClass())
	end
	selectorOpen = false
	highlightWeapon = nil
end

-- Timeout only - just hides the row again, no switch. Never clicked =
-- never wanted it, whatever was active stays active.
local function CancelSelector()
	selectorOpen = false
	highlightWeapon = nil
end

local function HandleSlotPress(slotIndex)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local inSlot = {}
	for _, wep in ipairs(GetSortedWeapons()) do
		if wep:GetSlot() == slotIndex then table.insert(inSlot, wep) end
	end
	if #inSlot == 0 then return end

	if #inSlot == 1 then
		-- Only one weapon in this slot (no cycling possible) - still
		-- just highlights it and waits for a click or the dwell
		-- timeout like every other slot, no instant-switch shortcut.
		OpenSelector(inSlot[1])
		return
	end

	local current = (selectorOpen and highlightWeapon) or ply:GetActiveWeapon()
	local currentIsInSlot = IsValid(current) and current:GetSlot() == slotIndex

	if not currentIsInSlot then
		OpenSelector(inSlot[1])
		return
	end

	for i, wep in ipairs(inSlot) do
		if wep == current then
			OpenSelector(inSlot[(i % #inSlot) + 1])
			return
		end
	end

	OpenSelector(inSlot[1])
end

local function HandleCycle(dir)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local list = GetSortedWeapons()
	if #list == 0 then return end

	local current = (selectorOpen and highlightWeapon) or ply:GetActiveWeapon()
	local index = 1
	for i, wep in ipairs(list) do
		if wep == current then
			index = i
			break
		end
	end

	index = ((index - 1 + dir) % #list) + 1
	OpenSelector(list[index])
end

hook.Add("PlayerBindPress", "pdcity_WeaponSelectInput", function(ply, bind, pressed)
	if not pressed then return end
	bind = string.lower(bind)

	local slot = string.match(bind, "^slot(%d)$")
	if slot then
		HandleSlotPress(tonumber(slot) - 1)
		return true
	elseif bind == "invnext" then
		HandleCycle(1)
		return true
	elseif bind == "invprev" then
		HandleCycle(-1)
		return true
	elseif bind == "+attack" and selectorOpen then
		-- Left click confirms whatever's highlighted right now instead
		-- of firing the still-technically-active weapon - swallowed
		-- (returns true) so it doesn't ALSO shoot on the same click.
		ConfirmSelection()
		return true
	end
end)

hook.Add("Think", "pdcity_WeaponSelectTimeout", function()
	if selectorOpen and CurTime() > openUntil then
		CancelSelector()
	end
end)

-- If the active weapon changes some OTHER way (dropped, died, picked
-- something up that auto-switched), drop any stale highlight so a
-- leftover selector state doesn't linger pointing at something no
-- longer relevant.
hook.Add("PlayerSwitchWeapon", "pdcity_WeaponSelectResync", function(ply, old, new)
	if ply ~= LocalPlayer() then return end
	if selectorOpen and highlightWeapon == new then
		selectorOpen = false
		highlightWeapon = nil
	end
end)

hook.Add("HUDShouldDraw", "pdcity_HideStockWeaponSelection", function(name)
	if name == "CHudWeaponSelection" then return false end
end)

-- A handful of stock HL2 weapons don't have a usable SWEP.PrintName -
-- their nice name only exists in the ENGINE's own (now-hidden) overlay,
-- pulled from the weapon's native script file rather than anything
-- Lua can read. Named explicitly here rather than guessed at runtime;
-- anything not listed falls back to its class name, cleaned up.
local FRIENDLY_NAMES = {
	weapon_physcannon = "Gravity Gun",
	weapon_physgun = "Physics Gun",
	gmod_tool = "Toolgun",
	gmod_camera = "Camera",
	weapon_crowbar = "Crowbar",
	weapon_pistol = "Pistol",
	weapon_357 = "Revolver",
	weapon_smg1 = "SMG",
	weapon_ar2 = "Pulse Rifle",
	weapon_shotgun = "Shotgun",
	weapon_crossbow = "Crossbow",
	weapon_rpg = "RPG",
	weapon_frag = "Grenade",
	weapon_slam = "SLAM",
	weapon_bugbait = "Bugbait",
	weapon_stunstick = "Stun Stick",
	weapon_keys = "Keys",
}

-- Custom icons for specific weapon classes, used in the preview box
-- instead of the weapon's own WepSelectIcon. Drop a PNG anywhere under
-- this gamemode's own materials/ folder (it's already sent to clients
-- as part of the gamemode's content, same as everything else in here -
-- no separate resource.AddFile needed) and point a class at it below,
-- e.g.:
--   weapon_pdcity_cuffs = "pdcity/weapon_icons/cuffs.png",
-- Anything not listed here just keeps using its own WepSelectIcon.
local CUSTOM_ICONS = {
	-- weapon_class = "path/relative/to/materials/icon.png",
}

local iconMatCache = {}

local function GetCustomIconMaterial(class)
	if iconMatCache[class] ~= nil then
		return iconMatCache[class] or nil
	end

	local path = CUSTOM_ICONS[class]
	local mat = path and Material(path)
	iconMatCache[class] = (mat and not mat:IsError()) and mat or false
	return iconMatCache[class] or nil
end

local function GetWeaponLabel(wep)
	local class = wep:GetClass()
	if FRIENDLY_NAMES[class] then return string.upper(FRIENDLY_NAMES[class]) end

	local name = wep.PrintName
	if isstring(name) and name ~= "" then
		if string.sub(name, 1, 1) == "#" then name = language.GetPhrase(string.sub(name, 2)) end
		return string.upper(name)
	end

	-- Fallback: "weapon_pdcity_cuffs" -> "CUFFS", "weapon_ar2" -> "AR2"
	local cleaned = string.gsub(class, "^weapon_", "")
	cleaned = string.gsub(cleaned, "^pdcity_", "")
	cleaned = string.gsub(cleaned, "_", " ")
	return string.upper(cleaned)
end

--[[-------------------------------------------------------
	Drawing - centred at the top of the screen, one pill per slot 1-6
	(EMPTY ones too, dimmed, same as stock always showing the full row
	rather than only the slots you happen to have something in) - the
	CURRENT slot's pill also shows the highlighted weapon's name, with a
	bigger icon preview box underneath it. Fades in fast, holds, fades
	out over the last stretch of VISIBLE_HOLD - same shape stock's own fade
	uses.
---------------------------------------------------------]]

local PILL_H = 42
local PILL_GAP = 10
local EMPTY_PILL_W = 52
local PREVIEW_W, PREVIEW_H = 260, 200
local MAX_SLOT = 5 -- slots 0-5, shown as "1".."6"

-- A tighter, subtler shadow than the shared PDCity.DrawShadow (cl_theme.lua)
-- - that one's tuned for big panels/cards, too heavy at this row's
-- smaller scale. Two layers instead of five, and the radius barely
-- grows between them (a bigger radius delta per layer is what made the
-- stacked corners look rough/stepped rather than a smooth blur).
local function DrawTightShadow(x, y, w, h, radius)
	for i = 2, 1, -1 do
		local grow = i * 2
		draw.RoundedBox(radius + 1, x - grow / 2, y - grow / 2 + 2, w + grow, h + grow, Color(0, 0, 0, 12 - i * 3))
	end
end

hook.Add("HUDPaint", "pdcity_DrawWeaponSelection", function()
	if not selectorOpen then return end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() or not IsValid(highlightWeapon) then
		selectorOpen = false
		return
	end

	local remaining = math.Clamp((openUntil - CurTime()) / VISIBLE_HOLD, 0, 1)
	local lifeUsed = 1 - remaining
	local alpha = 255
	if lifeUsed < 0.15 then
		alpha = 255 * (lifeUsed / 0.15)
	elseif remaining < 0.3 then
		alpha = 255 * (remaining / 0.3)
	end

	local slots = {}
	for _, wep in ipairs(GetSortedWeapons()) do
		local s = wep:GetSlot()
		if s <= MAX_SLOT then
			slots[s] = slots[s] or {}
			table.insert(slots[s], wep)
		end
	end

	local highlightSlot = highlightWeapon:GetSlot()

	-- First pass: figure out each pill's width (and the row's total
	-- width) before drawing anything, so the whole row can be centred.
	surface.SetFont("PDCity_Heading")
	local pillWidths = {}
	local totalW = 0

	for s = 0, MAX_SLOT do
		local isCurrentSlot = (s == highlightSlot)
		local pillW

		if not slots[s] then
			pillW = EMPTY_PILL_W
		elseif isCurrentSlot then
			local label = (s + 1) .. "   " .. GetWeaponLabel(highlightWeapon)
			pillW = math.max(PILL_H, select(1, surface.GetTextSize(label)) + 28)
		else
			pillW = math.max(EMPTY_PILL_W, select(1, surface.GetTextSize(tostring(s + 1))) + 28)
		end

		pillWidths[s] = pillW
		totalW = totalW + pillW + (s < MAX_SLOT and PILL_GAP or 0)
	end

	local x = (ScrW() - totalW) / 2
	local y = 20

	for s = 0, MAX_SLOT do
		local hasWeapon = slots[s] ~= nil
		local isCurrentSlot = (s == highlightSlot)
		local pillW = pillWidths[s]

		local label = tostring(s + 1)
		if isCurrentSlot then label = label .. "   " .. GetWeaponLabel(highlightWeapon) end

		local bg = isCurrentSlot and PDCity.THEME.PanelHover or PDCity.THEME.Panel
		local textCol = hasWeapon and PDCity.THEME.Text or PDCity.THEME.TextDim
		local rowAlpha = hasWeapon and alpha or alpha * 0.55 -- empty slots read as present but inactive

		DrawTightShadow(x, y, pillW, PILL_H, 12)
		draw.RoundedBox(12, x, y, pillW, PILL_H, ColorAlpha(bg, rowAlpha))
		draw.SimpleText(label, "PDCity_Heading", x + 16, y + PILL_H / 2, ColorAlpha(textCol, rowAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		if isCurrentSlot then
			local py = y + PILL_H + PILL_GAP
			-- Centred UNDER this pill, not left-aligned to it - the pill
			-- itself is almost always narrower than the preview box.
			local previewX = x + (pillW - PREVIEW_W) / 2

			DrawTightShadow(previewX, py, PREVIEW_W, PREVIEW_H, 16)
			draw.RoundedBox(16, previewX, py, PREVIEW_W, PREVIEW_H, ColorAlpha(PDCity.THEME.Panel, alpha))

			local customIcon = GetCustomIconMaterial(highlightWeapon:GetClass())
			if customIcon then
				local pad = 24
				surface.SetDrawColor(255, 255, 255, alpha)
				surface.SetMaterial(customIcon)
				surface.DrawTexturedRect(previewX + pad, py + pad, PREVIEW_W - pad * 2, PREVIEW_H - pad * 2 - 34)
			elseif highlightWeapon.WepSelectIcon then
				local pad = 24
				surface.SetDrawColor(255, 255, 255, alpha)
				surface.SetTexture(highlightWeapon.WepSelectIcon)
				surface.DrawTexturedRect(previewX + pad, py + pad, PREVIEW_W - pad * 2, PREVIEW_H - pad * 2 - 34)
			end

			draw.SimpleText(GetWeaponLabel(highlightWeapon), "PDCity_Heading",
				previewX + PREVIEW_W / 2, py + PREVIEW_H - 20, ColorAlpha(PDCity.THEME.Text, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		x = x + pillW + PILL_GAP
	end
end)
