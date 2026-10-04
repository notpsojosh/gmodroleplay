--[[---------------------------------------------------------
	Countdown shown to a jailed player (core/sv_arrests.lua sets the two
	networked values this reads). Only the jailed player sees this - the
	NWBool/NWFloat are read straight off LocalPlayer(), not broadcast.
-----------------------------------------------------------]]

hook.Add("HUDPaint", "pdcity_JailCountdown", function()

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:GetNWBool("PDCity_IsJailed", false) then return end

	local remaining = math.max(0, ply:GetNWFloat("PDCity_JailEndTime", 0) - CurTime())
	local minutes = math.floor(remaining / 60)
	local seconds = math.floor(remaining % 60)
	local text = string.format("JAILED - %d:%02d", minutes, seconds)

	draw.SimpleTextOutlined(text, "PDCity_Title", ScrW() / 2, 80, Color(230, 90, 90),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 220))

end)
