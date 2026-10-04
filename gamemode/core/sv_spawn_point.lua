--[[---------------------------------------------------------
	Two independent custom spawn points, both set in-game with the
	owner-only Default Spawn tool (entities/weapons/gmod_tool/stools/
	pdcity_spawnpoint.lua, its "Character spawn instead" checkbox toggles
	which one Left Click sets) rather than hardcoded here, since a
	coordinate only ever makes sense on the map it was set on (same
	reasoning, and same per-map file-per-map storage pattern, as
	core/sv_jail_spawns.lua):

	  Waiting spawn    where a player sits while the mandatory character
	                   selection screen has them frozen (core/sv_characters.lua) -
	                   NOT chosen a character yet this respawn.
	  Character spawn  where they actually appear once they HAVE picked
	                   one - the real gameplay spawn, which the owner may
	                   well want somewhere else on the map entirely (the
	                   waiting area doesn't need to be anywhere near where
	                   play actually happens).

	Runs on every GM:PlayerSpawn (join AND respawn after death) via
	hook.Add, which fires alongside core/sh_player_spawn.lua's own
	GM:PlayerSpawn function - GMod calls both a gamemode's GM: table
	method and any hook.Add callbacks for the same event, so this needs
	no changes to that file at all.

	A small random offset (SPAWN_RADIUS) stops every simultaneous spawn
	landing on the exact same point and stacking players on top of each
	other - "an area around here", not one exact spot.

	Until a spawn point has been set for the CURRENT map, this does
	nothing at all for that one (waiting/character are independent -
	either, both, or neither may be set) - players spawn wherever the
	map's own info_player_start entities put them, same as any other
	unmodified server.
-----------------------------------------------------------]]

local SPAWN_RADIUS = 48

-- One of these per spawn TYPE (waiting/character) - same lazy-load-once-
-- per-map-then-cache shape, just parameterised on the save directory so
-- the logic isn't written out twice.
local function MakeSpawnStore(dir)
	local cached -- nil = not loaded yet, false = confirmed none set, table = loaded

	local function Path()
		return dir .. "/" .. game.GetMap() .. ".json"
	end

	local function Load()
		if cached ~= nil then return cached end

		local raw = file.Read(Path(), "DATA")
		local stored = raw and util.JSONToTable(raw)
		if not stored then
			cached = false
			return cached
		end

		cached = {
			pos = Vector(stored.pos.x, stored.pos.y, stored.pos.z),
			ang = Angle(0, stored.yaw or 0, 0),
		}
		return cached
	end

	-- yaw alone, not a full Angle - a spawn point only ever needs to face
	-- a direction along the ground, matching the tool's own EyeAngles().y.
	local function Set(pos, yaw)
		cached = { pos = pos, ang = Angle(0, yaw, 0) }

		file.CreateDir(dir)
		file.Write(Path(), util.TableToJSON({
			pos = { x = pos.x, y = pos.y, z = pos.z },
			yaw = yaw,
		}, true))
	end

	return {
		Load = Load,
		Set = Set,
		Has = function() return Load() ~= false end,
	}
end

local WaitingSpawn = MakeSpawnStore("pdcity/default_spawn")
local CharacterSpawn = MakeSpawnStore("pdcity/character_spawn")

function PDCity.SetDefaultSpawn(pos, yaw) WaitingSpawn.Set(pos, yaw) end
function PDCity.HasDefaultSpawn() return WaitingSpawn.Has() end

function PDCity.SetCharacterSpawn(pos, yaw) CharacterSpawn.Set(pos, yaw) end
function PDCity.HasCharacterSpawn() return CharacterSpawn.Has() end

local function PlaceInSpawnArea(ply, spawn)
	local angle = math.Rand(0, 360)
	local dist = math.Rand(0, SPAWN_RADIUS)
	local offset = Vector(math.cos(math.rad(angle)) * dist, math.sin(math.rad(angle)) * dist, 0)

	-- Traced down/up from the target point rather than trusting the
	-- offset is exactly on the floor too - handles the offset landing
	-- on a slight step/slope near the original spot.
	local tr = util.TraceLine({
		start = spawn.pos + offset + Vector(0, 0, 32),
		endpos = spawn.pos + offset - Vector(0, 0, 64),
		mask = MASK_SOLID_BRUSHONLY,
	})

	ply:SetPos(tr.Hit and (tr.HitPos + Vector(0, 0, 2)) or (spawn.pos + offset))
	ply:SetEyeAngles(spawn.ang)
	ply:SetLocalVelocity(vector_origin)
end

hook.Add("PlayerSpawn", "pdcity_DefaultSpawnArea", function(ply)
	-- Which of the two spawn points applies depends entirely on whether
	-- they've actually picked a character yet this session
	-- (ply.pdcity_ActiveCharSlot, core/sv_characters.lua) - still
	-- choosing (or between "!characters" and finishing the switch) uses
	-- the waiting spawn; already playing as someone uses the character
	-- spawn instead.
	local spawn = ply.pdcity_ActiveCharSlot and CharacterSpawn.Load() or WaitingSpawn.Load()
	if not spawn then return end -- nothing set for this map/type - leave the map's own spawn points alone

	PlaceInSpawnArea(ply, spawn)
end)
