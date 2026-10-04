--[[---------------------------------------------------------
	Money printer - original PD City entity, not based on any existing
	printer addon. Uses a stock Half-Life 2 model that ships with every
	Garry's Mod install, so no Workshop content is needed.

	Mechanics (see core/sv_printers.lua for the purchase/interaction
	logic, cl_printer_menu.lua for the interface):
	  - Starts locked, holding $0. Press E (owner only) to open the
	    interface and pay to unlock.
	  - Once unlocked, prints money on a timer into its held balance,
	    collected via the interface.
	  - Two per-printer upgrade tracks (print speed, print amount), plus
	    a per-player "additional printers" cap increase.
	  - Can ONLY be destroyed by a police stunstick (ENT:OnTakeDamage
	    ignores every other damage source outright).
	  - Cannot be physgunned (and therefore never frozen) or toolgunned
	    by anyone but the server owner.
	  - Session-only: never persisted. Removed on the owner's disconnect
	    (core/sv_printers.lua).

	This is the "standard" printer profile (core/sv_printers.lua's
	PDCity.PRINTER_TYPES) and is police-blocked (see CanBuyPrinter in
	core/sh_f4_entities.lua).
-----------------------------------------------------------]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Money Printer"
ENT.Category = "PD Roleplay"
ENT.Author = ""
ENT.Spawnable = true
ENT.AdminOnly = true

local MODEL = "models/props_c17/consolebox01a.mdl"
local STUNSTICK_HITS_TO_DESTROY = 3

-- Static field (not just the local above) so generic tools that read it
-- off the class table work without needing this file to run first -
-- e.g. the F4 admin/shop card preview (cl_f4_menu.lua's ResolveEntityModel).
ENT.Model = MODEL

if SERVER then

	function ENT:Initialize()
		self:SetModel(MODEL)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			-- Motion stays ENABLED: the printer can't be physgunned or
			-- frozen (see PhysgunPickup / SetUnFreezable below), but it's
			-- meant to still be pushable and gravity-gun-movable like a
			-- normal physics prop, which a motion-disabled object can't be.
			phys:Wake()
		else
			-- No valid physics object means SOLID_VPHYSICS gave the entity
			-- NO collision (the same trap documented in ent_pdcity_bail.lua),
			-- e.g. if a server owner swaps MODEL for one that isn't mounted -
			-- the error model carries no .phy collision mesh. Without
			-- collision the +use trace passes straight through and pressing E
			-- does nothing. A plain bounding box restores collision (and Use)
			-- regardless of whether the real model ever loads.
			local mins, maxs = Vector(-22, -22, 0), Vector(22, 22, 44)
			self:PhysicsInitBox(mins, maxs)
			self:SetMoveType(MOVETYPE_NONE)
			self:SetSolid(SOLID_BBOX)
			self:SetCollisionBounds(mins, maxs)

			local boxPhys = self:GetPhysicsObject()
			if IsValid(boxPhys) then boxPhys:EnableMotion(false) end
		end

		-- Right-click physgun freeze toggles motion directly (weapon_
		-- physgun's SecondaryAttack) without ever going through
		-- PhysgunPickup below - GetUnFreezable() is the native flag
		-- GM:OnPhysgunFreeze (core/sv_physgun_players.lua) itself already
		-- checks, so this is the actual mechanism that blocks freezing,
		-- not just a belt-and-suspenders extra.
		self:SetUnFreezable(true)

		self.pdcity_Unlocked = false
		self.pdcity_HeldMoney = 0
		self.pdcity_SpeedLevel = 0
		self.pdcity_AmountLevel = 0
		self.pdcity_HitsTaken = 0

		self.pdcity_PrinterType = "standard"
	end

	-- Cap check happens here, before ents.Create, rather than in
	-- Initialize - rejecting there would mean creating the entity and
	-- immediately :Remove()-ing it right before this function's own
	-- :Activate() call runs on an already-removed entity.
	function ENT:SpawnFunction(ply, tr, className)
		if not tr.Hit then return end
		if not IsValid(ply) then return end

		if not PDCity.CanSpawnPrinter(ply, className) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You already have the maximum of " .. PDCity.GetMaxPrinters(ply, className) .. " of these.")
			return
		end

		local ent = ents.Create(className)
		ent:SetPos(tr.HitPos + tr.HitNormal * 4)
		ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
		ent.pdcity_Owner = ply
		ent:Spawn()
		ent:Activate()

		PDCity.TrackPrinter(ent, ply)

		return ent
	end

	function ENT:OnRemove()
		timer.Remove(self:GetPrintTimerName())

		local owner = self.pdcity_Owner
		if IsValid(owner) and owner.pdcity_Printers then
			table.RemoveByValue(owner.pdcity_Printers, self)
		end
	end

	function ENT:GetPrintTimerName()
		return "pdcity_printer_print_" .. self:EntIndex()
	end

	-- Which entry in PDCity.PRINTER_TYPES (core/sv_printers.lua) this
	-- particular printer uses - always "standard", the only type.
	function ENT:GetPrinterProfile()
		return PDCity.PRINTER_TYPES[self.pdcity_PrinterType or "standard"] or PDCity.PRINTER_TYPES.standard
	end

	function ENT:GetPrintInterval()
		local profile = self:GetPrinterProfile()
		return profile.BaseInterval - (self.pdcity_SpeedLevel * profile.SpeedStep)
	end

	function ENT:GetPrintAmount()
		local profile = self:GetPrinterProfile()
		return profile.BaseAmount + (self.pdcity_AmountLevel * profile.AmountStep)
	end

	-- (Re)starts the print timer at the printer's current speed level.
	-- Safe to call again after a speed upgrade - timer.Create on an
	-- existing name just resets it with the new interval.
	function ENT:StartPrinting()
		local ent = self
		timer.Create(self:GetPrintTimerName(), self:GetPrintInterval(), 0, function()
			if not IsValid(ent) then return end
			ent.pdcity_HeldMoney = ent.pdcity_HeldMoney + ent:GetPrintAmount()
		end)
	end

	-- Only the server owner may use ANY toolgun mode on a printer.
	function ENT:CanTool(ply, trace, mode, tool, button)
		return PDCity.IsOwner(ply)
	end

	-- Can't be picked up, moved, or frozen with the physgun by anyone,
	-- including the server owner - once placed it stays put, same as
	-- money printers on most other servers.
	function ENT:PhysgunPickup(ply)
		return false
	end

	-- Only the owner may open the interface - UNLESS the activator just
	-- picked its lock (core/sv_printers.lua's pdcity_StealAccess), in
	-- which case they get the same interface for exactly long enough to
	-- collect the cash before the pick expires.
	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() then return end

		if activator ~= self.pdcity_Owner and self.pdcity_StealAccess ~= activator then
			activator:ChatPrint("[" .. PDCity.BRAND_TAG .. "] This isn't your printer.")
			return
		end

		PDCity.OpenPrinterMenuFor(activator, self)
	end

	-- Ignores every damage source except a player actively swinging a
	-- police stunstick - explosions, bullets, fire, fall, etc. all do
	-- nothing. Tracked as a hit counter rather than raw damage points so
	-- balance doesn't depend on the stunstick's configured damage value.
	function ENT:OnTakeDamage(dmginfo)
		local attacker = dmginfo:GetAttacker()
		if not IsValid(attacker) or not attacker:IsPlayer() then return end

		local weapon = attacker:GetActiveWeapon()
		if not IsValid(weapon) or weapon:GetClass() != "weapon_stunstick" then return end

		self.pdcity_HitsTaken = self.pdcity_HitsTaken + 1
		attacker:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. self.PrintName .. " hit (" .. self.pdcity_HitsTaken .. "/" .. STUNSTICK_HITS_TO_DESTROY .. ")")

		if self.pdcity_HitsTaken >= STUNSTICK_HITS_TO_DESTROY then
			local owner = self.pdcity_Owner
			if IsValid(owner) then
				owner:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(attacker) .. " destroyed your " .. self.PrintName .. ".")
			end

			PDCity.GrantPrinterDestroyXP(attacker, owner, self)

			self:Remove()
		end
	end

end
