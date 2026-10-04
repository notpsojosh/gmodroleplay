--[[---------------------------------------------------------
	Owner-only tool for setting BOTH of PD City's custom spawn points
	(core/sv_spawn_point.lua) - which one Left Click sets depends on the
	"Set the character spawn instead" checkbox below:

	  Unchecked (default) - the WAITING spawn, where a player sits while
	                         the mandatory character selection screen has
	                         them frozen (core/sv_characters.lua).
	  Checked             - the CHARACTER spawn, where they actually
	                         appear once they've picked one - the real
	                         gameplay spawn, which can be anywhere else
	                         on the map entirely.

	  Left click   - set the currently-toggled spawn point to where
	                 you're aiming, facing the direction you're facing

	Until either has been used at least once on a given map, players use
	that map's own info_player_start entities instead for that one.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_spawnpoint.name"

TOOL.Information = {
	{ name = "left" },
}

TOOL.ClientConVar = {
	["mode"] = "0", -- 0 = waiting spawn, 1 = character (post-selection) spawn
}

if CLIENT then
	language.Add("tool.pdcity_spawnpoint.name", "Default Spawn (Owner)")
	language.Add("tool.pdcity_spawnpoint.desc", "Set where players spawn/respawn by default on this map")
	language.Add("tool.pdcity_spawnpoint.left", "Set the currently-toggled spawn point here")
end

local function CheckOwner(tool)
	local ply = tool:GetOwner()
	if PDCity.IsOwner(ply) then return true end
	if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can use the Default Spawn tool.") end
	return false
end

function TOOL:LeftClick(trace)
	if not CheckOwner(self) then return false end
	if not trace.Hit then return false end
	if CLIENT then return true end

	local ply = self:GetOwner()
	local pos = trace.HitPos + Vector(0, 0, 4)
	local yaw = ply:EyeAngles().y

	if self:GetClientNumber("mode", 0) == 1 then
		PDCity.SetCharacterSpawn(pos, yaw)
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Character spawn point set for this map.")
	else
		PDCity.SetDefaultSpawn(pos, yaw)
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Waiting spawn point set for this map.")
	end

	return true
end

function TOOL.BuildCPanel(panel)
	panel:AddControl("Header", {
		Description = "Owner-only. Left click anywhere, facing the direction you want players to face, to set a spawn point on THIS map - a small random area around that point, not one exact spot. Per-map: a new map needs its own spawn points set, and until then players use the map's own spawn points instead.",
	})
	panel:CheckBox("Set the character spawn (after selecting) instead of the waiting spawn", "pdcity_spawnpoint_mode")
	panel:ControlHelp("Waiting spawn: where players sit while picking a character. Character spawn: where they actually appear once they have one - can be anywhere else on the map.")
end
