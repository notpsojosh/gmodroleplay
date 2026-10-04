--[[---------------------------------------------------------
	General staff chat-commands, plus the perks that come with staff
	rank ("!unarrest" stays in core/sv_arrests.lua since it's
	arrest-specific).

	All gated the same way as noclip: PDCity.IsStaff (core/sh_permissions.lua,
	moderator rank or above) - a staff-rank perk, not tied to any
	particular job/team.
-----------------------------------------------------------]]

--[[---------------------------------------------------------
	Staff are permanently invulnerable.

	PlayerShouldTakeDamage rather than Player:GodEnable() because it's
	stateless - there's nothing to remember to switch back off when
	they respawn or reconnect, so godmode can never get stuck on for
	someone who's since lost staff rank.

	Covers every damage source including falls: core/sv_fall_damage.lua
	only returns an amount from GetFallDamage, and the engine then
	applies that through the normal damage path, which this gates.
-----------------------------------------------------------]]

hook.Add("PlayerShouldTakeDamage", "pdcity_StaffGodmode", function(ply)
	if PDCity.IsStaff(ply) then return false end
end)

--[[---------------------------------------------------------
	"!hide" / "!unhide" - staff only.

	Hides the model, its shadow and every carried weapon, and makes the
	player non-solid so nobody can walk into an invisible wall. The
	state is cleared on spawn and on leaving the staff job, so it's not
	possible to end up permanently invisible as a civilian.
-----------------------------------------------------------]]

function PDCity.SetPlayerHidden(ply, hidden)

	ply.pdcity_Hidden = hidden or nil

	ply:SetNoDraw(hidden)
	ply:DrawShadow(not hidden)
	ply:SetNotSolid(hidden)

	-- Weapons are drawn as their own entities, so hiding the player
	-- alone leaves a gun floating in mid-air.
	for _, wep in ipairs(ply:GetWeapons()) do
		if IsValid(wep) then wep:SetNoDraw(hidden) end
	end

end

hook.Add("PlayerSay", "pdcity_HideChatCommands", function(ply, text)

	local cmd = string.lower(string.Trim(text))
	if cmd ~= "!hide" and cmd ~= "!unhide" then return end

	if not PDCity.IsStaff(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You must be staff to use this.")
		return ""
	end

	local hide = (cmd == "!hide")
	PDCity.SetPlayerHidden(ply, hide)
	ply:ChatPrint(hide
		and "[" .. PDCity.BRAND_TAG .. "] You are now hidden. Use !unhide to reappear."
		or "[" .. PDCity.BRAND_TAG .. "] You are visible again.")

	return ""

end)

-- Spawning re-creates the weapons (so their NoDraw is lost anyway) and
-- is the natural point to drop the state entirely.
hook.Add("PlayerSpawn", "pdcity_ClearHiddenOnSpawn", function(ply)
	if ply.pdcity_Hidden then PDCity.SetPlayerHidden(ply, false) end
end)

-- Cleans up every custom state a bare Player:Spawn() would otherwise
-- leave stale (a pending jail-release timer, a lingering Freeze(), a
-- dangling officer/target reference) before actually respawning them.
local function ForceRespawn(target)

	if target.pdcity_IsJailed then
		PDCity.ReleaseFromJail(target) -- clears jail state and already calls target:Spawn()
		return
	end

	if target.pdcity_IsCuffed then
		PDCity.UncuffPlayer(target) -- clears cuff state, restores job weapons, unfreezes
	end

	target.pdcity_BeingCuffed = nil
	target.pdcity_IsStunned = nil
	target.pdcity_PhysgunFrozen = nil
	target.pdcity_PhysgunFrozenBy = nil
	PDCity.SetPlayerFrozen(target, false)

	target:Spawn()

end

hook.Add("PlayerSay", "pdcity_RespawnChatCommand", function(ply, text)

	local args = string.Explode(" ", string.Trim(text))
	if string.lower(args[1] or "") ~= "!respawn" then return end
	table.remove(args, 1)

	if not PDCity.IsStaff(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You must be staff to use this.")
		return ""
	end

	local identifier = args[1]
	if not identifier then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Usage: !respawn <name or steamid>")
		return ""
	end

	local target = PDCity.FindPlayerByIdentifier(identifier)
	if not IsValid(target) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No matching player found.")
		return ""
	end

	ForceRespawn(target)

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") force-respawned "
		.. target:Nick() .. " (" .. target:SteamID() .. ")")

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Respawned " .. PDCity.GetDisplayName(target) .. ".")
	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(ply) .. " (staff) force-respawned you.")

	return ""

end)
