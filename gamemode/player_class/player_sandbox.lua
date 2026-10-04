
AddCSLuaFile()
DEFINE_BASECLASS( "player_default" )

if ( CLIENT ) then

	CreateConVar( "cl_playercolor", "0.24 0.34 0.41", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The value is a Vector - so between 0-1 - not between 0-255" )
	CreateConVar( "cl_weaponcolor", "0.30 1.80 2.10", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The value is a Vector - so between 0-1 - not between 0-255" )
	CreateConVar( "cl_playerskin", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The skin to use, if the model has any" )
	CreateConVar( "cl_playerbodygroups", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The bodygroups to use, if the model has any" )

end

local PLAYER = {}

-- Default player models: refugee01, refugee02, female05, female06
-- (paths taken from GMod's own player_manager.lua AddValidModel registry)
local DEFAULT_MODELS = {
	"models/player/Group02/male_02.mdl", -- refugee01
	"models/player/Group02/male_04.mdl", -- refugee02
	"models/player/Group01/female_05.mdl", -- female05
	"models/player/Group01/female_06.mdl", -- female06
}

PLAYER.DuckSpeed			= 0.1		-- How fast to go from not ducking, to ducking
PLAYER.UnDuckSpeed			= 0.1		-- How fast to go from ducking, to not ducking

-- In vanilla sandbox everyone sits on team 0 (unassigned), which is outside
-- the engine's CONTENTS_TEAM1-4 range that SetNoCollideWithTeammates acts on,
-- so players always collide there. PDCity puts every player on a real job
-- team (1+) instead, so the inherited true here would make same-team players
-- (everyone on the same job) pass straight through each other.
PLAYER.TeammateNoCollide	= false

--
-- Creates a Taunt Camera
--
PLAYER.TauntCam = TauntCamera()

--
-- See gamemodes/base/player_class/player_default.lua for all overridable variables
--
-- Kept in sync with core/sv_movement.lua's values - player_manager.OnPlayerSpawn
-- applies these straight from this class table on every spawn, so if these
-- disagree with sv_movement.lua, whichever runs last silently wins.
PLAYER.SlowWalkSpeed		= 100
PLAYER.WalkSpeed 			= 120 -- 100 * 1.2 (20% faster)
PLAYER.RunSpeed				= 240 -- 209 * 1.15 (15% faster on top of the earlier 10%)
PLAYER.CrouchedWalkSpeed	= 0.35
PLAYER.JumpPower			= 190

--
-- Set up the network table accessors
--
function PLAYER:SetupDataTables()

	BaseClass.SetupDataTables( self )

end


function PLAYER:Loadout()

	self.Player:RemoveAllAmmo()

	if ( cvars.Bool( "sbox_weapons", true ) ) then

		self.Player:GiveAmmo( 256,	"Pistol", 		true )
		self.Player:GiveAmmo( 256,	"SMG1", 		true )
		self.Player:GiveAmmo( 5,	"grenade", 		true )
		self.Player:GiveAmmo( 64,	"Buckshot", 	true )
		self.Player:GiveAmmo( 32,	"357", 			true )
		self.Player:GiveAmmo( 32,	"XBowBolt", 	true )
		self.Player:GiveAmmo( 6,	"AR2AltFire", 	true )
		self.Player:GiveAmmo( 100,	"AR2", 			true )

		self.Player:Give( "weapon_crowbar" )
		self.Player:Give( "weapon_pistol" )
		self.Player:Give( "weapon_smg1" )
		self.Player:Give( "weapon_frag" )
		self.Player:Give( "weapon_physcannon" )
		self.Player:Give( "weapon_crossbow" )
		self.Player:Give( "weapon_shotgun" )
		self.Player:Give( "weapon_357" )
		self.Player:Give( "weapon_rpg" )
		self.Player:Give( "weapon_ar2" )

		-- The only reason I'm leaving this out is because
		-- I don't want to add too many weapons to the first
		-- row because that's where the gravgun is.
		--pl:Give( "weapon_stunstick" )

	end

	self.Player:Give( "gmod_tool" )
	self.Player:Give( "gmod_camera" )
	self.Player:Give( "weapon_physgun" )

	self.Player:SwitchToDefaultWeapon()

end

function PLAYER:SetModel()

	-- Model comes from the player's current job (see core/sh_jobs.lua),
	-- falling back to the citizen pool if they have no job yet. Only the
	-- server chooses it - the model is a networked entity property, so
	-- every client (including this one) sees it automatically once set;
	-- picking randomly on both realms independently would just disagree.
	if ( SERVER ) then
		local job = PDCity.GetJob and PDCity.GetJob( self.Player:Team() )
		local modelname

		if ( job and job.Models and #job.Models > 0 ) then
			modelname = table.Random( job.Models )
		else
			-- No job model (or no job yet) - fall back to the character's
			-- own chosen player model (F1 Character Selection's "Change
			-- Model"), and only then to a random default if they haven't
			-- picked one.
			local chosen = PDCity.GetCharacterModel and PDCity.GetCharacterModel( self.Player )
			modelname = ( chosen and chosen ~= "" and chosen ) or table.Random( DEFAULT_MODELS )
		end

		util.PrecacheModel( modelname )
		self.Player:SetModel( modelname )

		-- Jobs own the player's appearance: skin and bodygroups come from
		-- the job definition, not the client's cl_playerskin /
		-- cl_playerbodygroups preferences (which base sandbox would apply
		-- here and silently stomp the uniform on every respawn).
		if ( job ) then
			PDCity.ApplyJobAppearance( self.Player, job )
		else
			self.Player:SetSkin( 0 )
		end
	end

end

--
-- Called when the player spawns
--
function PLAYER:Spawn()

	BaseClass.Spawn( self )

	local plyclr = self.Player:GetInfo( "cl_playercolor" )
	self.Player:SetPlayerColor( Vector( plyclr ) )

	local wepclr = Vector( self.Player:GetInfo( "cl_weaponcolor" ) )
	if ( wepclr:Length() < 0.001 ) then
		wepclr = Vector( 0.001, 0.001, 0.001 )
	end
	self.Player:SetWeaponColor( wepclr )

end

--
-- Return true to draw local (thirdperson) camera - false to prevent - nothing to use default behaviour
--
function PLAYER:ShouldDrawLocal()

	if ( self.TauntCam:ShouldDrawLocalPlayer( self.Player, self.Player:IsPlayingTaunt() ) ) then return true end

	-- Draw the player model while in our own thirdperson view (see
	-- cl_thirdperson.lua, toggled by "!tpp").
	if ( CLIENT and PDCity.ThirdpersonEnabled and self.Player == LocalPlayer() ) then return true end

end

--
-- Allow player class to create move
--
function PLAYER:CreateMove( cmd )

	if ( self.TauntCam:CreateMove( cmd, self.Player, self.Player:IsPlayingTaunt() ) ) then return true end

end

--
-- Allow changing the player's view
--
local THIRDPERSON_DISTANCE = 70
local THIRDPERSON_HEIGHT = 10
local THIRDPERSON_TRACE_SIZE = 4 -- half-extent of the hull traced back from the player, so the camera stops at walls instead of clipping through

function PLAYER:CalcView( view )

	if ( self.TauntCam:CalcView( view, self.Player, self.Player:IsPlayingTaunt() ) ) then return true end

	-- Thirdperson (see cl_thirdperson.lua, toggled by "!tpp"). Only ever
	-- moves the render camera - aiming/shooting use EyeAngles/eye traces
	-- elsewhere in the engine, which CalcView doesn't touch, so this
	-- can't be used to see over walls while shooting through them or
	-- anything else that would need restricting.
	if ( CLIENT and PDCity.ThirdpersonEnabled and self.Player == LocalPlayer() and not self.Player:InVehicle() ) then

		local desired = view.origin + view.angles:Forward() * -THIRDPERSON_DISTANCE + Vector( 0, 0, THIRDPERSON_HEIGHT )

		local tr = util.TraceHull( {
			start = view.origin,
			endpos = desired,
			mins = Vector( -THIRDPERSON_TRACE_SIZE, -THIRDPERSON_TRACE_SIZE, -THIRDPERSON_TRACE_SIZE ),
			maxs = Vector( THIRDPERSON_TRACE_SIZE, THIRDPERSON_TRACE_SIZE, THIRDPERSON_TRACE_SIZE ),
			filter = self.Player,
			mask = MASK_SOLID,
		} )

		view.origin = tr.HitPos
		view.drawviewer = true

		return true

	end

end

--
-- Reproduces the jump boost from HL2 singleplayer
--
local JUMPING

function PLAYER:StartMove( move )

	-- Only apply the jump boost in FinishMove if the player has jumped during this frame
	-- Using a global variable is safe here because nothing else happens between SetupMove and FinishMove
	if bit.band( move:GetButtons(), IN_JUMP ) ~= 0 and bit.band( move:GetOldButtons(), IN_JUMP ) == 0 and self.Player:OnGround() then
		JUMPING = true
	end

end

function PLAYER:FinishMove( move )

	-- If the player has jumped this frame
	if ( JUMPING ) then
		-- Get their orientation
		local forward = move:GetAngles()
		forward.p = 0
		forward = forward:Forward()

		-- Compute the speed boost

		-- HL2 normally provides a much weaker jump boost when sprinting
		-- For some reason this never applied to GMod, so we won't perform
		-- this check here to preserve the "authentic" feeling
		local speedBoostPerc = ( ( not self.Player:Crouching() ) and 0.5 ) or 0.1

		local speedAddition = math.abs( move:GetForwardSpeed() * speedBoostPerc )
		local maxSpeed = move:GetMaxSpeed() * ( 1 + speedBoostPerc )
		local newSpeed = speedAddition + move:GetVelocity():Length2D()

		-- Clamp it to make sure they can't bunnyhop to ludicrous speed
		if newSpeed > maxSpeed then
			speedAddition = speedAddition - ( newSpeed - maxSpeed )
		end

		-- Reverse it if the player is running backwards
		if move:GetVelocity():Dot( forward ) < 0 then
			speedAddition = -speedAddition
		end

		-- Apply the speed boost
		move:SetVelocity( forward * speedAddition + move:GetVelocity() )
	end

	JUMPING = nil

end

player_manager.RegisterClass( "player_sandbox", PLAYER, "player_default" )
