--[[---------------------------------------------------------
	Client-side thirdperson state, toggled by "!tpp" (see
	core/sv_thirdperson.lua). The actual camera offset and player-model
	visibility live in PLAYER:CalcView / PLAYER:ShouldDrawLocal
	(player_class/player_sandbox.lua) - this file just tracks the on/off
	state and lets the player know it changed.

	Deliberately not gated by sv_cheats or any admin check: this only
	ever changes what the local client renders for itself, it can't
	affect aiming (CalcView doesn't touch EyeAngles/aim traces) or any
	other player's game, so there's nothing here that needs restricting.
-----------------------------------------------------------]]

PDCity.ThirdpersonEnabled = false

net.Receive("PDCity_ToggleThirdperson", function()
	PDCity.ThirdpersonEnabled = not PDCity.ThirdpersonEnabled
	PDCity.ShowToast("Thirdperson " .. (PDCity.ThirdpersonEnabled and "enabled" or "disabled") .. ".")
end)
