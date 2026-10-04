--[[---------------------------------------------------------
	Lockpick. Bypasses a door's lock without needing keys/ownership -
	aim at a door and click to start; keep looking at that same door
	for a random 4-8s "picking" duration without switching weapons or
	looking away, then a coin-flip decides whether it actually unlocks.

	Model: HL2's own stock crowbar for both view and world model - no
	Workshop content needed, works on every install.

	Door detection/unlocking reuses the mounted Universal Door System
	addon (gamemode/doors/): Player:GetDoor() finds the
	door under the crosshair within that addon's own configured
	DOOR_CONFIG_DISTANCE, and Entity:Fire("Unlock") is the same input
	weapon_keys.lua uses. Deliberately skips that addon's CanUseDoor
	ownership check - the whole point of a lockpick is bypassing a lock
	you don't have legitimate access to.

	Vehicle locks use whatever Lock()/UnLock() methods the vehicle
	entity itself exposes (IsLockableVehicle below) - written against
	simfphys, but not hardcoded to it specifically, so it works with any
	vehicle addon that exposes the same two methods and safely skips
	anything that doesn't (stock HL2 vehicles included) rather than
	erroring on them.

	Not given out by any job's default loadout - add it to the F4 shop
	via the admin editor (F4 > Entities > Manage Catalogue) with
	Class = "weapon_pdcity_lockpick" and whatever job/rank/price
	restrictions make sense.
-----------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Lockpick"
SWEP.Author = ""
SWEP.Category = "PD Roleplay"
SWEP.Spawnable = true

SWEP.Base = "weapon_base"
SWEP.HoldType = "melee"

SWEP.ViewModel = "models/weapons/v_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_crowbar.mdl"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Slot = 3
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

local PICK_MIN_TIME = 4
local PICK_MAX_TIME = 8
local SUCCESS_CHANCE = 0.5
local RETRY_COOLDOWN = 3 -- after a failed attempt, before trying again
local CHECK_INTERVAL = 0.25 -- how often we re-verify the player hasn't looked away/switched weapons

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
	util.PrecacheModel(self.ViewModel)
	util.PrecacheModel(self.WorldModel)
end

if SERVER then

	local DOUBLE_DOOR_RADIUS = 130

	-- Double doors are usually two separate door entities standing next
	-- to each other, only sometimes linked by the map's own slavename
	-- I/O - rather than depend on that, just also fire Unlock/Open at
	-- any other door entity within a typical double-door's width.
	local function GetNearbyDoors(door)
		local nearby = {}
		for _, ent in ipairs(ents.FindInSphere(door:GetPos(), DOUBLE_DOOR_RADIUS)) do
			if ent ~= door and IsValidDoor(ent) then
				table.insert(nearby, ent)
			end
		end
		return nearby
	end

	-- Unlocks AND opens - a picked lock should swing the door open
	-- immediately rather than leave the player to still push it, and
	-- covers the other leaf of a double door too (see GetNearbyDoors).
	local function UnlockAndOpen(door)
		door:Fire("Unlock", "", 0)
		door:Fire("Open", "", 0)

		for _, other in ipairs(GetNearbyDoors(door)) do
			other:Fire("Unlock", "", 0)
			other:Fire("Open", "", 0)
		end
	end

	local VEHICLE_RANGE = 130

	-- Doesn't assume simfphys specifically (or any other addon by name) -
	-- just checks the entity actually has Lock/UnLock methods, which is
	-- exactly what's needed right below and what SetNWBool-syncing the
	-- lock state to the HUD assumes too. Works with simfphys vehicles
	-- (what this was written against) and anything else that happens to
	-- expose the same two methods, and safely skips stock HL2 vehicles
	-- or anything else that doesn't - no hardcoded base-class name to
	-- get out of sync with whatever vehicle addon is actually installed.
	local function IsLockableVehicle(ent)
		return IsValid(ent) and isfunction(ent.Lock) and isfunction(ent.UnLock)
	end

	--[[-------------------------------------------------------
		What this pick is currently pointed at: a door (via the door
		system's own lookup, which already handles its distance rule),
		a vehicle, or a printer - all in front of the player.

		Returns the entity plus which kind it is, because all three
		unlock in completely different ways - a door takes engine I/O,
		a vehicle uses simfphys's native Lock()/UnLock(), and a printer
		grants temporary steal access instead of "unlocking" anything
		(core/sv_printers.lua).
	---------------------------------------------------------]]
	local function GetLockpickTarget(ply)
		local door = ply:GetDoor()
		if IsValid(door) then return door, "door" end

		local tr = util.TraceLine({
			start = ply:GetShootPos(),
			endpos = ply:GetShootPos() + ply:GetAimVector() * VEHICLE_RANGE,
			filter = ply,
		})

		local ent = tr.Entity
		if IsValid(ent) then
			if IsLockableVehicle(ent) then return ent, "vehicle" end
			if PDCity.PRINTER_CLASSES[ent:GetClass()] then return ent, "printer" end
		end

		return nil, nil
	end

	local function TimerName(ply)
		return "pdcity_lockpick_" .. ply:EntIndex()
	end

	local function StopPicking(ply)
		timer.Remove(TimerName(ply))
		if IsValid(ply) then ply:SetNWBool("PDCity_IsLockpicking", false) end
	end

	function SWEP:Holster()
		StopPicking(self:GetOwner())
		return true
	end

	function SWEP:OnRemove()
		StopPicking(self:GetOwner())
	end

	function SWEP:PrimaryAttack()
		self:SetNextPrimaryFire(CurTime() + 0.3)

		local ply = self:GetOwner()
		if not IsValid(ply) then return end

		if ply:GetNWBool("PDCity_IsLockpicking", false) then return end

		if (ply.pdcity_NextLockpickAttempt or 0) > CurTime() then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Give it a moment before trying again.")
			return
		end

		local target, kind = GetLockpickTarget(ply)
		if not IsValid(target) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You need to be looking at a door, vehicle, or printer to pick its lock.")
			return
		end

		local duration = math.Rand(PICK_MIN_TIME, PICK_MAX_TIME)
		local endTime = CurTime() + duration

		ply:SetNWBool("PDCity_IsLockpicking", true)
		ply:SetNWFloat("PDCity_LockpickEndTime", endTime)
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Picking the lock... hold still and keep looking at it.")

		-- Vehicle alarm hook - simfphys has no built-in alarm, but
		-- other addons can listen for this hook if needed. A no-op
		-- for doors and printers.
		if kind == "vehicle" then
			hook.Run("lockpickStarted", ply, target, {})
		end

		local weapon = self

		timer.Create(TimerName(ply), CHECK_INTERVAL, 0, function()

			if not IsValid(ply) or not ply:Alive() then
				StopPicking(ply)
				return
			end

			if not IsValid(weapon) or ply:GetActiveWeapon() ~= weapon then
				StopPicking(ply)
				return
			end

			if GetLockpickTarget(ply) ~= target then
				StopPicking(ply)
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You stopped picking the lock.")
				return
			end

			if CurTime() < endTime then return end

			-- Duration complete - stop checking and roll the outcome.
			timer.Remove(TimerName(ply))
			ply:SetNWBool("PDCity_IsLockpicking", false)

			if not IsValid(target) then return end

			if math.random() <= SUCCESS_CHANCE then
				if kind == "vehicle" then
					target:UnLock()
					target:SetNWBool("PDCity_DoorsLocked", false)
				elseif kind == "printer" then
					PDCity.GrantPrinterStealAccess(ply, target)
				else
					UnlockAndOpen(target)
				end

				ply:EmitSound("doors/door_latch3.wav")
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] The lock clicks open!")
				PDCity.GameLog("lockpicks", ply:Nick() .. " (" .. ply:SteamID() .. ") picked a " .. tostring(kind) .. " lock (" .. target:GetClass() .. ")")
			else
				ply.pdcity_NextLockpickAttempt = CurTime() + RETRY_COOLDOWN
				ply:EmitSound("doors/latchlocked2.wav")
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your lockpick slipped - you failed to pick the lock.")
				PDCity.GameLog("lockpicks", ply:Nick() .. " (" .. ply:SteamID() .. ") FAILED picking a " .. tostring(kind) .. " lock")
			end

		end)
	end

	function SWEP:SecondaryAttack()
	end

end

if CLIENT then

	hook.Add("HUDPaint", "pdcity_LockpickProgress", function()
		local ply = LocalPlayer()
		if not IsValid(ply) or not ply:GetNWBool("PDCity_IsLockpicking", false) then return end

		local weapon = ply:GetActiveWeapon()
		if not IsValid(weapon) or weapon:GetClass() ~= "weapon_pdcity_lockpick" then return end

		-- Counts down to the end time rather than filling a bar - we
		-- don't know the randomly-picked total duration client-side,
		-- just when it ends, and a second networked value isn't worth
		-- it for this.
		local remaining = math.max(0, ply:GetNWFloat("PDCity_LockpickEndTime", 0) - CurTime())

		draw.SimpleTextOutlined(string.format("Picking lock... %.1fs", remaining), "PDCity_Body",
			ScrW() / 2, ScrH() / 2 + 80, Color(230, 200, 90),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 220))
	end)

end
