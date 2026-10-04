--[[---------------------------------------------------------
	Handles applying a job to a player: team, model, and weapons.
	Used both for an immediate F4 job change and for normal spawning.
-----------------------------------------------------------]]

local function CountPlayersInJob(jobID)
	local count = 0
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Team() == jobID then
			count = count + 1
		end
	end
	return count
end

-- Gives the base sandbox tools plus whatever weapons the job specifies.
-- Shared by both the instant F4 job-change path and normal PlayerLoadout.
-- Every weapon given here is tagged pdcity_NoDrop so /drop (core/sv_drop.lua)
-- refuses to drop it - nobody should be able to drop their spawn
-- loadout (physgun, gravity gun, toolgun, keys, or a job's own weapons
-- like cuffs), only things acquired some other way (e.g. bought from
-- the F4 shop).
function PDCity.GiveJobWeapons(ply)
	local job = PDCity.GetJob(ply:Team())

	local function GiveLoadout(class)
		ply:Give(class)
		local wep = ply:GetWeapon(class)
		if IsValid(wep) then wep.pdcity_NoDrop = true end
	end

	GiveLoadout("weapon_physgun")
	GiveLoadout("weapon_physcannon") -- gravity gun, every job gets one
	GiveLoadout("gmod_tool")
	GiveLoadout("weapon_keys") -- every job gets keys, not just certain ones

	if job then
		for _, wep in ipairs(job.Weapons) do
			-- {Class, Nickname} (core/sv_job_catalogue.lua) or a plain
			-- class string from before that field existed - either way.
			GiveLoadout(istable(wep) and wep.Class or wep)
		end
	end

	ply:SelectWeapon("weapon_physgun")
end

-- Changes a player's job and forces a full respawn: new spawn point,
-- fresh health, and the new job's model/appearance/loadout all follow
-- automatically from Player:Spawn() (player_class/player_sandbox.lua's
-- PLAYER:SetModel already picks a job's model off whatever team
-- they're now on, and GM:PlayerLoadout already calls
-- PDCity.GiveJobWeapons - both run as part of the normal spawn
-- sequence, so this doesn't need to duplicate either).
function PDCity.ApplyJob(ply, jobID)
	if not ply:Alive() then
		return false, "You can't change jobs while dead - wait to respawn first."
	end

	local job = PDCity.GetJob(jobID)
	if not job then return false, "That job doesn't exist." end

	if job.StaffOnly and not PDCity.IsStaff(ply) then
		return false, "That job is for server staff only."
	end

	-- Whitelist-only category (core/sh_jobs.lua's PDCity.IsSectionWhitelistOnly,
	-- toggled per-category from the F4 admin editor) - completely replaces
	-- the XP-based RequiredLevel check below with a department whitelist
	-- level instead (core/sv_whitelist.lua), and a blacklist check that
	-- blocks every job in the department outright, not just this one.
	if PDCity.IsSectionWhitelistOnly(job.Section) then
		if PDCity.IsDepartmentBanned(ply, job.Section) then
			return false, "You're blacklisted from " .. job.Section .. "."
		end

		local required = math.max(1, job.RequiredWhitelistLevel or 1)
		local myLevel = PDCity.GetWhitelistLevel(ply, job.Section)

		if myLevel < required then
			return false, job.Section .. " is whitelist-only - you need whitelist level " .. required .. " for this job (you're level " .. myLevel .. ")."
		end

	-- Ranks unlocked by class level (core/sh_xp.lua) - e.g. Police
	-- Sergeant needs Police level 4. Keyed off the job's own Section,
	-- not hardcoded to "Police", so RequiredLevel works the same way
	-- for any other job class later. Skipped entirely for a whitelist-only
	-- category, per the branch above - "will not require levels to get
	-- these jobs" was the whole point of the whitelist replacing it.
	-- Also skipped outright while the XP system itself is turned off
	-- (core/sh_xp_settings.lua) - nothing should stay locked behind a
	-- system nobody can currently earn progress in.
	elseif job.RequiredLevel and PDCity.XP_ENABLED then
		local level = PDCity.LevelForXP(PDCity.GetJobClassXP(ply, job.Section))

		if level < job.RequiredLevel then
			return false, "You need to be " .. job.Section .. " level " .. job.RequiredLevel .. " to take this job (you're level " .. level .. ")."
		end
	end

	if job.MaxSlots and ply:Team() ~= jobID and CountPlayersInJob(jobID) >= job.MaxSlots then
		return false, "That job is full."
	end

	ply:SetTeam(jobID)

	-- Clean slate before the respawn below regives the new job's
	-- loadout - unlike a real death, an alive player forced through
	-- Spawn() here still has their old weapons, so without this
	-- they'd end up holding both the old and new job's gear at once.
	ply:StripWeapons()
	ply:Spawn()

	return true
end

concommand.Add("pdcity_selectjob", function(ply, cmd, args)
	if not IsValid(ply) then return end

	local jobID = tonumber(args[1])
	if not jobID then return end

	local ok, err = PDCity.ApplyJob(ply, jobID)
	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. err)
	end
end)
