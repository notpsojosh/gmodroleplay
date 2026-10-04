--[[---------------------------------------------------------
	Storage for the Staff Menu's jail "void" spot - a single point per
	map, set with the owner-only Staff Jail Spot tool
	(entities/weapons/gmod_tool/stools/pdcity_staffjailspot.lua), somewhere
	outside the map's skybox/playable area. Used by core/sv_staff_jail.lua.

	Deliberately separate from the RP jail system's spawn points
	(core/sv_jail_spawns.lua, plural, inside the map, bail-able) - this is
	one fixed point for a staff punishment, not part of the arrest RP loop.
	Same per-map file-per-map storage pattern as that file, and the
	default player spawn override (core/sv_spawn_point.lua).
-----------------------------------------------------------]]

local SPOT_DIR = "pdcity/staff_jail_spot"

local function SpotPath()
	return SPOT_DIR .. "/" .. game.GetMap() .. ".json"
end

-- Lazy-loaded { pos = Vector, ang = Angle } for the current map, or
-- `false` once confirmed there isn't one.
local Spot

local function LoadSpot()
	if Spot ~= nil then return Spot end

	local raw = file.Read(SpotPath(), "DATA")
	local stored = raw and util.JSONToTable(raw)
	if not stored then
		Spot = false
		return Spot
	end

	Spot = {
		pos = Vector(stored.pos.x, stored.pos.y, stored.pos.z),
		ang = Angle(0, stored.yaw or 0, 0),
	}
	return Spot
end

function PDCity.SetStaffJailSpot(pos, yaw)
	Spot = { pos = pos, ang = Angle(0, yaw, 0) }

	file.CreateDir(SPOT_DIR)
	file.Write(SpotPath(), util.TableToJSON({
		pos = { x = pos.x, y = pos.y, z = pos.z },
		yaw = yaw,
	}, true))
end

-- { pos = Vector, ang = Angle }, or nil if none set for this map.
function PDCity.GetStaffJailSpot()
	return LoadSpot() or nil
end
