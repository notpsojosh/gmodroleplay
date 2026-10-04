--[[---------------------------------------------------------
	Thirdperson toggle: "!tpp" in chat. Purely a local rendering choice
	(see PLAYER:CalcView / PLAYER:ShouldDrawLocal in
	player_class/player_sandbox.lua), so the server's only job is to
	catch the chat command before it's broadcast (matching the pattern
	used for !dropmoney/etc in core/sv_money.lua) and tell that one
	client to flip its own state - no shared/validated data involved.
-----------------------------------------------------------]]

util.AddNetworkString("PDCity_ToggleThirdperson")

hook.Add("PlayerSay", "pdcity_ThirdpersonChatCommand", function(ply, text)

	if string.lower(string.Trim(text)) ~= "!tpp" then return end

	net.Start("PDCity_ToggleThirdperson")
	net.Send(ply)

	return ""

end)
