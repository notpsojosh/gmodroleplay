--[[---------------------------------------------------------
	Handcuffs. Issued to every police job (see core/sh_jobs.lua), also
	spawnable from the Q menu.

	Left click on another player (anyone not staff, not already
	cuffed/jailed, not yourself): if they haven't moved for
	CUFF_HOLD_TIME seconds, they're cuffed (see PDCity.CuffPlayer in
	core/sv_arrests.lua), which opens the arrest menu for the officer.

	No stock HL2/GMod content ships an actual handcuffs prop, and cuffing
	someone is a hands-on action rather than something you'd hold anyway
	- so this deliberately has no world/view model at all (bare hands),
	which needs no Workshop content and works on every install.
-----------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Handcuffs"
SWEP.Author = ""
SWEP.Category = "PD Roleplay"
SWEP.Spawnable = true

SWEP.Base = "weapon_base"
SWEP.HoldType = "normal"

-- c_arms is GMod's built-in empty arms model - invisible like "" was, but
-- a real model, so the viewmodel no longer spams "Bad pstudiohdr in
-- GetSequenceLinearMotion()!" when this is deployed.
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.UseHands = false
SWEP.WorldModel = ""

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Slot = 4
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

local CUFF_RANGE = 150
local CUFF_HOLD_TIME = 1
local CUFF_MOVE_TOLERANCE = 48 -- how far the target may drift during the hold and still count as "stayed put"

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
	-- No view/world model on purpose (see file header) - nothing to precache.
end

if SERVER then

	function SWEP:PrimaryAttack()
		self:SetNextPrimaryFire(CurTime() + CUFF_HOLD_TIME)

		local ply = self:GetOwner()
		if not IsValid(ply) then return end

		-- An explicit trace with a known range, rather than
		-- Player:GetEyeTrace() (a native with no documented/inspectable
		-- range here) - this way "too far to reach" and "nothing there"
		-- can't be confused with each other regardless of what that
		-- native's own default distance actually is.
		local tr = util.TraceLine({
			start = ply:GetShootPos(),
			endpos = ply:GetShootPos() + ply:GetAimVector() * CUFF_RANGE,
			filter = ply,
			mask = MASK_SHOT,
		})
		local target = tr.Entity

		if not IsValid(target) or not target:IsPlayer() or target == ply then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Nobody within " .. CUFF_RANGE .. " units to cuff there.")
			return
		end

		if PDCity.IsStaff(target) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't arrest staff.")
			return
		end

		if target.pdcity_IsCuffed or target.pdcity_IsJailed then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] They're already cuffed.")
			return
		end

		if target.pdcity_BeingCuffed then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Someone's already cuffing them.")
			return
		end

		target.pdcity_BeingCuffed = true
		local startPos = target:GetPos()

		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Hold still...")
		target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(ply) .. " is putting on handcuffs - don't move!")

		timer.Simple(CUFF_HOLD_TIME, function()
			if not IsValid(target) then return end
			target.pdcity_BeingCuffed = nil

			if not IsValid(ply) then return end
			if not target:Alive() or target.pdcity_IsCuffed or target.pdcity_IsJailed then return end

			if target:GetPos():DistToSqr(startPos) > CUFF_MOVE_TOLERANCE * CUFF_MOVE_TOLERANCE then
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] They moved - cuffing failed.")
				target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You broke free of the cuffing attempt.")
				return
			end

			PDCity.CuffPlayer(target, ply)
		end)
	end

	function SWEP:SecondaryAttack()
	end

end
