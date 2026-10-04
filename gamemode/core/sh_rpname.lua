--[[---------------------------------------------------------
	The one place "what name do we actually show for this player" is
	decided - shared so every UI (chat, scoreboard, ...) agrees, rather
	than each one re-implementing "RP name if set, else Steam nick"
	slightly differently. Actually setting/validating/rate-limiting an RP
	name is server-only (core/sv_rpname.lua); this just reads whatever
	NWString that file already syncs.
-----------------------------------------------------------]]

function PDCity.GetDisplayName(ply)
	if not IsValid(ply) then return "" end
	local name = ply:GetNWString("PDCity_RPName", "")
	return name ~= "" and name or ply:Nick()
end

-- The "Staff on Duty" character slot's identity - shared because both
-- realms need the exact same slot key: the server (core/sv_accounts.lua
-- defines/enforces it, core/sv_characters.lua and core/sv_rpname.lua
-- guard against renaming/deleting/reskinning it) and the client
-- (cl_character_select.lua checks a lane's Slot against this to hide its
-- Edit/Rename/Choose Model/Delete options entirely).
PDCity.STAFF_SLOT = "STAFF"
PDCity.STAFF_SLOT_NAME = "Staff on Duty"
PDCity.STAFF_SLOT_MODEL = "models/player/combine_super_soldier.mdl"
