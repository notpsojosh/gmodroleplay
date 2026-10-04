--[[---------------------------------------------------------
	The gravity gun (weapon_physcannon, given to every job automatically -
	core/sv_jobs.lua's own GiveLoadout call) should still grab, hold, and
	punt objects normally - it just shouldn't be able to hurt anyone or
	break anything by doing it.

	Two checks, since a single one misses real cases:
	  DMG_PHYSGUN         - the damage-type bit the engine itself tags a
	                        punt's impact with. Covers a punted object
	                        hitting a player/NPC directly, and a
	                        breakable prop (prop_physics with health,
	                        func_breakable) shattering from that same
	                        impact - both route through this same
	                        EntityTakeDamage dispatch, not just players.
	  Attacker's active weapon - a secondary check for anything the
	                        engine's own DMG_PHYSGUN tagging doesn't
	                        catch (e.g. some prop-on-prop physics
	                        impacts attribute differently) - if whoever's
	                        credited as the attacker currently has the
	                        gravity gun equipped, that's close enough to
	                        certainly the same swing.

	Not a full weapon replacement (see this session's own discussion of
	why that's a much bigger, riskier undertaking for stock C++ weapons) -
	grabbing/punting itself is untouched, only the damage it would have
	dealt is zeroed.
-----------------------------------------------------------]]

local function IsFromGravityGun(dmginfo)
	if dmginfo:IsDamageType(DMG_PHYSGUN) then return true end

	local attacker = dmginfo:GetAttacker()
	if IsValid(attacker) and attacker:IsPlayer() then
		local wep = attacker:GetActiveWeapon()
		if IsValid(wep) and wep:GetClass() == "weapon_physcannon" then return true end
	end

	return false
end

hook.Add("EntityTakeDamage", "pdcity_NoGravityGunDamage", function(target, dmginfo)
	if IsFromGravityGun(dmginfo) then
		dmginfo:SetDamage(0)
		return true
	end
end)
