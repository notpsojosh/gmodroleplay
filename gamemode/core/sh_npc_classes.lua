--[[---------------------------------------------------------
	Registry of PD City's own custom "NPC" entities that the NPC Spawner
	tool (entities/weapons/gmod_tool/stools/pdcity_npcspawner.lua) is
	allowed to place - deliberately NOT a general npc_* spawner, so the
	owner can only place things actually built for this gamemode, never
	stock HL2 NPCs.

	Two ways an NPC ends up in the tool's dropdown:

	1. Built-in (PDCity.NPC_CLASSES below) - a bespoke SENT someone wrote
	   (the Bail Bondsman), with its own Class and its own Use()/dialogue/
	   behaviour.

	2. Owner-made (PDCity.CUSTOM_NPCS, core/sv_npc_classes.lua) - created
	   in-game from the F4 admin editor's "NPCs" tab with just a name and
	   a model, no SENT required. All share ONE real entity class
	   (PDCity.CUSTOM_NPC_BASE_CLASS, entities/entities/ent_pdcity_custom_npc.lua)
	   - which specific custom NPC a placed instance represents is
	   remembered per-entity (ent.pdcity_CustomNPCID). Since the tool's
	   dropdown and core/sv_npc_spawns.lua's persistence both only ever
	   deal in a single "class" string per spawnable thing, each custom
	   NPC gets its own SYNTHETIC class string
	   (PDCity.CustomNPCSyntheticClass) that PDCity.ResolveNPCSpawnClass
	   decodes back to (real class, custom NPC ID) at actual spawn time -
	   see core/sv_npc_spawns.lua's SpawnFromRecord.

	Shared so the tool's Q-menu dropdown can list every display name from
	both sources in one list (PDCity.GetAllNPCClasses).
-----------------------------------------------------------]]

PDCity.NPC_CLASSES = {
	{ Class = "ent_pdcity_bail", Name = "Bail Bondsman" },
	-- Car Dealer/Garage entries (citizen + police/hospital/fire variants)
	-- removed with the vehicle system - see init.lua's own comment.
	--
	-- "Mike" (a decorative standing NPC) was removed too: it was only ever
	-- a placeholder built on a workshop character model, and a decorative
	-- NPC is exactly what the F4 admin editor's "NPCs" tab already makes
	-- in-game from any model, with no SENT to ship.
}

PDCity.CUSTOM_NPC_BASE_CLASS = "ent_pdcity_custom_npc"

-- Replaced wholesale by disk load (server) / network sync (client) - see
-- core/sv_npc_classes.lua.
PDCity.CUSTOM_NPCS = PDCity.CUSTOM_NPCS or {}

function PDCity.GetCustomNPCByID(id)
	for _, npc in ipairs(PDCity.CUSTOM_NPCS) do
		if npc.ID == id then return npc end
	end
end

-- The tool-dropdown/persistence-facing "class" string for one custom
-- NPC - never a real registered entity class, only ever decoded by
-- PDCity.ResolveNPCSpawnClass below at the moment something's actually
-- spawned.
function PDCity.CustomNPCSyntheticClass(id)
	return "pdcity_customnpc_" .. id
end

-- (realClass, customNPCID or nil) - customNPCID is set only when `class`
-- was one of the synthetic strings above; realClass is always a genuine
-- spawnable entity class either way (nil if `class` isn't recognised at
-- all - a built-in class that no longer exists, or a corrupted record).
function PDCity.ResolveNPCSpawnClass(class)
	local id = tonumber(string.match(class or "", "^pdcity_customnpc_(%d+)$"))
	if id then
		return PDCity.GetCustomNPCByID(id) and PDCity.CUSTOM_NPC_BASE_CLASS or nil, id
	end

	for _, entry in ipairs(PDCity.NPC_CLASSES) do
		if entry.Class == class then return class, nil end
	end

	return nil, nil
end

-- Combined list, built-ins first, in the {Class, Name} shape the
-- NPC Spawner tool's dropdown already expects - Class here is always
-- either a real built-in class or one of the synthetic custom-NPC
-- strings above, never PDCity.CUSTOM_NPC_BASE_CLASS directly (that
-- would be ambiguous between every custom NPC sharing it).
function PDCity.GetAllNPCClasses()
	local list = {}
	for _, entry in ipairs(PDCity.NPC_CLASSES) do
		table.insert(list, entry)
	end
	for _, npc in ipairs(PDCity.CUSTOM_NPCS) do
		table.insert(list, { Class = PDCity.CustomNPCSyntheticClass(npc.ID), Name = npc.Name })
	end
	return list
end

--[[---------------------------------------------------------
	Shared by every PD City NPC-style entity, since they all use a
	player model on a base_anim entity and hit the same problem.

	A base_anim entity that never picks a sequence sits in the raw bind
	pose (the T-pose). ACT_IDLE via SelectWeightedSequence is the robust
	way to find a real idle regardless of the model's sequence names;
	the name list and "skip sequence 0" are fallbacks for models that
	don't map that activity (sequence 0 is very often the bind pose
	itself, so sequence 1 - almost always a real animation - beats
	leaving it at 0).
-----------------------------------------------------------]]
function PDCity.PickIdleSequence(ent)
	local seq = ent:SelectWeightedSequence(ACT_IDLE)
	if seq and seq > 0 then return seq end

	for _, name in ipairs({ "idle_all_01", "idle_unarmed", "idle_all_02", "Idle" }) do
		seq = ent:LookupSequence(name)
		if seq and seq > 0 then return seq end
	end

	if ent:GetSequenceCount() > 1 then return 1 end

	return 0
end
