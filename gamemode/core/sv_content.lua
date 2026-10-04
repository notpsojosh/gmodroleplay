--[[---------------------------------------------------------
	"!content" - anyone can use this, unlike most other chat commands in
	this gamemode. Tells the requesting player's own client to open the
	Workshop collection link (core/sh_content.lua) via a net message,
	since gui.OpenURL only makes sense client-side.

	Also handles showing the F1 menu automatically the first time
	someone joins, so nobody plays through a session full of missing
	models without ever finding out why.
-----------------------------------------------------------]]

util.AddNetworkString("PDCity_OpenContentLink")
util.AddNetworkString("pdcity_welcome")

-- No longer auto-fires on join - the mandatory character-select screen
-- (cl_character_select.lua) is now a full dashboard that folds this same
-- onboarding content (download filter check, step cards) in alongside
-- character creation, so a fresh join only ever sees ONE screen instead
-- of this one stacking on top of the character picker. "!welcome"/
-- "!motd" below still open the standalone version any time after that.
local function SendWelcomeChatHint(ply)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Welcome! Press F1 any time for help, or type !content to get the workshop collection.")
end

hook.Add("PDCity_CharacterSelected", "pdcity_WelcomeChatHint", function(ply)
	SendWelcomeChatHint(ply)
end)

-- Priority -1 (HOOK_HIGH): ULib's hook system clamps priorities to
-- [-2, 2] and IGNORES return values at the +/-2 "monitor" levels, so
-- -1 is the earliest level where our `return ""` still suppresses the
-- message. ULib's own say-command processor also runs at -1, and order
-- within one priority is undefined - so rather than racing it for
-- "!motd", ULX's registration of that command is deleted below and
-- this hook becomes its only handler.
hook.Add("PlayerSay", "pdcity_WelcomeChatCommand", function(ply, text)
	local cmd = string.lower(string.Trim(text))
	if cmd ~= "!welcome" and cmd ~= "!motd" then return end

	net.Start("pdcity_welcome")
	net.Send(ply)

	return ""
end, -1)

-- Deferred: ULX builds its say-command table as its modules load, so
-- stripping "!motd" too early would just get re-registered over.
hook.Add("InitPostEntity", "pdcity_StripUlxMotd", function()
	timer.Simple(5, function()
		if ULib and ULib.sayCmds then
			ULib.sayCmds["!motd"] = nil
			ULib.sayCmds["!motd "] = nil
		end
	end)
end)

hook.Add("PlayerSay", "pdcity_ContentChatCommand", function(ply, text)

	if string.lower(string.Trim(text)) ~= "!content" then return end

	net.Start("PDCity_OpenContentLink")
	net.Send(ply)

	return ""

end)
