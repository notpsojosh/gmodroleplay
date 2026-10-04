--[[---------------------------------------------------------
	Permission helpers. ULX/UCL (data/ulib/users.txt) stays the source of
	truth for usergroups; this just gives the gamemode a single place to
	ask "is this player staff / the owner" on both server and client
	(usergroups are networked, so these work in both realms).

	Staff = moderator, admin, superadmin or owner usergroup. "operator"
	is ULX's built-in step above user, counted as staff too so a future
	trial-mod group works without touching this file.
-----------------------------------------------------------]]

-- SteamIDs with owner powers regardless of usergroup (F1 Site Admin,
-- Catalogue, etc.). Empty by default - add your own SteamID (the
-- STEAM_0:X:XXXXXXXX form, shown by typing `status` in console), or
-- give yourself the "owner" usergroup through ULX instead.
PDCity.OWNER_STEAMIDS = {
	-- ["STEAM_0:1:12345678"] = true,
}

local STAFF_GROUPS = {
	["operator"] = true,		
	["moderator"] = true,
	["admin"] = true,
	["superadmin"] = true,
	["owner"] = true,
}

function PDCity.IsOwner(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if PDCity.OWNER_STEAMIDS[ply:SteamID()] then return true end
	return ply:GetUserGroup() == "owner"
end

function PDCity.IsStaff(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if PDCity.IsOwner(ply) then return true end
	return STAFF_GROUPS[ply:GetUserGroup()] == true
end

local ADMIN_PLUS_GROUPS = {
	["admin"] = true,
	["superadmin"] = true,
	["owner"] = true,
}

-- "admin+" specifically - admin, superadmin, or owner, deliberately
-- excluding moderator/operator (both count as PDCity.IsStaff, but not
-- this). Used where something was asked for as "admin and above" rather
-- than "any staff", e.g. !forcename/!unforce (core/sv_rpname.lua).
function PDCity.IsAdminPlus(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if PDCity.IsOwner(ply) then return true end
	return ADMIN_PLUS_GROUPS[ply:GetUserGroup()] == true
end

-- Owner or superadmin - "can bypass normal spawn restrictions entirely".
-- Shared (not server-only) because the Prop Filter tool
-- (entities/weapons/gmod_tool/stools/pdcity_propfilter.lua) predicts its
-- click clientside too and needs the exact same answer both realms give;
-- core/sv_restrictions.lua's Q-menu/prop-whitelist gates use this too, so
-- there's one definition of "who this doesn't apply to" everywhere.
function PDCity.CanSpawnFromMenu(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	return PDCity.IsOwner(ply) or ply:IsSuperAdmin()
end

-- Owner or superadmin - one tier above PDCity.IsAdminPlus (which also
-- lets plain admin through). The Staff Menu's player-punishment actions
-- (ban/gag/mute/jail - cl_staff_menu.lua, core/sv_staff_menu.lua) are
-- gated at this level; setting someone's actual staff ROLE from that
-- same menu is gated tighter still, at PDCity.IsOwner alone. Same
-- effective check as PDCity.CanSpawnFromMenu, named for what THIS is
-- used for rather than reusing that name out of context.
function PDCity.IsSuperAdminPlus(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	return PDCity.IsOwner(ply) or ply:IsSuperAdmin()
end
