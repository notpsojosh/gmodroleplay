--[[---------------------------------------------------------
	Lets the owner/staff pick up and move other players with the
	physgun, same as a prop (permission check + initial Freeze() live in
	GM:PhysgunPickup, shared.lua). This file handles the rest of the
	lifecycle:

	  - GM:OnPhysgunFreeze / GM:OnPhysgunReload didn't exist ANYWHERE in
	    this gamemode before this file - meaning right-click "freeze"
	    and reload's "unfreeze everything I've frozen" have silently
	    never worked for PROPS either, the whole project, for the same
	    reason spawning/tools kept turning up missing this session:
	    gamemode.Call requires GM[event] to exist. Restored here
	    verbatim from gamemodes/base/gamemode/player.lua, then extended
	    to also cover a physgunned player.
	  - PhysgunDrop: releases a held player's Freeze() UNLESS they were
	    explicitly frozen (right-click) - a frozen prop stays put after
	    being dropped, so a frozen player should too - or unless cuffing/
	    jailing/tasing already owns their freeze state.

	Player-local state:
	  ply.pdcity_PhysgunFrozen    - explicitly frozen via right-click
	  ply.pdcity_PhysgunFrozenBy  - who froze them (kept for logging and
	                                inspection; reload no longer filters
	                                on it - see its own note below)
-----------------------------------------------------------]]

function GM:OnPhysgunFreeze(weapon, phys, ent, ply)

	if not IsValid(ent) then return end

	if ent:IsPlayer() then
		ent.pdcity_PhysgunFrozen = true
		ent.pdcity_PhysgunFrozenBy = ply
		PDCity.SetPlayerFrozen(ent, true)
		PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") physgun-froze "
			.. ent:Nick() .. " (" .. ent:SteamID() .. ")")
		return
	end

	-- Stock base gamemode behaviour for everything else (props/ragdolls).
	if not IsValid(phys) then return end -- non-vphysics entity, nothing to freeze
	if not phys:IsMoveable() then return end -- already frozen
	if ent:GetUnFreezable() then return end

	phys:EnableMotion(false)
	ply:AddFrozenPhysicsObject(ent, phys)

end

--[[---------------------------------------------------------
	Reload = unfreeze. For PROPS this is stock behaviour and stays scoped
	to "everything I personally froze" (ply:PhysgunUnfreeze below).

	For PLAYERS it deliberately isn't: it unfreezes ANY frozen player,
	not just ones this staff member froze themselves. A player left stuck
	frozen is stuck for good otherwise - the admin who froze them may have
	disconnected, or the freeze may have come from something else entirely -
	and "find the exact person who froze them and ask them to reload"
	isn't a real recovery path. Reload is the one obvious "get them
	moving again" tool, so it works on whoever's actually frozen.

	Freezes another system actively owns (cuffed, jailed, tased) are still
	left alone - those aren't stuck, they're mid-mechanic, and each one
	releases its own freeze when it's finished.
-----------------------------------------------------------]]
function GM:OnPhysgunReload(weapon, ply)

	for _, target in ipairs(player.GetAll()) do
		if target.pdcity_IsCuffed or target.pdcity_IsJailed or target.pdcity_IsStunned then
			-- another system owns this freeze and will release it itself
		elseif PDCity.IsPlayerFrozen(target) then
			target.pdcity_PhysgunFrozen = nil
			target.pdcity_PhysgunFrozenBy = nil
			PDCity.SetPlayerFrozen(target, false)

			if target ~= ply then
				PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") physgun-unfroze "
					.. target:Nick() .. " (" .. target:SteamID() .. ")")
			end
		end
	end

	ply:PhysgunUnfreeze() -- stock behaviour: unfreeze every prop this player has frozen

end

hook.Add("PhysgunDrop", "pdcity_ReleaseDroppedPlayer", function(ply, ent)

	if not IsValid(ent) or not ent:IsPlayer() then return end
	if ent.pdcity_PhysgunFrozen then return end -- stays frozen, same as a frozen prop staying put after drop
	if ent.pdcity_IsCuffed or ent.pdcity_IsJailed or ent.pdcity_IsStunned then return end -- another system owns the freeze

	PDCity.SetPlayerFrozen(ent, false)

end)
