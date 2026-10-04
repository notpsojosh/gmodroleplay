--[[---------------------------------------------------------
	Bail bondsman. Press E to open a list of everyone currently jailed
	(including yourself, if you are) and pay someone's bail - an
	owner-configurable amount per minute remaining on their sentence
	(rounded up; core/sh_laws.lua's PDCity.LAW_REWARDS.BailPerMinute,
	editable from F1 Site Admin's "Laws & Rewards" tab), deducted from
	YOUR balance. See core/sv_arrests.lua for PDCity.OpenBailMenuFor and
	the "PDCity_PayBail" net receiver that actually processes payment
	(shared logic, not duplicated here).

	Spawnable from the Entities tab ("PD City" category) as admin, so
	the owner can place one near wherever jail spawns are set up - or,
	for a permanent placement that survives restarts, place it with the
	NPC Spawner tool instead (core/sh_npc_classes.lua already lists it).

	Model is a placeholder (models/player/police.mdl - bundled with base
	Garry's Mod content, no workshop dependency) since no specific "bail
	bondsman" model was provided; swap MODEL below for anything else.

	Uses SOLID_BBOX rather than PhysicsInit(SOLID_VPHYSICS): player
	models generally don't carry the prop-style physics collision mesh
	SOLID_VPHYSICS depends on, so that setup silently produced an entity
	with NO collision at all - traces (including the toolgun's, which is
	how this got noticed) passed straight through it. A plain bounding
	box doesn't depend on the model having real physics geometry, so it
	works for any model.
-----------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Bail Bondsman"
ENT.Category = "PD Roleplay"
ENT.Author = ""
ENT.Spawnable = true
ENT.AdminOnly = true

local MODEL = "models/player/police.mdl"

-- Idle-sequence picking is shared by every PD City NPC - see
-- PDCity.PickIdleSequence in core/sh_npc_classes.lua.

if SERVER then

	function ENT:Initialize()
		self:SetModel(MODEL)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_BBOX)
		self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 73))
		self:SetUseType(SIMPLE_USE)
		self:DrawShadow(true)
		self:ResetSequence(PDCity.PickIdleSequence(self))
	end

	function ENT:SpawnFunction(ply, tr, className)
		if not tr.Hit then return end

		local ent = ents.Create(className)
		ent:SetPos(tr.HitPos)
		ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
		ent:Spawn()
		ent:Activate()
		return ent
	end

	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() then return end
		PDCity.OpenBailMenuFor(activator)
	end

end
