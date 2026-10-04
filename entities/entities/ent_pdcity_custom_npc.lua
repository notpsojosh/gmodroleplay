--[[---------------------------------------------------------
	Generic owner-made NPC - the entity behind every custom NPC created
	from the F4 admin editor's "NPCs" tab (core/sh_npc_classes.lua's
	PDCity.CUSTOM_NPCS). One shared entity class wearing whatever model
	its NPC definition specifies; which definition a given placed
	instance represents is remembered per-entity
	(self.pdcity_CustomNPCID), set by the NPC Spawner tool via
	core/sv_npc_spawns.lua before spawning - see
	core/sh_npc_classes.lua's own header for the full synthetic-class
	scheme that makes that tool able to place these at all.

	Purely a standing/idle NPC - no Use(), no dialogue, no gameplay of
	its own beyond standing where it was placed. Fires a generic hook on use so
	the modification addon (addons/pdroleplay_modification) can build
	real interaction (buy/sell, a hitman contract, whatever) on top,
	same "wiring, not gameplay" philosophy as Job Activities
	(core/sh_activities.lua).
-----------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Custom NPC"
ENT.Category = "PD Roleplay"
ENT.Author = ""
-- Never Q-menu spawnable - a blind spawn has no CustomNPCID to attach,
-- which would leave it wearing the fallback model with no identity.
-- Always created through the NPC Spawner tool instead.
ENT.Spawnable = false
ENT.AdminOnly = true

local FALLBACK_MODEL = "models/player/kleiner.mdl"

if SERVER then

	function ENT:Initialize()
		local npc = self.pdcity_CustomNPCID and PDCity.GetCustomNPCByID(self.pdcity_CustomNPCID)
		local model = (npc and npc.Model and util.IsValidModel(npc.Model)) and npc.Model or FALLBACK_MODEL

		self:SetModel(model)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 73))
		self:DrawShadow(true)
		self:ResetSequence(PDCity.PickIdleSequence(self))
		self:SetUseType(SIMPLE_USE)

		-- Floating name label (core/sv_nameplates.lua, cl_entity_labels.lua) -
		-- shows this NPC's own given name above itself with no code needed.
		PDCity.SetNameplate(self, npc and npc.Name)
	end

	-- Only the owner may retool/remove a placed custom NPC - same
	-- lockdown as ent_pdcity_printer.lua's own CanTool (Falco's Prop
	-- Protection would otherwise deny everyone including the owner,
	-- since this has no CPPI ownership of its own).
	function ENT:CanTool(ply, trace, mode, tool, button)
		return PDCity.IsOwner(ply)
	end

	function ENT:PhysgunPickup(ply)
		return PDCity.IsOwner(ply)
	end

	-- No behaviour of its own on purpose - see this file's own header.
	-- Fires the generic "PDCity_CustomNPCUsed" hook (build real
	-- interaction on top in the modification addon) AND, if this
	-- specific NPC has its own code set (via the Developer Console,
	-- core/sv_npc_classes.lua's "set_code"/"get_code" actions), runs
	-- that too - same "wiring, not gameplay" philosophy as Job
	-- Activities (core/sh_activities.lua), just per-NPC-definition
	-- instead of per-entity-class, since every Custom NPC shares this
	-- one class and was never a valid Job Activity target on its own.
	function ENT:Use(activator, caller)
		if not IsValid(activator) or not activator:IsPlayer() then return end

		local npc = self.pdcity_CustomNPCID and PDCity.GetCustomNPCByID(self.pdcity_CustomNPCID)
		hook.Run("PDCity_CustomNPCUsed", self, activator, npc)

		if npc then PDCity.RunCustomNPCCode(npc, self, activator) end
	end

end
