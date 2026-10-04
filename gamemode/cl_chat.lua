--[[---------------------------------------------------------
	Renders the chat kinds routed by core/sv_chat.lua. The server has
	already decided who receives each message - this only decides what
	it looks like in the chat box.
-----------------------------------------------------------]]

-- Kind numbers - must match the CHAT_* values in core/sv_chat.lua
-- (that file is server-only, so the client can't read them from there).
local CHAT_LOCAL = 1
local CHAT_OOC = 2
local CHAT_PM = 3
local CHAT_ADVERT = 4
local CHAT_DARKWEB = 5

local COL_TEXT = Color(255, 255, 255)
local COL_OOC = Color(120, 160, 220)
local COL_PM = Color(200, 120, 220)
local COL_ADVERT = Color(255, 210, 60)
local COL_DARKWEB = Color(190, 60, 60)
local COL_DIM = Color(150, 155, 165)

net.Receive("pdcity_chat", function()

	local kind = net.ReadUInt(4)
	local sender = net.ReadEntity()
	local text = net.ReadString()
	local extra = net.ReadString()

	-- PDCity.GetDisplayName (core/sh_rpname.lua) prefers the RP name
	-- (/name /rpname /n) over the real Steam nick when one's set.
	local name = IsValid(sender) and PDCity.GetDisplayName(sender) or "(disconnected)"
	local teamCol = IsValid(sender) and team.GetColor(sender:Team()) or COL_DIM

	if kind == CHAT_LOCAL then
		chat.AddText(teamCol, name, COL_TEXT, ": " .. text)

	elseif kind == CHAT_OOC then
		chat.AddText(COL_OOC, "[OOC] ", teamCol, name, COL_TEXT, ": " .. text)

	elseif kind == CHAT_PM then
		if IsValid(sender) and sender == LocalPlayer() then
			-- Our own copy: show who it went to ("extra" carries the
			-- recipient's name), so a sent PM reads back sensibly.
			chat.AddText(COL_PM, "[PM to " .. extra .. "] ", COL_TEXT, text)
		else
			chat.AddText(COL_PM, "[PM from " .. name .. "] ", COL_TEXT, text)
			chat.AddText(COL_DIM, "  (/r <message> to reply)")
		end
		surface.PlaySound("friends/message.wav")

	elseif kind == CHAT_ADVERT then
		chat.AddText(COL_ADVERT, "[ADVERT] " .. name .. ": " .. text)

	elseif kind == CHAT_DARKWEB then
		chat.AddText(COL_DARKWEB, "[DARK WEB] ", COL_DIM, "???", COL_TEXT, ": " .. text)
	end

end)
