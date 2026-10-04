--[[---------------------------------------------------------
	These are the stock sandbox gamemode defaults for the various
	PlayerSpawn*/PlayerSpawned* hooks (see gamemodes/sandbox/gamemode/player.lua).

	pdcity defines its own init.lua/cl_init.lua/shared.lua rather than
	deriving them additively from sandbox, which means sandbox's own
	gamemode/player.lua (included from sandbox's init.lua) never actually
	runs for this gamemode. gamemode.Call() only invokes hook.Add hooks
	(like Falco's Prop Protection's) for an event if GAMEMODE[event] is
	already defined - so without these, every spawn attempt silently
	returned nil (treated as "blocked"), regardless of what FPP or anything
	else had to say about it.
-----------------------------------------------------------]]

function GM:PlayerSpawnObject( ply, model, skin )
	return true
end

function GM:CanPlayerUnfreeze( ply, entity, physobject )

	if ( entity:GetPersistent() and GetConVarString( "sbox_persist" ):Trim() ~= "" ) then return false end

	return true
end

local function LimitReachedProcess( ply, str )

	if ( !IsValid( ply ) ) then return true end

	return ply:CheckLimit( str )

end

function GM:PlayerSpawnRagdoll( ply, model )
	return LimitReachedProcess( ply, "ragdolls" )
end

function GM:PlayerSpawnEffect( ply, model )
	return LimitReachedProcess( ply, "effects" )
end

function GM:PlayerSpawnSWEP( ply, wname, wtable )
	return LimitReachedProcess( ply, "sents" )
end

function GM:PlayerGiveSWEP( ply, wname, wtable )
	return true
end

function GM:PlayerSpawnSENT( ply, name )
	return LimitReachedProcess( ply, "sents" )
end

function GM:PlayerSpawnNPC( ply, npc_type, equipment )
	return LimitReachedProcess( ply, "npcs" )
end

-- This was missing entirely: commands.lua fires it via gamemode.Call,
-- which silently no-ops when the GM function doesn't exist - so props
-- were never counted (breaking the 75 limit and the HUD counter) and
-- PlayerSpawnedProp hook.Add hooks (FPP, our logging) never ran.
-- Frozen by default, same as holding a prop with the physgun and letting
-- go without unfreezing - EnableMotion(false) is exactly what the physgun
-- itself does to freeze, so this is recognised/unfreezable the normal way
-- (physgun left-click, or the "unfreeze all" tool) without any extra
-- bookkeeping on our end.
--
-- Tagged PDCityBuildProp so core/sv_prop_ghost_unfrozen.lua knows to
-- watch it - if it's ever unfrozen (by any means), that file ghosts it
-- against players the same way holding it with the physgun already does,
-- so an unfrozen prop can't be used to trap/crush someone.
function GM:PlayerSpawnedProp( ply, model, ent )
	ply:AddCount( "props", ent )

	ent.PDCityBuildProp = true

	local phys = ent:GetPhysicsObject()
	if IsValid( phys ) then
		phys:EnableMotion( false )
		phys:Sleep()
	end
end

function GM:PlayerSpawnedRagdoll( ply, model, ent )
	ply:AddCount( "ragdolls", ent )
end

function GM:PlayerSpawnedEffect( ply, model, ent )
	ply:AddCount( "effects", ent )
end

function GM:PlayerSpawnedNPC( ply, ent )
	ply:AddCount( "npcs", ent )
end

function GM:PlayerSpawnedSENT( ply, ent )
	ply:AddCount( "sents", ent )
end

function GM:PlayerSpawnedSWEP( ply, ent )
	-- This is on purpose, matches stock sandbox behaviour
	ply:AddCount( "sents", ent )
end

function GM:PlayerButtonDown( ply, btn )
	numpad.Activate( ply, btn )
end

function GM:PlayerButtonUp( ply, btn )
	numpad.Deactivate( ply, btn )
end
