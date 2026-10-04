--[[---------------------------------------------------------
	Restores the stock "base" gamemode's GM:PlayerSpawn orchestration
	(see gamemodes/base/gamemode/player.lua). pdcity's own init.lua/cl_init.lua/
	shared.lua don't inherit from base/sandbox additively, so none of this
	ever ran - meaning player_manager.RunClass(pl, "Spawn") and the
	PlayerSetModel hook (which is what actually calls PLAYER:SetModel(),
	our random-default-model code) were never being invoked at all.
-----------------------------------------------------------]]

function GM:PlayerInitialSpawn(pl, transiton)
	pl:SetTeam(PDCity.DEFAULT_JOB)
end

function GM:PlayerSpawn(pl, transiton)

	pl:UnSpectate()

	-- This is the piece "base" gamemode doesn't do itself - it's sandbox's
	-- own GM:PlayerSpawn that assigns the class before deferring to base's.
	-- Without it, RunClass below has no class to look up and silently no-ops.
	player_manager.SetPlayerClass(pl, "player_sandbox")

	player_manager.OnPlayerSpawn(pl, transiton)
	player_manager.RunClass(pl, "Spawn")

	-- If we are in transition, do not touch player's weapons
	if (!transiton) then
		hook.Call("PlayerLoadout", GAMEMODE, pl)
	end

	-- Set player model
	hook.Call("PlayerSetModel", GAMEMODE, pl)

	pl:SetupHands()

end

function GM:PlayerSetModel(pl)
	player_manager.RunClass(pl, "SetModel")
end
