--[[---------------------------------------------------------
	Department (job category) whitelist/blacklist - shared constants,
	plus the client-side cache of the LOCAL player's own status. Actual
	storage/enforcement lives in core/sv_whitelist.lua (server); the
	management panel is cl_whitelist_menu.lua.

	A "department" here is a job Section name (core/sh_jobs.lua's
	PDCity.SECTIONS) that's been marked whitelist-only (PDCity_
	IsSectionWhitelistOnly) via the F4 admin editor's Job Categories tab.
	Every job in a whitelist-only category needs a matching whitelist
	LEVEL (job.RequiredWhitelistLevel, default 1) instead of the usual
	XP-based RequiredLevel - see core/sv_jobs.lua's PDCity.ApplyJob.
-----------------------------------------------------------]]

-- A player needs this level (or PDCity.IsSuperAdminPlus) in a department
-- to manage that department's whitelist/blacklist themselves - can
-- promote/demote/blacklist anyone with a LOWER level than their own,
-- never anyone at or above it.
PDCity.WHITELIST_MANAGE_LEVEL = 6

if CLIENT then

	-- Synced down for the LOCAL player only (core/sv_whitelist.lua's
	-- "pdcity_whitelist_sync") - enough to gate F4 job cards and the
	-- whitelist panel's own department list without a round trip per
	-- check. Never trust this for anything security-relevant beyond UI -
	-- every actual grant/promotion/blacklist is re-validated server-side.
	PDCity.MY_WHITELIST_LEVELS = PDCity.MY_WHITELIST_LEVELS or {}     -- [department] = level
	PDCity.MY_WHITELIST_PROMOTED = PDCity.MY_WHITELIST_PROMOTED or {} -- [department] = os.time()
	PDCity.MY_DEPARTMENT_BANS = PDCity.MY_DEPARTMENT_BANS or {}       -- [department] = { Until = os.time()+N or -1, Reason = "..." }

	function PDCity.MyWhitelistLevel(department)
		return PDCity.MY_WHITELIST_LEVELS[department] or 0
	end

	function PDCity.AmIDepartmentBanned(department)
		local ban = PDCity.MY_DEPARTMENT_BANS[department]
		if not ban then return false end
		if ban.Until == -1 then return true end
		return ban.Until > os.time()
	end

	-- Whether the LOCAL client can manage this specific department -
	-- level >= PDCity.WHITELIST_MANAGE_LEVEL there, or superadmin/owner
	-- (who can manage every department regardless of their own level).
	function PDCity.CanIManageDepartment(department)
		return PDCity.IsSuperAdminPlus(LocalPlayer()) or PDCity.MyWhitelistLevel(department) >= PDCity.WHITELIST_MANAGE_LEVEL
	end

	-- Whether I can manage AT LEAST ONE department right now - gates
	-- whether !whitelist/the F4 "Manage Whitelist" button do anything.
	function PDCity.HaveAnyWhitelistAccess()
		if PDCity.IsSuperAdminPlus(LocalPlayer()) then return true end
		for _, level in pairs(PDCity.MY_WHITELIST_LEVELS) do
			if level >= PDCity.WHITELIST_MANAGE_LEVEL then return true end
		end
		return false
	end

	-- core/sv_whitelist.lua sends this down on join and after every level/ban
	-- change that affects us - without this the three caches above never get
	-- filled in, so every whitelist-only job permanently reads as level 0.
	net.Receive("pdcity_whitelist_sync", function()
		local data = util.JSONToTable(net.ReadString() or "")
		if not istable(data) then return end

		PDCity.MY_WHITELIST_LEVELS = data.Levels or {}
		PDCity.MY_WHITELIST_PROMOTED = data.PromotedAt or {}
		PDCity.MY_DEPARTMENT_BANS = data.Bans or {}
	end)

end
