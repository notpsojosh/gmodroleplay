--[[---------------------------------------------------------
	Weapon safety catch. USE + RELOAD together toggles the safety on
	whatever you're holding: while it's on the weapon can't fire, and
	it's held in a lowered/neutral pose.

	Deliberately built here rather than relying on a weapon pack that
	ships the feature - this works with ANY weapon base (M9K, ArcCW,
	ARC9, CW2, TFA, FA:S, the gamemode's own SWEPs) because it operates
	on the player's input command rather than anything base-specific.

	WHY THIS IS SHARED, not server-only:

	Weapon firing is a *predicted* action - the client runs the weapon's
	code too, and only gets corrected if the server disagrees. Stripping
	the keys on the server alone produced two bugs:

	  - the client still predicted a shot, played the animation and
	    decremented the clip, then had its ammo corrected back by the
	    server. That reads in-game as unlimited ammo.
	  - the client-side weapon code still saw IN_RELOAD and ran its own
	    firemode-switch logic, so toggling safety also flipped firemode.

	So the input stripping has to happen on both realms. The server
	still owns the actual on/off decision (and networks it), the client
	just needs to agree about the buttons so its prediction matches.
-----------------------------------------------------------]]

local SAFE_HOLDTYPE = "passive" -- lowered, both hands, nothing pointed

-- Read from the networked value rather than a plain Lua field, so both
-- realms agree - a client-only field would be nil on the client and the
-- prediction would diverge again.
local function IsSafetyOn(wep)
	return IsValid(wep) and wep:GetNWBool("PDCity_Safety", false)
end

if SERVER then

	function PDCity.SetWeaponSafety(ply, wep, on)

		wep:SetNWBool("PDCity_Safety", on)

		if on then
			-- Captured only on the way IN, so repeated toggles can't
			-- overwrite the original with "passive".
			wep.pdcity_HoldTypeBeforeSafety = wep:GetHoldType()
			wep:SetHoldType(SAFE_HOLDTYPE)
		else
			wep:SetHoldType(wep.pdcity_HoldTypeBeforeSafety or "normal")
		end

		ply:EmitSound("weapons/smg1/switch_single.wav", 55, on and 90 or 110)
		ply:ChatPrint(on
			and "[" .. PDCity.BRAND_TAG .. "] Safety ON - weapon lowered and can't fire."
			or "[" .. PDCity.BRAND_TAG .. "] Safety OFF.")

	end

	-- A weapon handed out fresh should never start on safety - a gun
	-- that silently won't fire is the worst possible surprise.
	hook.Add("WeaponEquip", "pdcity_ClearSafetyOnEquip", function(wep)
		if not IsValid(wep) then return end
		wep:SetNWBool("PDCity_Safety", false)
	end)

end

--[[---------------------------------------------------------
	StartCommand sees the player's input before the weapon acts on it,
	so removing IN_ATTACK here stops the shot rather than trying to undo
	it afterwards. Runs clientside for the local player (prediction) and
	serverside for everyone (authority).
-----------------------------------------------------------]]

hook.Add("StartCommand", "pdcity_WeaponSafety", function(ply, cmd)

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) then return end

	if cmd:KeyDown(IN_USE) and cmd:KeyDown(IN_RELOAD) then

		-- Swallowed on BOTH realms - this is what stops the weapon base
		-- seeing a reload press and switching firemode behind our back.
		cmd:RemoveKey(IN_RELOAD)
		cmd:RemoveKey(IN_USE)

		-- Only the server decides; edge-triggered so it fires once per
		-- press rather than every tick the keys are held.
		if SERVER and not ply.pdcity_SafetyComboHeld then
			ply.pdcity_SafetyComboHeld = true
			PDCity.SetWeaponSafety(ply, wep, not IsSafetyOn(wep))
		end

	elseif SERVER then
		ply.pdcity_SafetyComboHeld = nil
	end

	if IsSafetyOn(wep) then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)

		-- Belt and braces. Some bases fire from their own Think rather
		-- than from the button state in the command, and every base
		-- respects the next-fire timers, so this catches those too.
		if SERVER then
			wep:SetNextPrimaryFire(CurTime() + 0.5)
			wep:SetNextSecondaryFire(CurTime() + 0.5)
		end
	end

end)
