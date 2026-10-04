AddCSLuaFile()

SWEP.PrintName = "Keys"
SWEP.Category = "Door System"
SWEP.Spawnable = true
SWEP.Base = "weapon_base"
SWEP.Author = "OPGman"
SWEP.Slot = 1 -- SWEP.Slot is 0-indexed, so this displays as slot 2
-- c_arms is GMod's built-in empty arms model - invisible like "" was, but
-- a real model, so the viewmodel no longer spams "Bad pstudiohdr in
-- GetSequenceLinearMotion()!" when this is deployed.
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.UseHands = false
SWEP.WorldModel = ""

SWEP.Primary.Ammo = "none"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false

SWEP.Secondary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false

function SWEP:Initialize()
	self:SetHoldType( "normal" )
end

function SWEP:ShouldDrawViewModel()
	return false
end

local function KeySound( ply, lock )
	ply:EmitSound( "npc/metropolice/gear"..math.random( 1, 6 )..".wav" )
	timer.Simple( 1, function()
		if lock then
			ply:EmitSound( "doors/door_latch1.wav" )
		else
			ply:EmitSound( "doors/door_latch3.wav" )
		end
	end )
end

-- A few raps in quick succession reads as an actual knock, rather than
-- the single generic wood-impact thud this addon ships with by default.
--
-- KNOCK_COOLDOWN below is what actually rate-limits this (once per
-- player+door pair) - reported as spammable, since the only throttle
-- either attack function had was a single SetNextPrimaryFire(0.1)
-- shared incorrectly across both: the engine gates PrimaryAttack and
-- SecondaryAttack on TWO SEPARATE timers (NextPrimaryFire for left
-- click, NextSecondaryFire for right click), so that one call never
-- actually throttled whichever button it wasn't called from, and
-- alternating left/right could dodge it entirely regardless.
local KNOCK_COOLDOWN = 1
local lastKnock = {}

local function Knock( ply, door )
	local key = ply:SteamID64() .. "|" .. door:EntIndex()
	if ( lastKnock[key] or 0 ) + KNOCK_COOLDOWN > CurTime() then return end
	lastKnock[key] = CurTime()

	for i = 1, 3 do
		timer.Simple( ( i - 1 ) * 0.25, function()
			if IsValid( ply ) then
				ply:EmitSound( "physics/wood/wood_crate_impact_hard2.wav", 70, 100, 1, CHAN_ITEM )
			end
		end )
	end
end

-- Cleared on disconnect rather than left to grow forever - a SteamID64
-- key that'll never be looked up again otherwise.
hook.Add( "PlayerDisconnected", "pdcity_KeysKnockCleanup", function( ply )
	for key in pairs( lastKnock ) do
		if string.StartsWith( key, ply:SteamID64() .. "|" ) then
			lastKnock[key] = nil
		end
	end
end )

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire( CurTime() + 0.1 )
	self:SetNextSecondaryFire( CurTime() + 0.1 )
	if !IsFirstTimePredicted() or CLIENT then return end
	local door = self:GetOwner():GetDoor()
	if !IsValid( door ) then return end
	if self:GetOwner():CanUseDoor( door ) then
		door:Fire( "lock", "", 0 )
		KeySound( self:GetOwner(), true )
	else
		Knock( self:GetOwner(), door )
	end
end

function SWEP:SecondaryAttack()
	self:SetNextPrimaryFire( CurTime() + 0.1 )
	self:SetNextSecondaryFire( CurTime() + 0.1 )
	if !IsFirstTimePredicted() or CLIENT then return end
	local door = self:GetOwner():GetDoor()
	if !IsValid( door ) then return end
	if self:GetOwner():CanUseDoor( door ) then
		door:Fire( "unlock", "", 0 )
		KeySound( self:GetOwner() )
	else
		Knock( self:GetOwner(), door )
	end
end
