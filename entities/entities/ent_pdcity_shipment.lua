--[[---------------------------------------------------------
	Shipment crate - a physical box holding N copies of one item class.
	Press E to take one out; the crate removes itself once it's empty.

	Any F4 shop entry can be turned into a shipment by giving it a
	ShipmentCount (see core/sh_f4_catalogue.lua and the "Shipment of"
	field in the F4 admin editor). When one is bought, the purchase
	handler (core/sv_f4_entities.lua) spawns this crate instead of the
	item itself.

	Nothing about this entity is specific to weapons - it'll hold any
	class the shop can sell.

	Base is "base_anim", not "base_gmodentity", for the same reason as
	the other PD City entities: this gamemode doesn't derive from
	sandbox, so base_gmodentity doesn't exist here.
-----------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Shipment"
ENT.Category = "PD Roleplay"
ENT.Author = ""
ENT.Spawnable = false -- only ever created by a shop purchase

local MODEL = "models/props_junk/wood_crate001a.mdl"

-- Static field so generic tooling (F4 card previews, inventory slots)
-- can find the model without this file having run - same reason
-- ent_pdcity_printer.lua sets one.
ENT.Model = MODEL

local TAKE_COOLDOWN = 0.4

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "ItemClass")
	self:NetworkVar("Int", 0, "Count")
end

if SERVER then

	function ENT:Initialize()
		self:SetModel(MODEL)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			-- Heavy enough not to get punted across the map by someone
			-- walking into it, same reasoning as the money case.
			phys:SetMass(150)
		end
	end

	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() then return end
		if not activator:Alive() then return end

		if (self.pdcity_NextTake or 0) > CurTime() then return end
		self.pdcity_NextTake = CurTime() + TAKE_COOLDOWN

		local class = self:GetItemClass()
		if class == "" then self:Remove() return end

		local count = self:GetCount()
		if count <= 0 then self:Remove() return end

		-- Weapons go straight to hand; anything else is spawned in front
		-- of the player, since Give() only means anything for a weapon.
		if weapons.GetStored(class) then
			activator:Give(class)
		else
			local ent = ents.Create(class)
			if not IsValid(ent) then return end

			ent:SetPos(self:GetPos() + self:GetForward() * 24 + Vector(0, 0, 8))
			ent:Spawn()
			ent:Activate()
			ent:SetCreator(activator)
			if isfunction(ent.CPPISetOwner) then ent:CPPISetOwner(activator) end
		end

		count = count - 1
		self:SetCount(count)

		activator:EmitSound("items/ammo_pickup.wav", 60, 110)

		if count <= 0 then
			activator:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Took the last " .. PDCity.GetItemName(class) .. " - the crate is empty.")
			self:Remove()
		else
			activator:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Took a " .. PDCity.GetItemName(class) .. " (" .. count .. " left).")
		end
	end

end

if CLIENT then

	-- Floating label so it's obvious what's inside and how many are
	-- left without having to walk up and press E.
	function ENT:Draw()
		self:DrawModel()

		if EyePos():DistToSqr(self:GetPos()) > 300 * 300 then return end

		local class = self:GetItemClass()
		if class == "" then return end

		local ang = Angle(0, EyeAngles().y - 90, 90)

		cam.Start3D2D(self:GetPos() + Vector(0, 0, 26), ang, 0.2)
			draw.SimpleTextOutlined(PDCity.GetItemName(class), "PDCity_Heading", 0, -12,
				Color(235, 237, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
			draw.SimpleTextOutlined("x" .. self:GetCount(), "PDCity_Heading", 0, 12,
				Color(140, 220, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
		cam.End3D2D()
	end

end
