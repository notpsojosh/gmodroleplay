--[[---------------------------------------------------------
	Warrant Request tool. Aim and left-click while holding it to open the
	request form (cl_warrant_request.lua) - submitting sends it to the
	warrant approvers set in Site Admin (core/sv_wanted.lua), who can
	approve (marks the target WANTED for 10 minutes) or deny it. Holding
	this tool is the permission to request: the owner decides which jobs
	get it through their weapon loadouts. Checked server-side in the net
	receiver - this only ever opens the form.

	Model: HL2's own stock lab binder (models/props_lab/binderblue.mdl) -
	bundled with every Garry's Mod install, no Workshop content needed.
	It's a plain prop, not a rigged viewmodel, so UseHands = true tells
	the engine to draw the player's own default viewmodel hands holding
	it rather than expecting the prop itself to animate.
-----------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Warrant Request"
SWEP.Author = ""
SWEP.Category = "PD Roleplay"
SWEP.Spawnable = true
SWEP.AdminSpawnable = true

SWEP.Base = "weapon_base"
SWEP.HoldType = "normal"

SWEP.ViewModel = "models/props_lab/binderblue.mdl"
SWEP.WorldModel = "models/props_lab/binderblue.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Slot = 3
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
	util.PrecacheModel(self.ViewModel)
	util.PrecacheModel(self.WorldModel)
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.5)

	if CLIENT and IsFirstTimePredicted() then
		PDCity.OpenWarrantRequest()
	end
end

function SWEP:SecondaryAttack()
end
