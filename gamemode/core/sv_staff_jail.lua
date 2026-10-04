--[[---------------------------------------------------------
	Staff Menu jail (cl_staff_menu.lua, core/sv_staff_menu.lua) - a
	punishment, not part of the arrest RP loop. Teleports to the Staff
	Jail Spot (core/sv_staff_jail_spot.lua, set with the owner-only
	pdcity_staffjailspot tool), not the RP jail spawns the arrest system
	uses (core/sv_jail_spawns.lua). Deliberately separate: this needs no
	`law` or arresting officer, and - critically - core/sv_arrests.lua's
	own GetJailedPlayers skips anyone jailed this way, so bail can't buy
	someone out of a staff punishment.

	Reuses the same PDCity_IsJailed/PDCity_JailEndTime NWVars the RP jail
	system sets, so cl_jail_hud.lua's countdown renders for a staff jail
	too, for free - `pdcity_StaffJailed` is the extra marker that tells
	the two systems apart server-side.

	minutes == 0 means indefinite: no release timer is created, and the
	player stays jailed until a superadmin+ explicitly unjails them from
	the Staff Menu.
-----------------------------------------------------------]]

local function ReleaseTimerName(target)
	return "pdcity_StaffJailRelease_" .. target:SteamID64()
end

function PDCity.StaffJailPlayer(target, minutes)
	if not IsValid(target) then return false, "Invalid target." end

	local spot = PDCity.GetStaffJailSpot()
	if not spot then
		return false, "No staff jail spot set on this map - use the Staff Jail Spot tool first."
	end

	-- Already RP-jailed (or already staff-jailed) - clear whichever
	-- release timer was running before overwriting their jail state, so
	-- an old one can't fire later and release them early/wrongly.
	timer.Remove("pdcity_JailRelease_" .. target:SteamID64())
	timer.Remove(ReleaseTimerName(target))

	target.pdcity_IsCuffed = nil
	target.pdcity_ArrestingOfficer = nil
	target:StripWeapons()
	PDCity.SetPlayerFrozen(target, false)
	target:SetPos(spot.pos)
	target:SetEyeAngles(spot.ang)

	target.pdcity_IsJailed = true
	target.pdcity_StaffJailed = true
	target.pdcity_JailEndTime = (minutes > 0) and (CurTime() + minutes * 60) or nil

	target:SetNWBool("PDCity_IsJailed", true)
	target:SetNWFloat("PDCity_JailEndTime", target.pdcity_JailEndTime or 0)

	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You have been jailed by staff"
		.. (minutes > 0 and (" for " .. minutes .. " minute(s).") or " indefinitely."))

	if minutes > 0 then
		timer.Create(ReleaseTimerName(target), minutes * 60, 1, function()
			if IsValid(target) then PDCity.StaffUnjailPlayer(target) end
		end)
	end

	return true
end

function PDCity.StaffUnjailPlayer(target)
	if not IsValid(target) then return end
	if not target.pdcity_IsJailed then return end

	timer.Remove(ReleaseTimerName(target))

	target.pdcity_IsJailed = nil
	target.pdcity_StaffJailed = nil
	target.pdcity_JailEndTime = nil
	target:SetNWBool("PDCity_IsJailed", false)

	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You have been released from staff jail.")
	target:Spawn() -- normal spawn chain: job model/appearance/loadout, same as any respawn
end
