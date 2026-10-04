--[[---------------------------------------------------------
	A pickup-able stack of cash. Press E on it to add its Amount to your
	profile balance (core/sv_profiles.lua). Spawnable from the Entities
	tab ("PD City" category) as admin, for testing the money system;
	later systems (paydays, drops, ATMs) can ents.Create this and call
	SetAmount before Spawn.

	Base is "base_anim", not "base_gmodentity" - this gamemode doesn't
	derive from sandbox, so base_gmodentity doesn't exist here (that's
	also why AdvDupe2's gmod_contr_spawner logs a derive error on boot).
-----------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Money"
ENT.Category = "PD Roleplay"
ENT.Author = ""
ENT.Spawnable = true
ENT.AdminOnly = true -- spawning this literally creates money

local MODEL = "models/props_c17/suitcase_passenger_physics.mdl"
local FALLBACK_MODEL = "models/props_junk/cardboard_box004a.mdl"
local DEFAULT_AMOUNT = 100

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Amount")
end

if SERVER then

	function ENT:Initialize()
		local model = util.IsValidModel(MODEL) and MODEL or FALLBACK_MODEL
		self:SetModel(model)

		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		-- Passes through players (and other weapons/pickups) while still
		-- resting on the world, so walking into a dropped case doesn't
		-- punt it across the map. A true "no collision at all" would
		-- drop it straight through the floor instead - this is the
		-- collision group the engine's own weapon pickups use.
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

		if self:GetAmount() <= 0 then
			self:SetAmount(DEFAULT_AMOUNT)
		end

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()

			-- Heavy + damped: even a gravity gun punt or an explosion
			-- only nudges it, rather than sending it flying.
			phys:SetMass(200)
			phys:SetDamping(2, 4)
		end
	end

	-- Spawn menu placement. ply/tr come from the engine.
	function ENT:SpawnFunction(ply, tr, className)
		if not tr.Hit then return end

		local ent = ents.Create(className)
		ent:SetPos(tr.HitPos + tr.HitNormal * 8)
		ent:Spawn()
		ent:Activate()
		return ent
	end

	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() then return end
		if self.PickedUp then return end -- guard against double-Use in one frame

		if not PDCity.AddMoney(activator, self:GetAmount()) then return end

		self.PickedUp = true
		activator:EmitSound("items/ammo_pickup.wav", 60, 110)
		activator:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Picked up $" .. self:GetAmount() .. ".")
		self:Remove()
	end

end

if CLIENT then

	-- Floating "$amount" label so it's obvious what the entity is worth
	-- without needing a custom cash model.
	function ENT:Draw()
		self:DrawModel()

		if EyePos():DistToSqr(self:GetPos()) > 250 * 250 then return end

		local ang = Angle(0, EyeAngles().y - 90, 90)
		cam.Start3D2D(self:GetPos() + Vector(0, 0, 18), ang, 0.25)
			draw.SimpleTextOutlined("$" .. self:GetAmount(), "PDCity_Heading", 0, 0,
				Color(140, 220, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
		cam.End3D2D()
	end

end
