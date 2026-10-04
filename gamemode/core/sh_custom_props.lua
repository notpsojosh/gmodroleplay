--[[---------------------------------------------------------
	Custom Props - "copy any prop, turn it into a real spawnable entity"
	(the Prop Copier toolgun tool, entities/weapons/gmod_tool/stools/pdcity_propcopier.lua).

	Unlike Job Activities' station concept (tried, then explicitly
	rejected - see this session's own history) or the NPC Maker (one
	shared entity class + a per-instance definition ID), each Custom Prop
	gets its OWN real, independent scripted_ents class -
	"pdcity_customprop_<id>" - registered dynamically at runtime via
	PDCity.RegisterCustomPropClass below, on BOTH realms (core/sv_custom_props.lua
	calls this on the server when a definition is added/loaded;
	cl_custom_props.lua calls it on the client when the definition syncs
	down). That's what makes the result behave exactly like a normal,
	independently spawnable entity - genuinely spawnable from the Q menu
	(ENT.Spawnable = true, own spawn icon from its own model), and
	immediately usable as a real F4 shop entry (core/sh_f4_catalogue.lua's
	Entities tab) or a Job Activity's Class (core/sh_activities.lua) with
	NO changes needed to either system - both already just check
	scripted_ents.GetStored(class), which this satisfies like any other
	SENT would.

	Definitions (Name, Model) persist server-side
	(core/sv_custom_props.lua, data/pdcity/custom_props.json) and are
	re-registered fresh every server start (dynamic scripted_ents
	registrations don't survive a restart on their own) - synced to
	every client the same way so their copy of the class exists too.
-----------------------------------------------------------]]

PDCity.CUSTOM_PROPS = PDCity.CUSTOM_PROPS or {}

function PDCity.CustomPropClass(id)
	return "pdcity_customprop_" .. id
end

function PDCity.GetCustomPropByID(id)
	for _, def in ipairs(PDCity.CUSTOM_PROPS) do
		if def.ID == id then return def end
	end
end

local FALLBACK_MODEL = "models/hunter/blocks/cube1x1x1.mdl"

-- Builds and registers the actual ENT table for one Custom Prop
-- definition. Idempotent - safe to call again for the same definition
-- (e.g. every server boot for every saved definition); scripted_ents.Register
-- just overwrites the previous registration under the same class name.
function PDCity.RegisterCustomPropClass(def)
	local class = PDCity.CustomPropClass(def.ID)
	local model = (isstring(def.Model) and util.IsValidModel(def.Model)) and def.Model or FALLBACK_MODEL

	local ENT = {}
	ENT.Type = "anim"
	ENT.Base = "base_gmodentity"
	ENT.PrintName = def.Name or ("Custom Prop #" .. def.ID)
	ENT.Category = "PD Roleplay (Custom)"
	ENT.Author = ""
	ENT.Spawnable = true
	-- Deliberately NOT ENT.AdminOnly = true - that's GMod's OWN native
	-- admin/usergroup check, entirely separate from PD Roleplay's owner
	-- system (PDCity.OWNER_STEAMIDS, core/sh_permissions.lua). Setting it
	-- silently blocks the actual spawn (SpawnFunction never runs, no
	-- error, no feedback) for anyone who's a PDCity owner without ALSO
	-- being a native engine admin - exactly the "shows in the Q menu but
	-- doesn't spawn" symptom this was reported as. core/sv_restrictions.lua's
	-- own PlayerSpawnSENT hook (PDCity.CanSpawnFromMenu) already enforces
	-- owner/superadmin-only spawning correctly, so this native flag was
	-- redundant even before it turned out to actively conflict.
	ENT.Model = model -- static field so the Q-menu spawn icon and F4 shop card preview can read it without an instance

	if SERVER then

		function ENT:Initialize()
			self:SetModel(model)
			self:PhysicsInit(SOLID_VPHYSICS)
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:SetUseType(SIMPLE_USE)

			-- Floating name label (core/sv_nameplates.lua, cl_entity_labels.lua) -
			-- shows this Custom Prop's own given name above itself with no
			-- code needed; a Developer Console script can still change it
			-- later via PDCity.SetNameplate.
			PDCity.SetNameplate(self, def.Name)

			local phys = self:GetPhysicsObject()
			if IsValid(phys) then
				phys:Wake()
			else
				-- Same fallback as ent_pdcity_printer.lua/ent_pdcity_custom_npc.lua -
				-- a model with no .phy collision mesh gives SOLID_VPHYSICS no
				-- physics object at all, silently killing both collision and
				-- +use. A plain bounding box keeps this functional regardless.
				local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 36)
				self:PhysicsInitBox(mins, maxs)
				self:SetMoveType(MOVETYPE_NONE)
				self:SetSolid(SOLID_BBOX)
				self:SetCollisionBounds(mins, maxs)
			end
		end

		function ENT:SpawnFunction(ply, tr, className)
			if not tr.Hit then return end
			if not IsValid(ply) then return end

			local ent = ents.Create(className)
			ent:SetPos(tr.HitPos + tr.HitNormal * 4)
			ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
			ent:Spawn()
			ent:Activate()

			ent:SetCreator(ply)
			if isfunction(ent.CPPISetOwner) then ent:CPPISetOwner(ply) end

			return ent
		end

		-- No behaviour of its own on purpose, same "wiring, not gameplay"
		-- philosophy as everything else built this session - fires a
		-- generic hook (build real interaction on top in the modification
		-- addon) AND doubles as an ordinary Class-based Job Activity target,
		-- since PDCity.GetActivityForClass already just checks the class
		-- name, which this is a real, independent one of.
		function ENT:Use(activator, caller)
			if not IsValid(activator) or not activator:IsPlayer() then return end
			hook.Run("PDCity_CustomPropUsed", self, activator, def)
		end

		-- Required for a Collide-triggered Job Activity to ever fire on a
		-- Custom Prop at all - core/sh_activities.lua's own header explains
		-- why this has to live on the entity itself rather than a generic
		-- hook.Add the way Use's PlayerUse hook works. Every touch is
		-- forwarded to PDCity.FireActivityCollide, which does its own
		-- Activity lookup/FillClasses filtering/cooldown and is a complete
		-- no-op if this class has no Collide-type Activity tied to it - so
		-- this is always safe to define, not just for classes that end up
		-- using it.
		function ENT:StartTouch(other)
			PDCity.FireActivityCollide(self, other)
		end

	end

	scripted_ents.Register(ENT, class)
end
