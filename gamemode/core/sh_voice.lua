--[[---------------------------------------------------------
	Proximity voice tuning, shared so the server's hard cutoff
	(core/sv_voice.lua) and the client's volume fade + speaking icon
	(cl_voice.lua) always agree on where "out of range" is - keeping
	the numbers in one place means the fade can never still be audible
	past the point the server has already stopped sending the audio
	at all.
-----------------------------------------------------------]]

PDCity.VOICE_FADE_START = 375 -- full volume up to here
PDCity.VOICE_HEAR_DISTANCE = 750 -- not sent to the listener at all beyond here

local HEAR_DISTANCE_SQR = PDCity.VOICE_HEAR_DISTANCE * PDCity.VOICE_HEAR_DISTANCE
local sv_alltalk = GetConVar("sv_alltalk") -- FCVAR_REPLICATED, so this reads correctly on the client too

--[[---------------------------------------------------------
	The actual hearing rule, shared so it's defined in exactly one
	place: core/sv_voice.lua uses it to decide what really gets sent,
	and cl_voice.lua's "who can hear you" list uses the SAME function
	to decide what to display - so the list can never claim someone
	can hear you when the server would actually disagree, or vice
	versa, since there's only one predicate to get out of sync.

	Returns the same two values as GM:PlayerCanHearPlayersVoice: can
	hear at all, and whether it's positional.
-----------------------------------------------------------]]
function PDCity.CanHearVoice(listener, talker)

	if not IsValid(listener) or not IsValid(talker) then return false end
	if listener == talker then return false end

	-- Staff Menu gag (core/sv_staff_menu.lua) - a plain Lua field set
	-- server-side wouldn't exist on the client at all, and this function
	-- runs in both realms (cl_voice.lua's "who can hear you" list uses it
	-- too), so this has to be the networked flag, not ply.pdcity_Gagged.
	if talker:GetNWBool("PDCity_Gagged", false) then return false end

	local alltalk = sv_alltalk:GetInt()
	if alltalk >= 1 then return true, alltalk == 2 end

	if listener:GetPos():DistToSqr(talker:GetPos()) > HEAR_DISTANCE_SQR then
		return false
	end

	return true, true

end
