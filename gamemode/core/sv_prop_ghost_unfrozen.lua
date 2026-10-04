--[[---------------------------------------------------------
	Any player-spawned prop (core/sv_spawn_defaults.lua tags it
	PDCityBuildProp, and freezes it on spawn) that ends up unfrozen -
	however that happens: the physgun's own unfreeze, the Freeze tool,
	anything else - gets its collision switched to ignore players, same
	as core/sv_prop_throwing.lua already does for the entire time a prop
	is held with the physgun. An unfrozen prop is a mobile one, and a
	mobile prop pressed against a player is exactly the "prop boosting"/
	trapping abuse that file already exists to prevent while held; this
	closes the same hole for the rest of an unfrozen prop's life, not
	just the moment it's in a physgun's grip.

	Polled rather than hooked to one specific "unfreeze" trigger - there
	isn't a single reliable hook for every way a prop's motion can end up
	re-enabled, and the point is to catch it "somehow" happening, not
	just the one obvious path.

	Skips anything currently held (ent.pdcity_OldCollisionGroup ~= nil) -
	sv_prop_throwing.lua already owns the collision group for the
	duration of a hold and restores it correctly on drop; touching it
	here too would fight that restore.
-----------------------------------------------------------]]

local WATCH_INTERVAL = 1

local function SyncGhostState(ent)
	if ent.pdcity_OldCollisionGroup ~= nil then return end -- held; sv_prop_throwing.lua owns this right now

	local phys = ent:GetPhysicsObject()
	if not IsValid(phys) then return end

	local frozen = not phys:IsMotionEnabled()

	if frozen then
		if ent.PDCityUnfrozenGhosted then
			ent:SetCollisionGroup(ent.PDCityPreGhostCollisionGroup or COLLISION_GROUP_NONE)
			ent.PDCityUnfrozenGhosted = nil
			ent.PDCityPreGhostCollisionGroup = nil
		end
	else
		if not ent.PDCityUnfrozenGhosted then
			ent.PDCityPreGhostCollisionGroup = ent:GetCollisionGroup()
			ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			ent.PDCityUnfrozenGhosted = true
		end
	end
end

timer.Create("pdcity_UnfrozenPropGhostWatchdog", WATCH_INTERVAL, 0, function()
	for _, ent in ipairs(ents.FindByClass("prop_physics")) do
		if ent.PDCityBuildProp and IsValid(ent) then
			SyncGhostState(ent)
		end
	end
end)
