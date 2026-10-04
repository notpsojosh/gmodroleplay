--[[---------------------------------------------------------
	Server side of the toast notification system (cl_toast.lua). Every
	"[" .. PDCity.BRAND_TAG .. "] ..." message the server sends a player - salary, RP name
	changes, admin action feedback, permission denials, all of it - was
	previously Player:ChatPrint, which drops straight into the real
	chatbox alongside actual player-typed chat. Asked to keep the
	chatbox for player-sent stuff only, so those need to land somewhere
	else instead.

	Rather than touching the ~200 existing ChatPrint call sites across
	the gamemode one by one, Player:ChatPrint itself is overridden here
	to redirect to a toast - every EXISTING call site (and any future
	one) is covered automatically. This only runs server-side: the
	engine's ChatPrint only ever does anything visible when called on a
	player from the server anyway (a client calling it on anyone but
	itself is already a no-op), so there's nothing to catch client-side.

	The genuine chat system (core/sv_chat.lua's "pdcity_chat" net
	message, rendered by cl_chat.lua) is untouched - it never went
	through ChatPrint to begin with, so it isn't affected by this at all.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_toast")

function PDCity.Notify(ply, text)
	if not IsValid(ply) or not ply:IsPlayer() or not isstring(text) or text == "" then return end

	net.Start("pdcity_toast")
		net.WriteString(text)
	net.Send(ply)
end

local PLAYER = FindMetaTable("Player")
local EngineChatPrint = PLAYER.ChatPrint

function PLAYER:ChatPrint(text)
	PDCity.Notify(self, text)
end

-- Kept for anything that genuinely needs the real engine chat line
-- (none of this gamemode's own code does) rather than a toast.
function PDCity.EngineChatPrint(ply, text)
	EngineChatPrint(ply, text)
end
