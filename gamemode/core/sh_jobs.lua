--[[---------------------------------------------------------
	Job/team definitions for PD City. Shared so the client can list
	jobs on the F4 menu and the server can validate/apply them.

	Appearance fields (all optional):
	  Models      pool of model paths, one picked at random
	  Skins       pool of skin indices, one picked at random (default 0)
	  Bodygroups  { [bodygroup name] = value } applied after the model,
	              e.g. { Uppr = 2, Hat = 0 } - names come from the model
	              itself (the LVMPD models use "Uppr", "Lowr", "Hat")
-----------------------------------------------------------]]

local CITIZEN_MODELS = {
	"models/player/Group02/male_02.mdl", -- refugee01
	"models/player/Group02/male_04.mdl", -- refugee02
	"models/player/Group01/female_05.mdl", -- female05
	"models/player/Group01/female_06.mdl", -- female06
}

-- Display order for the F4 menu's section headers. Jobs are grouped by
-- their Section field below and rendered in this order; within a section
-- they're rendered in ascending job ID order.
--
-- Replaceable wholesale by disk load (server) / network sync (client) -
-- see core/sh_job_catalogue.lua and core/sv_job_catalogue.lua. The value
-- here is just the starting default before any custom categories exist -
-- only "Citizens" and "Staff" ship by default (what the two hardcoded
-- jobs below need), add your own via the F4 admin editor's Job
-- Categories tab for anything else (Police, EMS, whatever your server
-- wants).
PDCity.SECTIONS = PDCity.SECTIONS or { "Citizens" }

-- Whitelist-only categories (core/sv_whitelist.lua) - [sectionName] = true.
-- Every job in a whitelisted category ignores RequiredLevel entirely and
-- instead needs a matching department access level (job.RequiredWhitelistLevel,
-- default 1) - see core/sv_jobs.lua's PDCity.ApplyJob. Toggled from the F4
-- admin editor's Job Categories tab, persisted/synced alongside
-- PDCity.SECTIONS itself (core/sv_job_catalogue.lua).
PDCity.SECTION_WHITELIST_ONLY = PDCity.SECTION_WHITELIST_ONLY or {}

function PDCity.IsSectionWhitelistOnly(section)
	return PDCity.SECTION_WHITELIST_ONLY[section] == true
end

PDCity.JOBS = {
	[1] = {
		Name = "Citizen",
		Salary = 0,
		Section = "Citizens",
		Color = Color(90, 150, 90),
		Models = CITIZEN_MODELS,
		Weapons = {},
		Description = "An ordinary resident of the city. No special equipment.",
		Default = true,
	},
	-- Only Citizen ships hardcoded now - every other job (Police ranks,
	-- Farmer, etc.) is added from scratch via the F4 admin editor's Jobs
	-- tab, nothing to delete first.
	--
	-- "Staff on Duty" used to be a hardcoded JOB here (ID 8) that granted
	-- noclip/staff-tool access/damage immunity to whoever selected it.
	-- That's gone - those perks are inherent to staff rank itself
	-- (PDCity.IsStaff, core/sh_permissions.lua) rather than tied to a job
	-- selection. See shared.lua's GM:PlayerNoClip/GM:PhysgunPickup and
	-- core/sv_staff_commands.lua for what that grants now.
	--
	-- "Staff on Duty" as a CHARACTER (not a job) still exists though - a
	-- dedicated, forced-name/forced-model slot on the F1 Character
	-- Selection screen, offered only to staff-ranked players. See
	-- core/sh_rpname.lua's PDCity.STAFF_SLOT and core/sv_accounts.lua's
	-- PDCity.GetCharacterSlots.
}

PDCity.DEFAULT_JOB = 1

