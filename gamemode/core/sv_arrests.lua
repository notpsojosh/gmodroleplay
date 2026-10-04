--[[---------------------------------------------------------
	The arrest cycle: cuff -> officer picks a law + duration -> jail
	countdown -> forced respawn. Cuffing itself happens in
	weapon_pdcity_cuffs.lua (PrimaryAttack), which calls PDCity.CuffPlayer
	below once the target holds still for a second.

	Player-local state (not persisted - it only matters while the
	player's current entity exists):
	  ply.pdcity_IsCuffed          - frozen, holding weapon_pdcity_cuffed,
	                                 waiting on the officer's menu
	  ply.pdcity_BeingCuffed        - mid 1-second cuff attempt
	  ply.pdcity_ArrestingOfficer   - officer who cuffed them (for cleanup)
	  ply.pdcity_ArrestTarget       - (on the OFFICER) who their open
	                                 arrest menu refers to
	  ply.pdcity_IsJailed           - serving a sentence
	  ply.pdcity_JailEndTime        - CurTime() the sentence ends
	  ply.pdcity_PreJailRunSpeed    - RunSpeed to restore on release
-----------------------------------------------------------]]

util.AddNetworkString("PDCity_OpenArrestMenu")
util.AddNetworkString("PDCity_SubmitArrest")
util.AddNetworkString("PDCity_CancelArrest")
util.AddNetworkString("PDCity_OpenBailMenu")
util.AddNetworkString("PDCity_PayBail")

-- Owner-editable (F1 Site Admin's "Laws & Rewards" tab, core/sv_law_settings.lua)
-- via PDCity.LAW_REWARDS (core/sh_laws.lua) - PayPerMinute, BailPerMinute,
-- DisconnectPenaltyPerMinute. Read live at each point of use below rather
-- than cached into locals, so a change from the admin panel takes effect
-- on the very next arrest/bail/disconnect without needing a restart.

--[[---------------------------------------------------------
	Cuffing / uncuffing
-----------------------------------------------------------]]

-- Called by weapon_pdcity_cuffs.lua once a target has held still long enough.
function PDCity.CuffPlayer(target, officer)
	if not IsValid(target) or not IsValid(officer) then return end

	target.pdcity_IsCuffed = true
	target.pdcity_ArrestingOfficer = officer

	target:StripWeapons()
	target:Give("weapon_pdcity_cuffed")
	target:SelectWeapon("weapon_pdcity_cuffed")
	PDCity.SetPlayerFrozen(target, true)

	officer.pdcity_ArrestTarget = target

	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You have been cuffed by " .. PDCity.GetDisplayName(officer) .. ".")

	net.Start("PDCity_OpenArrestMenu")
	net.WriteEntity(target)
	net.Send(officer)
end

-- Releases a cuffed (not yet jailed) player back to normal: unfreezes
-- them and restores their job's weapons, since cuffing already stripped
-- everything they had. Global (not local) since core/sv_staff_commands.lua's
-- "!respawn" reuses it too, rather than duplicating this cleanup.
function PDCity.UncuffPlayer(target)
	if not IsValid(target) then return end

	target.pdcity_IsCuffed = nil
	target.pdcity_BeingCuffed = nil

	local officer = target.pdcity_ArrestingOfficer
	target.pdcity_ArrestingOfficer = nil
	if IsValid(officer) and officer.pdcity_ArrestTarget == target then
		officer.pdcity_ArrestTarget = nil
	end

	PDCity.SetPlayerFrozen(target, false)
	target:StripWeapons()
	PDCity.GiveJobWeapons(target)
	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You have been uncuffed.")
end

--[[---------------------------------------------------------
	Jailing / release
-----------------------------------------------------------]]

function PDCity.JailPlayer(target, minutes, law, officer)
	if not IsValid(target) then return end

	local spawnPoint = PDCity.GetRandomJailSpawn()
	if not spawnPoint then
		if IsValid(officer) then
			officer:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No jail spawns set - use the Jail Spawn tool first. Releasing the prisoner instead.")
		end
		PDCity.UncuffPlayer(target)
		return
	end

	target.pdcity_IsCuffed = nil
	target.pdcity_ArrestingOfficer = nil

	target:StripWeapons()
	PDCity.SetPlayerFrozen(target, false)
	target:SetPos(spawnPoint.pos)
	target:SetEyeAngles(spawnPoint.ang)

	target.pdcity_IsJailed = true
	target.pdcity_JailEndTime = CurTime() + minutes * 60
	target.pdcity_PreJailRunSpeed = target:GetRunSpeed()
	target:SetRunSpeed(target:GetWalkSpeed()) -- no sprinting while jailed

	target:SetNWBool("PDCity_IsJailed", true)
	target:SetNWFloat("PDCity_JailEndTime", target.pdcity_JailEndTime)

	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You've been jailed for " .. minutes .. " year(s) - " .. (law and law.Name or "unknown charge") .. ".")

	timer.Create("pdcity_JailRelease_" .. target:SteamID64(), minutes * 60, 1, function()
		if IsValid(target) then PDCity.ReleaseFromJail(target) end
	end)
end

function PDCity.ReleaseFromJail(ply)
	if not IsValid(ply) then return end

	timer.Remove("pdcity_JailRelease_" .. ply:SteamID64())

	ply.pdcity_IsJailed = nil
	ply.pdcity_JailEndTime = nil
	ply:SetNWBool("PDCity_IsJailed", false)

	if ply.pdcity_PreJailRunSpeed then
		ply:SetRunSpeed(ply.pdcity_PreJailRunSpeed)
		ply.pdcity_PreJailRunSpeed = nil
	end

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your sentence is complete.")
	ply:Spawn() -- runs the normal spawn chain: job model/appearance/loadout, same as any respawn
end

--[[---------------------------------------------------------
	Bail (ent_pdcity_bail.lua). Anyone can pay anyone's bail, not just a
	prisoner bailing themselves - the entity just calls
	PDCity.OpenBailMenuFor(activator) on use; this builds and sends the
	current jailed-players list, and the client (cl_bail_menu.lua) sends
	back which one to pay for. Everything is re-validated here at
	payment time (still jailed, cost recalculated fresh, payer can still
	afford it) rather than trusted from what the menu showed, since jail
	time keeps ticking down and someone else may have already paid.
-----------------------------------------------------------]]

local function GetJailedPlayers()
	local jailed = {}
	for _, ply in ipairs(player.GetAll()) do
		-- Staff Menu jail (core/sv_staff_jail.lua) is a punishment, not
		-- part of the arrest RP loop - deliberately excluded here so
		-- money can't buy someone out of it the way bail buys out of an
		-- officer's arrest.
		if IsValid(ply) and ply.pdcity_IsJailed and not ply.pdcity_StaffJailed then
			table.insert(jailed, ply)
		end
	end
	return jailed
end

local function MinutesLeft(ply)
	return math.max(1, math.ceil((ply.pdcity_JailEndTime - CurTime()) / 60))
end

function PDCity.OpenBailMenuFor(activator)
	local jailed = GetJailedPlayers()

	if #jailed == 0 then
		activator:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Nobody is currently under arrest.")
		return
	end

	net.Start("PDCity_OpenBailMenu")
	net.WriteUInt(#jailed, 8)
	for _, ply in ipairs(jailed) do
		local minutes = MinutesLeft(ply)
		net.WriteEntity(ply)
		net.WriteUInt(minutes, 16)
		net.WriteUInt(minutes * PDCity.LAW_REWARDS.BailPerMinute, 32)
	end
	net.Send(activator)
end

net.Receive("PDCity_PayBail", function(len, payer)
	if not IsValid(payer) then return end

	local target = net.ReadEntity()
	if not IsValid(target) or not target.pdcity_IsJailed then
		payer:ChatPrint("[" .. PDCity.BRAND_TAG .. "] They're no longer under arrest.")
		return
	end

	local cost = MinutesLeft(target) * PDCity.LAW_REWARDS.BailPerMinute

	if PDCity.GetMoney(payer) < cost then
		payer:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Bail is $" .. cost .. " - you don't have enough.")
		return
	end

	PDCity.AddMoney(payer, -cost)

	PDCity.GameLog("arrests", payer:Nick() .. " (" .. payer:SteamID() .. ") paid $" .. cost .. " bail for "
		.. target:Nick() .. " (" .. target:SteamID() .. ")" .. (payer == target and " (self)" or ""))

	if payer == target then
		payer:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You posted your own bail for $" .. cost .. ".")
	else
		payer:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You posted bail for " .. PDCity.GetDisplayName(target) .. " ($" .. cost .. ").")
		target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(payer) .. " posted your bail for $" .. cost .. ".")
	end

	PDCity.ReleaseFromJail(target)
end)

--[[---------------------------------------------------------
	Arrest menu (officer-side UI, see cl_arrest_menu.lua)
-----------------------------------------------------------]]

net.Receive("PDCity_SubmitArrest", function(len, officer)
	if not IsValid(officer) then return end

	local target = net.ReadEntity()
	local lawIndex = net.ReadUInt(8)
	local duration = net.ReadUInt(8)

	if not IsValid(officer.pdcity_ArrestTarget) or officer.pdcity_ArrestTarget ~= target then return end
	if not IsValid(target) or not target.pdcity_IsCuffed then
		officer.pdcity_ArrestTarget = nil
		return
	end

	local law = PDCity.LAWS[lawIndex]
	if not law or duration < law.MinMinutes or duration > law.MaxMinutes then return end

	officer.pdcity_ArrestTarget = nil

	local pay = duration * PDCity.LAW_REWARDS.PayPerMinute
	PDCity.AddMoney(officer, pay)
	officer:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Arrest processed: " .. law.Name .. " (" .. duration .. " year(s)). You earned $" .. pay .. ".")

	PDCity.JailPlayer(target, duration, law, officer)
end)

net.Receive("PDCity_CancelArrest", function(len, officer)
	if not IsValid(officer) then return end

	local target = officer.pdcity_ArrestTarget
	officer.pdcity_ArrestTarget = nil

	if IsValid(target) and target.pdcity_IsCuffed then
		PDCity.UncuffPlayer(target)
	end
end)

--[[---------------------------------------------------------
	Staff release: "!unarrest <name or steamid>". Requires staff rank
	(PDCity.IsStaff, core/sh_permissions.lua) - same rule noclip uses
	(see GM:PlayerNoClip in shared.lua).
-----------------------------------------------------------]]

hook.Add("PlayerSay", "pdcity_UnarrestChatCommand", function(ply, text)

	local args = string.Explode(" ", string.Trim(text))
	if string.lower(args[1] or "") ~= "!unarrest" then return end
	table.remove(args, 1)

	if not PDCity.IsStaff(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You must be staff to use this.")
		return ""
	end

	local identifier = args[1]
	if not identifier then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Usage: !unarrest <name or steamid>")
		return ""
	end

	local target = PDCity.FindPlayerByIdentifier(identifier)
	if not IsValid(target) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No matching player found.")
		return ""
	end

	if not target.pdcity_IsJailed then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(target) .. " isn't currently jailed.")
		return ""
	end

	PDCity.ReleaseFromJail(target)

	-- The generic PDCity.ReleaseFromJail wrap (core/sv_gamelog.lua) only
	-- captures the target, not who did it - !unarrest specifically is
	-- exactly the kind of staff action that needs the "who" on record.
	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") released "
		.. target:Nick() .. " (" .. target:SteamID() .. ") from jail early (!unarrest)")

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Released " .. PDCity.GetDisplayName(target) .. " from jail.")
	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(ply) .. " (staff) released you early.")

	return ""

end)

--[[---------------------------------------------------------
	Disconnect handling: financial penalty for leaving jail early, and
	cleanup so nobody else is left dangling (a cuffed target whose
	officer vanished mid-menu, or an officer's open menu reference to a
	target who vanished).
-----------------------------------------------------------]]

hook.Add("PlayerDisconnected", "pdcity_ArrestDisconnectCleanup", function(ply)

	if ply.pdcity_JailEndTime and ply.pdcity_JailEndTime > CurTime() then
		local minutesLeft = math.ceil((ply.pdcity_JailEndTime - CurTime()) / 60)
		PDCity.AddMoney(ply, -(minutesLeft * PDCity.LAW_REWARDS.DisconnectPenaltyPerMinute))
		-- Force an immediate write rather than relying on the debounced
		-- save (core/sv_profiles.lua) - by the time that timer would
		-- fire, this player's profile cache may already be gone.
		PDCity.SaveProfile(ply:SteamID64())
		timer.Remove("pdcity_JailRelease_" .. ply:SteamID64())
	end

	if IsValid(ply.pdcity_ArrestTarget) and ply.pdcity_ArrestTarget.pdcity_IsCuffed then
		PDCity.UncuffPlayer(ply.pdcity_ArrestTarget)
	end

end)
