--[[---------------------------------------------------------
	Owner-only tool for managing jail spawn points (core/sv_jail_spawns.lua),
	used by the arrest system (core/sv_arrests.lua) to place a jailed
	player somewhere on the map.

	  Left click   - add a jail spawn point where you're aiming
	  Right click  - remove the nearest existing jail spawn point

	"Clear ALL" used to be Reload (R) - moved to the console command
	"pdcity_clearjailspawns confirm" (core/sv_jail_spawns.lua) since R
	is GMod's default reload bind and far too easy to hit by accident.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_jailspawn.name"

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
}

if CLIENT then
	language.Add("tool.pdcity_jailspawn.name", "Jail Spawn (Owner)")
	language.Add("tool.pdcity_jailspawn.desc", "Add or remove jail spawn points for the arrest system")
	language.Add("tool.pdcity_jailspawn.left", "Add a jail spawn point here")
	language.Add("tool.pdcity_jailspawn.right", "Remove the nearest jail spawn point")
end

local REMOVE_RADIUS = 100

local function CheckOwner(tool)
	local ply = tool:GetOwner()
	if PDCity.IsOwner(ply) then return true end
	if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can use the Jail Spawn tool.") end
	return false
end

function TOOL:LeftClick(trace)
	if not CheckOwner(self) then return false end
	if not trace.Hit then return false end
	if CLIENT then return true end

	local ply = self:GetOwner()
	local pos = trace.HitPos + Vector(0, 0, 4)
	local ang = Angle(0, ply:EyeAngles().y, 0)

	local count = PDCity.AddJailSpawn(pos, ang)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Jail spawn added (" .. count .. " total on this map).")
	return true
end

function TOOL:RightClick(trace)
	if not CheckOwner(self) then return false end
	if not trace.Hit then return false end
	if CLIENT then return true end

	local ply = self:GetOwner()
	if PDCity.RemoveNearestJailSpawn(trace.HitPos, REMOVE_RADIUS) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Removed the nearest jail spawn (" .. PDCity.CountJailSpawns() .. " left on this map).")
	else
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No jail spawn within " .. REMOVE_RADIUS .. " units to remove.")
	end
	return true
end

function TOOL.BuildCPanel(panel)
	panel:AddControl("Header", {
		Description = "Owner-only. Left click anywhere to add a jail spawn point - arrested players teleport to a random one. Right click removes the nearest one. To clear ALL of them, run \"pdcity_clearjailspawns confirm\" in console.",
	})
end
