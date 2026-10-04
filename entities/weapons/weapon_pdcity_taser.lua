--[[---------------------------------------------------------
	Taser. Given out through job weapon loadouts (F1 > Catalogue > Jobs),
	and spawnable from the Q menu by anyone allowed to spawn weapons.

	Uses HL2's own stock stunstick model/sounds (models/weapons/
	v_stunstick.mdl + w_stunstick.mdl, weapons/stunstick/*) - bundled
	with every Garry's Mod install, no Workshop content required, so
	this works out of the box for anyone who installs this gamemode.
	PrimaryAttack logic is adapted from JJL772's Garry's Mod Taser
	(https://github.com/JJL772/Garry-s-Mod-Taser), whose README says "Feel
	free to use this for whatever you want." Credited on the store page.

	Stun behaviour is NOT a ragdoll/force-respawn trick - that would
	collide with our own job/loadout system (a stunned player shouldn't
	lose their inventory or trigger PlayerSpawn mid-arrest). Reuses the
	same Player:Freeze() approach as cuffing (core/sv_arrests.lua)
	instead: frozen for STUN_DURATION, then released - unless they got
	cuffed while frozen, in which case cuffing owns the freeze from that
	point on.
-----------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Taser"
SWEP.Author = ""
SWEP.Category = "PD Roleplay"
SWEP.Spawnable = true

SWEP.Base = "weapon_base"
SWEP.HoldType = "melee"

SWEP.ViewModel = "models/weapons/v_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunstick.mdl"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Slot = 1
SWEP.SlotPos = 2
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

local TASER_RANGE = 1000
local STUN_DURATION = 5
local TASER_COOLDOWN = 8 -- longer than the stun so a target can't be re-tased the instant they're released

-- Played from the TARGET's position (not the shooter's) so anyone
-- nearby hears it too, not just whoever fired - that's the whole
-- point, versus the shooter-only fire sound already in PrimaryAttack.
-- Both are stock HL2 stunstick sounds, bundled with every install.
local TASER_HIT_SOUNDS = {
	"weapons/stunstick/stunstick_fleshhit1.wav",
	"weapons/stunstick/stunstick_fleshhit2.wav",
}
local TASER_PAIN_SOUNDS = {
	"player/pl_pain5.wav",
	"player/pl_pain6.wav",
	"player/pl_pain7.wav",
}

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
	util.PrecacheModel(self.ViewModel)
	util.PrecacheModel(self.WorldModel)
end

if SERVER then

	function SWEP:PrimaryAttack()
		self:SetNextPrimaryFire(CurTime() + TASER_COOLDOWN)

		local ply = self:GetOwner()
		if not IsValid(ply) then return end

		self:EmitSound("weapons/stunstick/stunstick_swing2.wav")

		local tr = util.TraceLine({
			start = ply:GetShootPos(),
			endpos = ply:GetShootPos() + ply:GetAimVector() * TASER_RANGE,
			filter = ply,
			mask = MASK_SHOT,
		})

		local target = tr.Entity
		if not IsValid(target) or not target:IsPlayer() or target == ply then return end
		if PDCity.IsStaff(target) then return end
		if target.pdcity_IsStunned or target.pdcity_IsCuffed or target.pdcity_IsJailed then return end

		target.pdcity_IsStunned = true
		PDCity.SetPlayerFrozen(target, true)
		target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You've been tased by " .. PDCity.GetDisplayName(ply) .. "!")

		-- Emitted from the TARGET, not the shooter, so anyone standing
		-- nearby hears it too - that's the point, versus the fire
		-- sound above which only the shooter's weapon plays.
		target:EmitSound(table.Random(TASER_HIT_SOUNDS), 75)
		target:EmitSound(table.Random(TASER_PAIN_SOUNDS), 75)

		timer.Simple(STUN_DURATION, function()
			if not IsValid(target) then return end
			target.pdcity_IsStunned = nil
			-- Only release the freeze if nothing else (cuffing) has since
			-- taken ownership of it.
			if not target.pdcity_IsCuffed and not target.pdcity_IsJailed then
				PDCity.SetPlayerFrozen(target, false)
			end
		end)
	end

	function SWEP:SecondaryAttack()
	end

end

if CLIENT then

	-- GetNextPrimaryFire() is the same value SetNextPrimaryFire() wrote
	-- server-side in PrimaryAttack above - it's a normal networked
	-- weapon field, so no extra net message is needed to show it here.
	function SWEP:DrawHUD()

		local remaining = self:GetNextPrimaryFire() - CurTime()
		if remaining <= 0 then return end

		local w, h = 220, 8
		local x, y = ScrW() / 2 - w / 2, ScrH() - 140

		draw.SimpleTextOutlined(("TASER RECHARGING: %.1fs"):format(remaining), "PDCity_Heading", ScrW() / 2, y - 6,
			Color(230, 170, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 220))

		local frac = 1 - (remaining / TASER_COOLDOWN)
		draw.RoundedBox(2, x, y, w, h, Color(40, 40, 40, 200))
		draw.RoundedBox(2, x, y, w * math.Clamp(frac, 0, 1), h, Color(230, 170, 70, 230))

	end

end
