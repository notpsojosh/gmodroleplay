--[[---------------------------------------------------------
	A pickup-able crate of XP. Press E on it to choose which job class
	to put its XP into (core/sv_xp_crates.lua opens that menu and
	grants the XP once a class is picked). Unlike ent_pdcity_money.lua,
	the actual reward isn't decided until the player picks a class from
	the menu - but the crate is claimed (hidden, non-solid) the instant
	that menu opens, not when they choose, so a second player can't
	+use it while the first is still deciding. See ENT:Use below.

	Model is base HL2 content (props_junk), so unlike the money
	entity's suitcase there's no workshop-mounting fallback needed
	here - it's always available.

	Spawnable from the Entities tab ("PD City" category) as admin, for
	testing/placing; later systems (drops, rewards) can ents.Create
	this and call SetAmount before Spawn, same pattern as the money
	entity.
-----------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "XP Crate"
ENT.Category = "PD Roleplay"
ENT.Author = ""
ENT.Spawnable = true
ENT.AdminOnly = true

local MODEL = "models/props_junk/cardboard_box003a.mdl"
local DEFAULT_AMOUNT = 50

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "Amount")
end

if SERVER then

	function ENT:Initialize()
		self:SetModel(MODEL)

		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		-- Same reasoning as ent_pdcity_money.lua: passes through players
		-- while still resting on the world, so walking into it doesn't
		-- punt it away.
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

		if self:GetAmount() <= 0 then
			self:SetAmount(DEFAULT_AMOUNT)
		end

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			phys:SetMass(50)
			phys:SetDamping(2, 4)
		end
	end

	function ENT:SpawnFunction(ply, tr, className)
		if not tr.Hit then return end

		local ent = ents.Create(className)
		ent:SetPos(tr.HitPos + tr.HitNormal * 8)
		ent:Spawn()
		ent:Activate()
		return ent
	end

	--[[-------------------------------------------------------
		Claimed the instant someone opens the menu, not when they
		actually choose a class - otherwise a second player could +use
		it while the first is still deciding and race them for it.

		Can't just self:Remove() here though: the entity still needs
		to exist so the later "choose" net message (core/sv_xp_crates.
		lua) can reference it and read its Amount. So instead it's
		hidden and made non-solid - gone as far as anyone else is
		concerned - and the claim flag is the actual gate (checked
		first, regardless of visibility/solidity) against a second
		Use() slipping through some other way.
	---------------------------------------------------------]]
	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() then return end
		if self.pdcity_Claimed then return end

		self.pdcity_Claimed = true
		self.pdcity_ClaimedBy = activator
		self:SetNoDraw(true)
		self:SetNotSolid(true)

		PDCity.OpenXPCrateMenuFor(activator, self)

		-- Safety net for someone who opens the menu and never actually
		-- chooses (alt-tabs away, disconnects mid-decision, etc.) - an
		-- invisible, unclaimed-by-anyone-else crate shouldn't sit there
		-- forever just because they never clicked Deposit.
		timer.Simple(120, function()
			if IsValid(self) then self:Remove() end
		end)
	end

	-- If the player currently deciding disconnects before choosing,
	-- there's no reason to wait out the full safety-net timer above.
	hook.Add("PlayerDisconnected", "pdcity_XPCrateClaimCleanup", function(ply)
		for _, ent in ipairs(ents.FindByClass("ent_pdcity_xpcrate")) do
			if ent.pdcity_ClaimedBy == ply then
				ent:Remove()
			end
		end
	end)

end

if CLIENT then

	function ENT:Draw()
		self:DrawModel()

		if EyePos():DistToSqr(self:GetPos()) > 250 * 250 then return end

		local ang = Angle(0, EyeAngles().y - 90, 90)
		cam.Start3D2D(self:GetPos() + Vector(0, 0, 14), ang, 0.25)
			draw.SimpleTextOutlined("+" .. self:GetAmount() .. " XP", "PDCity_Heading", 0, 0,
				Color(140, 180, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
		cam.End3D2D()
	end

end
