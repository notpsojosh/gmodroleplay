--[[---------------------------------------------------------
	HUD indicator for the weapon safety catch (core/sh_weapon_safety.lua).
	Reads the NWBool the server sets on the weapon itself, so it's
	correct for whatever gun is currently in hand without needing any
	per-weapon-base support.
-----------------------------------------------------------]]

hook.Add("HUDPaint", "pdcity_WeaponSafetyIndicator", function()

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or not wep:GetNWBool("PDCity_Safety", false) then return end

	draw.SimpleTextOutlined("SAFETY ON", "PDCity_Heading", ScrW() / 2, ScrH() - 120,
		Color(230, 170, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 220))

end)
