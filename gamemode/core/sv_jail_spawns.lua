--[[---------------------------------------------------------
	Storage for jail spawn points, set in-game with the owner-only Jail
	Spawn tool (entities/weapons/gmod_tool/stools/pdcity_jailspawn.lua).
	Per-map, like the door system's own data - a jail spawn's coordinates
	only make sense on the map they were placed on.
-----------------------------------------------------------]]

local SPAWNS_DIR = "pdcity/jail_spawns"

local function SpawnsPath()
	return SPAWNS_DIR .. "/" .. game.GetMap() .. ".json"
end

-- Lazy-loaded list of { pos = {x,y,z}, ang = {p,y,r} } for the current map.
local Spawns

local function LoadSpawns()
	if Spawns then return Spawns end
	local raw = file.Read(SpawnsPath(), "DATA")
	Spawns = (raw and util.JSONToTable(raw)) or {}
	return Spawns
end

local function SaveSpawns()
	file.CreateDir(SPAWNS_DIR)
	file.Write(SpawnsPath(), util.TableToJSON(Spawns or {}, true))
end

function PDCity.AddJailSpawn(pos, ang)
	LoadSpawns()
	table.insert(Spawns, {
		pos = { x = pos.x, y = pos.y, z = pos.z },
		ang = { p = ang.p, y = ang.y, r = ang.r },
	})
	SaveSpawns()
	return #Spawns
end

-- Removes whichever spawn point is nearest to pos, if it's within
-- maxDist. Returns true if one was removed.
function PDCity.RemoveNearestJailSpawn(pos, maxDist)
	LoadSpawns()

	local closestIndex, closestDistSqr
	for i, spawn in ipairs(Spawns) do
		local distSqr = pos:DistToSqr(Vector(spawn.pos.x, spawn.pos.y, spawn.pos.z))
		if not closestDistSqr or distSqr < closestDistSqr then
			closestDistSqr = distSqr
			closestIndex = i
		end
	end

	if not closestIndex or closestDistSqr > maxDist * maxDist then return false end

	table.remove(Spawns, closestIndex)
	SaveSpawns()
	return true
end

function PDCity.ClearJailSpawns()
	Spawns = {}
	SaveSpawns()
end

function PDCity.CountJailSpawns()
	LoadSpawns()
	return #Spawns
end

--[[---------------------------------------------------------
	Owner-only: pdcity_clearjailspawns confirm
	This used to be the Jail Spawn tool's Reload (R key) action - moved
	to a command requiring an explicit "confirm" argument since R is
	GMod's default reload bind and far too easy to hit by muscle memory
	while just switching weapons, instantly wiping every jail spawn on
	the map with a single accidental keypress.
-----------------------------------------------------------]]

concommand.Add("pdcity_clearjailspawns", function(ply, cmd, args)
	if IsValid(ply) and not PDCity.IsOwner(ply) then return end

	local function Reply(text)
		if IsValid(ply) then ply:ChatPrint(text) else print(text) end
	end

	if args[1] ~= "confirm" then
		Reply("[" .. PDCity.BRAND_TAG .. "] This clears all " .. PDCity.CountJailSpawns() .. " jail spawn(s) on this map. Run \"pdcity_clearjailspawns confirm\" to actually do it.")
		return
	end

	PDCity.ClearJailSpawns()
	Reply("[" .. PDCity.BRAND_TAG .. "] Cleared all jail spawns on this map.")
end)

-- Returns { pos = Vector, ang = Angle }, or nil if none are set for this map.
function PDCity.GetRandomJailSpawn()
	LoadSpawns()
	if #Spawns == 0 then return nil end

	local spawn = Spawns[math.random(#Spawns)]
	return {
		pos = Vector(spawn.pos.x, spawn.pos.y, spawn.pos.z),
		ang = Angle(spawn.ang.p, spawn.ang.y, spawn.ang.r),
	}
end
