--[[---------------------------------------------------------
	Persistent placement for PD City's custom NPCs (core/sh_npc_classes.lua),
	managed in-game with the owner-only NPC Spawner tool. Same per-map
	JSON pattern as core/sv_jail_spawns.lua, except entries are keyed by
	a stable random ID rather than array position - a live entity keeps
	that ID for its whole life (ent.pdcity_NPCSpawnID) so it can always
	be matched back to its disk record for removal, even after other
	entries have been added or removed in between.
-----------------------------------------------------------]]

local SPAWNS_DIR = "pdcity/npc_spawns"

local function SpawnsPath()
	return SPAWNS_DIR .. "/" .. game.GetMap() .. ".json"
end

-- [id] = { class = "...", pos = {x,y,z}, ang = {p,y,r} }
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

-- Live entities currently placed by this system, keyed the same as the
-- disk records (PDCity.ManagedNPCEntities[id] = entity).
PDCity.ManagedNPCEntities = {}

local function AddRecord(class, pos, ang)
	LoadSpawns()
	local id = "npc_" .. os.time() .. "_" .. math.random(100000, 999999)
	Spawns[id] = {
		class = class,
		pos = { x = pos.x, y = pos.y, z = pos.z },
		ang = { p = ang.p, y = ang.y, r = ang.r },
	}
	SaveSpawns()
	return id
end

local function RemoveRecord(id)
	LoadSpawns()
	if not Spawns[id] then return end
	Spawns[id] = nil
	SaveSpawns()
end

function PDCity.CountNPCSpawns()
	LoadSpawns()
	local count = 0
	for _ in pairs(Spawns) do count = count + 1 end
	return count
end

-- Creates the live entity for one record and wires up its cleanup, so
-- the disk record and PDCity.ManagedNPCEntities stay correct no matter
-- how the entity ends up being removed later (this tool, the remover
-- tool, ent_remove, a map cleanup command...).
--
-- record.class may be a real built-in NPC class OR one of the synthetic
-- "pdcity_customnpc_<id>" strings a custom (F4 admin editor "NPCs" tab)
-- NPC uses instead (core/sh_npc_classes.lua) - PDCity.ResolveNPCSpawnClass
-- decodes it either way; a record whose class no longer resolves at all
-- (the custom NPC it pointed to was deleted) is silently skipped rather
-- than spawning something with no identity.
local function SpawnFromRecord(id, record)
	local realClass, customNPCID = PDCity.ResolveNPCSpawnClass(record.class)
	if not realClass then return nil end

	local ent = ents.Create(realClass)
	if not IsValid(ent) then return nil end

	ent:SetPos(Vector(record.pos.x, record.pos.y, record.pos.z))
	ent:SetAngles(Angle(record.ang.p, record.ang.y, record.ang.r))
	ent.pdcity_CustomNPCID = customNPCID
	ent:Spawn()
	ent:Activate()

	ent.pdcity_NPCSpawnID = id
	PDCity.ManagedNPCEntities[id] = ent

	ent:CallOnRemove("pdcity_npc_persistence_cleanup", function()
		PDCity.ManagedNPCEntities[id] = nil
		RemoveRecord(id)
	end)

	return ent
end

-- Places a new NPC and persists it. Returns the live entity.
function PDCity.SpawnManagedNPC(class, pos, ang)
	local id = AddRecord(class, pos, ang)
	return SpawnFromRecord(id, LoadSpawns()[id])
end

-- Removes one placed NPC by its ID (triggers the CallOnRemove cleanup
-- above, which handles both the disk record and the runtime table).
function PDCity.RemoveManagedNPC(id)
	local ent = PDCity.ManagedNPCEntities[id]
	if IsValid(ent) then ent:Remove() end
end

function PDCity.ClearManagedNPCs()
	for _, ent in pairs(PDCity.ManagedNPCEntities) do
		if IsValid(ent) then ent:Remove() end
	end
	PDCity.ManagedNPCEntities = {}

	LoadSpawns()
	Spawns = {}
	SaveSpawns()
end

--[[---------------------------------------------------------
	Owner-only: pdcity_clearnpcs confirm
	This used to be the NPC Spawner tool's Reload (R key) action - moved
	to a command requiring an explicit "confirm" argument since R is
	GMod's default reload bind and far too easy to hit by muscle memory
	while just switching weapons, instantly wiping every placed NPC on
	the map with a single accidental keypress.
-----------------------------------------------------------]]

concommand.Add("pdcity_clearnpcs", function(ply, cmd, args)
	if IsValid(ply) and not PDCity.IsOwner(ply) then return end

	local function Reply(text)
		if IsValid(ply) then ply:ChatPrint(text) else print(text) end
	end

	if args[1] ~= "confirm" then
		Reply("[" .. PDCity.BRAND_TAG .. "] This removes ALL " .. PDCity.CountNPCSpawns() .. " placed NPC(s) on this map. Run \"pdcity_clearnpcs confirm\" to actually do it.")
		return
	end

	PDCity.ClearManagedNPCs()
	Reply("[" .. PDCity.BRAND_TAG .. "] Removed all placed NPCs on this map.")
end)

-- Recreate every NPC placed on this map from previous sessions.
hook.Add("InitPostEntity", "pdcity_RespawnManagedNPCs", function()
	LoadSpawns()
	for id, record in pairs(Spawns) do
		SpawnFromRecord(id, record)
	end
end)
