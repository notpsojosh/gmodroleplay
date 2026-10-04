--[[---------------------------------------------------------
	Which entity classes a normal player's physgun can pick up at all.

	Two tiers, deliberately not one list:

	  PDCity.PHYSGUN_ALWAYS_ALLOWED - hardcoded, not owner-editable. The
	  classes every prop a player spawns/buys/dupes/copies actually IS
	  (prop_physics and friends) - without this, the whitelist below
	  starting empty would mean nobody can move anything they just built
	  until the owner manually allows the single most common class on the
	  server. Players/staff still go through their own separate gates
	  further down GM:PhysgunPickup (shared.lua) - this tier only concerns
	  props.

	  PDCity.PHYSGUN_WHITELIST - owner-editable, starts empty, everything
	  else (map fixtures, NPCs, vehicles, any other entity class). Nothing
	  on this tier is grabbable until the owner explicitly adds it, either
	  from the F4 admin editor's "Physgun Whitelist" tab or by pointing the
	  Physgun Whitelist tool (entities/weapons/gmod_tool/stools/
	  pdcity_physgunwhitelist.lua) at it and left-clicking.

	Persisted/synced by core/sv_physgun_whitelist.lua, enforced in
	GM:PhysgunPickup (shared.lua). An entity with its own ENT:PhysgunPickup
	override (money printer, custom NPC, ...) is untouched either way -
	shared.lua defers to that override before this file is ever consulted.
-----------------------------------------------------------]]

PDCity.PHYSGUN_ALWAYS_ALLOWED = {
	["prop_physics"] = true,
	["prop_physics_multiplayer"] = true,
	["prop_ragdoll"] = true,
}

PDCity.PHYSGUN_WHITELIST = PDCity.PHYSGUN_WHITELIST or {}

function PDCity.IsPhysgunAllowed(ent)
	if not IsValid(ent) then return false end
	local class = ent:GetClass()

	if PDCity.PHYSGUN_ALWAYS_ALLOWED[class] then return true end
	return table.HasValue(PDCity.PHYSGUN_WHITELIST, class)
end

if CLIENT then

	net.Receive("pdcity_physgun_whitelist", function()
		local data = util.JSONToTable(net.ReadString() or "")
		if istable(data) then
			PDCity.PHYSGUN_WHITELIST = data
			hook.Run("PDCity_PhysgunWhitelistUpdated")
		end
	end)

end