-- Owner edits to a BUILT-IN job (F4 admin editor's Jobs tab, same edit
-- flow as a custom job - core/sv_job_catalogue.lua's edit_builtin_job)
-- layered on top of the hardcoded table above. Needed because, unlike
-- PDCity.CUSTOM_JOBS, the jobs in PDCity.JOBS itself reload fresh from
-- this file every restart and have nowhere else to remember an edit -
-- persisted/synced alongside PDCity.CUSTOM_JOBS regardless.
-- Only ever holds whichever of Name/Models/Salary/RequiredLevel/Section/
-- Description/Icon/Weapons/CanRaid/CanMug/CanKidnap/DarkWeb/DoorFactions the owner actually
-- changed - Color/Default/StaffOnly always come from the hardcoded job
-- untouched.
PDCity.JOB_OVERRIDES = PDCity.JOB_OVERRIDES or {}

-- Keyed by job ID, invalidated (see PDCity.InvalidateJobCache) whenever
-- PDCity.JOB_OVERRIDES[id] is reassigned to a NEW table - edit code must
-- always assign a fresh table rather than mutate one in place, or this
-- cache won't notice the change.
local mergedJobCache = {}

function PDCity.InvalidateJobCache(id)
	mergedJobCache[id] = nil
end

-- Shallow merge - Models/Weapons/Color etc. that AREN'T overridden stay
-- shared references from the base job, only fields actually present in
-- the override replace them. Cached by the override table's IDENTITY
-- (see PDCity.InvalidateJobCache above), not its contents.
local function MergeJobOverride(id, base, override)
	if not override then return base end

	local cached = mergedJobCache[id]
	if cached and cached.pdcity_OverrideRef == override then return cached end

	local merged = {}
	for k, v in pairs(base) do merged[k] = v end
	for k, v in pairs(override) do merged[k] = v end
	merged.pdcity_OverrideRef = override

	mergedJobCache[id] = merged
	return merged
end

-- Checks the hardcoded jobs above first (merged with any owner override),
-- then whatever's been added through the F4 admin editor's Jobs tab
-- (core/sh_job_catalogue.lua, PDCity.CUSTOM_JOBS - defined there, but
-- this file loads first, so it's read lazily here rather than at load
-- time).
--
-- A built-in job the owner has removed (override.Removed - F4 admin
-- editor's Jobs tab, core/sv_job_catalogue.lua's remove_builtin_job)
-- returns nil here, same as if the ID never existed at all - every
-- existing caller (job selection, F4 menu listings, XP lookups) already
-- treats "no job" as "can't use/see it", so this one flag is all that's
-- needed to pull a removed job out of the whole game with no other
-- changes. PDCity.GetRemovedBuiltinJobs below is the one deliberate
-- exception, for the admin editor's own restore list.
function PDCity.GetJob(id)
	local base = PDCity.JOBS[id]
	if not base then
		return PDCity.CUSTOM_JOBS and PDCity.CUSTOM_JOBS[id]
	end

	local merged = MergeJobOverride(id, base, PDCity.JOB_OVERRIDES[id])
	if merged.Removed then return nil end
	return merged
end

-- Bypasses the Removed filter above - only for the admin editor's own
-- "removed built-in jobs" restore list (mirrors
-- core/sh_f4_entities.lua's PDCity.GetRemovedBuiltinF4Entities).
function PDCity.GetRemovedBuiltinJobs()
	local out = {}
	for id, base in pairs(PDCity.JOBS) do
		local override = PDCity.JOB_OVERRIDES[id]
		if override and override.Removed then
			table.insert(out, { ID = id, Name = base.Name })
		end
	end
	table.sort(out, function(a, b) return a.ID < b.ID end)
	return out
end

-- Sorted list of job IDs (hardcoded + custom), so menus don't need a
-- hardcoded range that has to be kept in sync whenever jobs are added or
-- removed.
function PDCity.GetSortedJobIDs()
	local ids = {}
	for id in pairs(PDCity.JOBS) do
		table.insert(ids, id)
	end
	if PDCity.CUSTOM_JOBS then
		for id in pairs(PDCity.CUSTOM_JOBS) do
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Job IDs belonging to a single section (e.g. "Police"), in ascending ID
-- order. Used by the F4 menu to render one grid per section.
function PDCity.GetJobIDsInSection(sectionName)
	local ids = {}
	for _, id in ipairs(PDCity.GetSortedJobIDs()) do
		local job = PDCity.GetJob(id)
		if job and job.Section == sectionName then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Applies a job's skin and bodygroups. Must be called AFTER SetModel -
-- a model change resets bodygroups, and skin indices are per-model.
-- Always sets the skin so one job's random skin never carries over to a
-- job that doesn't define any.
function PDCity.ApplyJobAppearance(ply, job)
	local skin = 0
	if job.Skins and #job.Skins > 0 then
		skin = job.Skins[math.random(#job.Skins)]
	end
	ply:SetSkin(skin)

	if job.Bodygroups then
		for name, value in pairs(job.Bodygroups) do
			local index = ply:FindBodygroupByName(name)
			if index >= 0 then
				ply:SetBodygroup(index, value)
			end
		end
	end
end

for id, job in pairs(PDCity.JOBS) do
	team.SetUp(id, job.Name, job.Color)
end
