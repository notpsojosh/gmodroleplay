--[[---------------------------------------------------------
	Given to a player the moment they're cuffed (PDCity.CuffPlayer,
	core/sv_arrests.lua) in place of every weapon they were carrying -
	it's their only weapon until they're uncuffed or released from jail,
	deliberately with no model and no function, satisfying "cuffed
	players can't equip anything" without needing a separate block on
	weapon switching (there's nothing else to switch to).
-----------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Cuffed"
SWEP.Author = ""
SWEP.Category = "PD Roleplay"
SWEP.Spawnable = false

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

SWEP.Slot = 0
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false

function SWEP:ShouldDrawViewModel()
	return false
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 1)
	if SERVER and IsValid(self:GetOwner()) then
		self:GetOwner():ChatPrint("[" .. PDCity.BRAND_TAG .. "] You're cuffed - you can't do that.")
	end
end

function SWEP:SecondaryAttack()
	self:PrimaryAttack()
end

function SWEP:Reload()
end
