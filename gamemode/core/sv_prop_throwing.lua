--[[---------------------------------------------------------
	Prevents props from being used as thrown projectiles.
	As soon as the physgun releases an entity, all velocity and
	angular velocity on every physics object it has is zeroed out,
	so no momentum carries over from swinging/tossing it.
-----------------------------------------------------------]]

local function KillVelocity( ent )

	if ( !IsValid( ent ) ) then return end

	local count = ent:GetPhysicsObjectCount()
	for i = 0, count - 1 do

		local phys = ent:GetPhysicsObjectNum( i )
		if ( IsValid( phys ) ) then
			phys:SetVelocity( vector_origin )
			phys:SetAngleVelocity( vector_origin )
		end

	end

end

hook.Add( "PhysgunDrop", "pdcity_NoPropThrow", function( ply, ent )
	if ( IsValid( ent ) and ent:IsPlayer() ) then return end -- players are handled by core/sv_physgun_players.lua
	KillVelocity( ent )
end )

--[[---------------------------------------------------------
	Prevents "prop boosting" - wedging a held prop against a wall or
	the floor and using the physgun to shove it into yourself, which
	the engine resolves by pushing the player out of the way.

	While an entity is held by the physgun, it's switched to a
	collision group that still collides with world geometry (so it
	doesn't clip through floors/walls) but ignores players entirely.
	Normal collision is restored the instant it's dropped.
-----------------------------------------------------------]]

hook.Add( "PhysgunPickup", "pdcity_GhostHeldProps", function( ply, ent )

	if ( !IsValid( ent ) ) then return end
	if ( ent:IsPlayer() ) then return end -- would break how players collide with the world/each other

	-- This hook runs BEFORE GM:PhysgunPickup (where an entity's own
	-- ENT:PhysgunPickup veto is honoured), so it fires even for entities
	-- that ultimately refuse the grab (money printers). If the grab is
	-- denied, no hold is established and PhysgunDrop never fires - which
	-- is the only thing that restores collision - so ghosting here would
	-- strand the entity in the DEBRIS group (no player collision) for
	-- good. Skip anything that vetoes its own pickup.
	if ( ent.PhysgunPickup and ent:PhysgunPickup( ply ) == false ) then return end

	ent.pdcity_OldCollisionGroup = ent:GetCollisionGroup()
	ent:SetCollisionGroup( COLLISION_GROUP_DEBRIS )

end )

hook.Add( "PhysgunDrop", "pdcity_RestorePropCollision", function( ply, ent )

	if ( !IsValid( ent ) ) then return end
	if ( ent.pdcity_OldCollisionGroup == nil ) then return end

	ent:SetCollisionGroup( ent.pdcity_OldCollisionGroup )
	ent.pdcity_OldCollisionGroup = nil

end )
