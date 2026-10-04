--[[---------------------------------------------------------
	Server side of the F4 admin editor's Jobs/Categories tabs: persists
	the owner-editable custom jobs and job categories
	(core/sh_job_catalogue.lua, PDCity.SECTIONS in core/sh_jobs.lua) to
	data/pdcity/job_catalogue.json, validates every change, and
	broadcasts the result to all clients so job selection and the F4
	menu update live.

	Every action re-checks PDCity.IsOwner(ply) here - the admin editor
	only shows for the owner client-side, but that's just UI; this is
	the actual enforcement.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_job_sync")
util.AddNetworkString("pdcity_job_admin")

local CATALOGUE_PATH = "pdcity/job_catalogue.json"

-- Next ID handed out for a new custom job. Never reused, even after a
-- job is removed, so a stale client reference can never collide with a
-- different job than the one it originally pointed to.
local nextJobID = PDCity.CUSTOM_JOB_ID_BASE

local function SaveCatalogue()
	file.CreateDir("pdcity")
	file.Write(CATALOGUE_PATH, util.TableToJSON({
		Sections = PDCity.SECTIONS,
		Jobs = PDCity.CUSTOM_JOBS,
		Overrides = PDCity.JOB_OVERRIDES,
		NextID = nextJobID,
		WhitelistOnlySections = PDCity.SECTION_WHITELIST_ONLY,
	}, true))
end

local function LoadCatalogue()
	local raw = file.Read(CATALOGUE_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. CATALOGUE_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if istable(data.Sections) and #data.Sections > 0 then
		PDCity.SECTIONS = data.Sections
	end

	if istable(data.Jobs) then
		-- JSON object keys are always strings; job IDs need to be
		-- numbers again to match team IDs / Player:Team().
		local jobs = {}
		for idStr, job in pairs(data.Jobs) do
			jobs[tonumber(idStr)] = job
		end
		PDCity.CUSTOM_JOBS = jobs
	end

	if istable(data.Overrides) then
		local overrides = {}
		for idStr, override in pairs(data.Overrides) do
			overrides[tonumber(idStr)] = override
		end
		PDCity.JOB_OVERRIDES = overrides
	end

	if isnumber(data.NextID) then
		nextJobID = math.max(nextJobID, data.NextID)
	end

	if istable(data.WhitelistOnlySections) then
		PDCity.SECTION_WHITELIST_ONLY = data.WhitelistOnlySections
	end

	PDCity.RegisterCustomJobTeams()

	-- Built-in jobs' teams need re-registering too if any have an
	-- overridden Name/Color - team.SetUp for them normally only runs
	-- once, at sh_jobs.lua's own load time, before any override from
	-- disk has been read.
	for id in pairs(PDCity.JOB_OVERRIDES) do
		local job = PDCity.GetJob(id)
		if job then team.SetUp(id, job.Name, job.Color) end
	end
end

LoadCatalogue()

local function BroadcastCatalogue(ply)
	net.Start("pdcity_job_sync")
		net.WriteString(util.TableToJSON({
			Sections = PDCity.SECTIONS,
			Jobs = PDCity.CUSTOM_JOBS,
			Overrides = PDCity.JOB_OVERRIDES,
			WhitelistOnlySections = PDCity.SECTION_WHITELIST_ONLY,
		}))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncJobCatalogue", function(ply)
	BroadcastCatalogue(ply)
end)

--[[---------------------------------------------------------
	Validation helpers
-----------------------------------------------------------]]

-- Optional - a job with no models (nil/empty) falls back to each
-- character's own chosen player model at spawn time (see
-- player_class/player_sandbox.lua's PLAYER:SetModel and
-- core/sv_accounts.lua's PDCity.GetCharacterModel), same nil-is-fine
-- convention as IsValidWeaponList above.
local function IsValidModelList(models)
	if models == nil then return true end
	if not istable(models) then return false end
	for _, m in ipairs(models) do
		if not isstring(m) or m == "" then return false end
	end
	return true
end

local function NormalizeModelList(models)
	local out = {}
	if not istable(models) then return out end
	for _, m in ipairs(models) do
		if isstring(m) and m ~= "" then table.insert(out, m) end
	end
	return out
end

local function IsValidWholeNumber(n)
	return isnumber(n) and n >= 0 and n == math.floor(n)
end

-- RequiredLevel (core/sv_jobs.lua's class-level gate) is stored as
-- `false`, not nil, when cleared - NOT just omitted from the job/override
-- table. For a custom job that'd be equivalent either way, but for a
-- built-in job's OVERRIDE (core/sh_jobs.lua's PDCity.GetJob merge, shallow
-- key-by-key) an absent key falls back to the hardcoded job's own
-- RequiredLevel instead of clearing it - `false` is what actually wins
-- the merge and reads as "no requirement" (job.RequiredLevel and ...
-- checks are already false-safe, same as nil).
local function NormalizeRequiredLevel(n)
	if not IsValidWholeNumber(n) then return false, false end
	if n == 0 then return true, false end
	return true, math.floor(n)
end

-- Weapon classes for a new job's loadout (cl_f4_admin.lua's Jobs tab).
-- Weapon-only (not scripted_ents like sh_f4_catalogue.lua's IsValidClass
-- allows for the F4 shop) - a job's Weapons list is given out via
-- Player:Give(), which only makes sense for actual weapons.
--
-- Each entry is { Class = "...", Nickname = "..." } - Nickname is
-- optional, shown instead of the raw class name wherever a job's
-- loadout is displayed, falling back to the class itself when blank.
-- Older saved jobs may still have plain class-string entries from before
-- this field existed - core/sv_jobs.lua's GiveLoadout and every display
-- site read either shape defensively, so nothing needs a one-off
-- migration; a job saved through this form from now on always comes out
-- in the new shape (NormalizeWeaponList below).
-- Returns the offending class as a second value on failure - the owner's
-- OWN weapon picker (cl_f4_admin.lua) lists everything THEIR client has
-- registered (weapons.GetList()), which includes anything they're
-- personally subscribed to on Steam even if it isn't in the server's own
-- host_workshop_collection - that class then genuinely doesn't exist
-- here (weapons.GetStored fails server-side) even though it picked fine
-- client-side. Naming it is the difference between that being solvable
-- in five seconds and a guessing game.
local function IsValidWeaponList(list)
	if list == nil then return true end -- optional - defaults to no weapons
	if not istable(list) then return false end

	for _, entry in ipairs(list) do
		local class = istable(entry) and entry.Class or entry
		if not isstring(class) or class == "" or weapons.GetStored(class) == nil then
			return false, class
		end
	end

	return true
end

local function NormalizeWeaponList(list)
	local out = {}
	if not istable(list) then return out end

	for _, entry in ipairs(list) do
		if istable(entry) then
			local nickname = isstring(entry.Nickname) and entry.Nickname ~= "" and entry.Nickname or nil
			table.insert(out, { Class = entry.Class, Nickname = nickname })
		else
			table.insert(out, { Class = entry })
		end
	end

	return out
end

-- CanRaid/CanMug/CanKidnap - display-only for now (shown on the F4 job
-- card's slide-out, cl_f4_menu.lua) - no gameplay system reads these
-- yet, they exist so the editor and the card already agree on the data
-- once those systems are built. DarkWeb is read by core/sv_chat.lua:
-- jobs with it receive /dwa dark web adverts. Always stored as an explicit boolean
-- (never nil/omitted), same reasoning as RequiredLevel's false-not-
-- omitted convention: a built-in job's override needs a real value to
-- win the merge, not an absent key that falls through to the hardcoded
-- job's own.
local function NormalizeFlag(v)
	return v == true
end

-- Door faction IDs this job belongs to (core/sh_door_factions.lua). Always
-- a list (possibly empty), never nil, so a built-in job's override wins
-- the merge when every faction is unticked. Unknown IDs are dropped.
local function NormalizeDoorFactions(list)
	local out, seen = {}, {}
	if not istable(list) then return out end

	for _, v in ipairs(list) do
		local id = tonumber(v)
		if id and PDCity.DOOR_FACTIONS[id] and not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end

	table.sort(out)
	return out
end

--[[---------------------------------------------------------
	Action handlers. Each takes (ply, payload) where payload is the
	decoded table sent from cl_f4_admin.lua, and returns ok[, error].
-----------------------------------------------------------]]

local Actions = {}

function Actions.add_job(ply, p)
	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not IsValidModelList(p.Models) then return false, "Player models, if set, must all be valid model paths (leave empty to use each character's own chosen model)." end
	if not isstring(p.Section) or not table.HasValue(PDCity.SECTIONS, p.Section) then return false, "Pick a valid category." end
	if not IsValidWholeNumber(p.Salary) then return false, "Salary must be a whole number, 0 or more." end
	do
		local weaponsOK, badWeapon = IsValidWeaponList(p.Weapons)
		if not weaponsOK then
			return false, "\"" .. tostring(badWeapon) .. "\" isn't a recognised weapon class on this server - if you're subscribed to that addon yourself, it may not be in the server's own workshop collection."
		end
	end

	local levelOK, requiredLevel = NormalizeRequiredLevel(p.RequiredLevel)
	if not levelOK then return false, "Required level must be a whole number, 0 or more." end

	-- Same false-not-omitted convention, reused as-is - see
	-- NormalizeRequiredLevel's own comment. 0/blank means "level 1", not
	-- "no requirement" - a whitelist-only job with nothing set still
	-- needs SOME level, floored at 1 in core/sv_jobs.lua.
	local wlLevelOK, requiredWhitelistLevel = NormalizeRequiredLevel(p.RequiredWhitelistLevel)
	if not wlLevelOK then return false, "Required whitelist level must be a whole number, 0 or more." end

	local id = nextJobID
	nextJobID = nextJobID + 1

	local job = {
		Name = p.Name,
		Models = NormalizeModelList(p.Models),
		Salary = math.floor(p.Salary),
		RequiredLevel = requiredLevel,
		RequiredWhitelistLevel = requiredWhitelistLevel,
		Section = p.Section,
		Description = isstring(p.Description) and p.Description or "",
		Icon = isstring(p.Icon) and p.Icon or "", -- a literal character OR a pasted image URL - see cl_f4_menu.lua's BuildCard
		Weapons = NormalizeWeaponList(p.Weapons),
		CanRaid = NormalizeFlag(p.CanRaid),
		CanMug = NormalizeFlag(p.CanMug),
		CanKidnap = NormalizeFlag(p.CanKidnap),
		DarkWeb = NormalizeFlag(p.DarkWeb),
		DoorFactions = NormalizeDoorFactions(p.DoorFactions),
		Color = Color(150, 150, 150), -- not settable from the form; a distinct color can be hand-set afterwards
	}

	PDCity.CUSTOM_JOBS[id] = job
	team.SetUp(id, job.Name, job.Color)

	return true
end

function Actions.edit_job(ply, p)
	local id = tonumber(p.ID)
	local job = id and PDCity.CUSTOM_JOBS[id]
	if not job then return false, "That job no longer exists." end

	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not IsValidModelList(p.Models) then return false, "Player models, if set, must all be valid model paths (leave empty to use each character's own chosen model)." end
	if not isstring(p.Section) or not table.HasValue(PDCity.SECTIONS, p.Section) then return false, "Pick a valid category." end
	if not IsValidWholeNumber(p.Salary) then return false, "Salary must be a whole number, 0 or more." end
	do
		local weaponsOK, badWeapon = IsValidWeaponList(p.Weapons)
		if not weaponsOK then
			return false, "\"" .. tostring(badWeapon) .. "\" isn't a recognised weapon class on this server - if you're subscribed to that addon yourself, it may not be in the server's own workshop collection."
		end
	end

	local levelOK, requiredLevel = NormalizeRequiredLevel(p.RequiredLevel)
	if not levelOK then return false, "Required level must be a whole number, 0 or more." end

	local wlLevelOK, requiredWhitelistLevel = NormalizeRequiredLevel(p.RequiredWhitelistLevel)
	if not wlLevelOK then return false, "Required whitelist level must be a whole number, 0 or more." end

	-- Color deliberately untouched - not settable from the form (see
	-- add_job), so an edit shouldn't reset it back to the default grey
	-- if it's been hand-set since.
	job.Name = p.Name
	job.Models = NormalizeModelList(p.Models)
	job.Salary = math.floor(p.Salary)
	job.RequiredLevel = requiredLevel
	job.RequiredWhitelistLevel = requiredWhitelistLevel
	job.Section = p.Section
	job.Description = isstring(p.Description) and p.Description or ""
	job.Icon = isstring(p.Icon) and p.Icon or ""
	job.Weapons = NormalizeWeaponList(p.Weapons)
	job.CanRaid = NormalizeFlag(p.CanRaid)
	job.CanMug = NormalizeFlag(p.CanMug)
	job.CanKidnap = NormalizeFlag(p.CanKidnap)
	job.DarkWeb = NormalizeFlag(p.DarkWeb)
	job.DoorFactions = NormalizeDoorFactions(p.DoorFactions)

	team.SetUp(id, job.Name, job.Color) -- team name needs refreshing too if it changed

	return true
end

-- Editing a BUILT-IN job (core/sh_jobs.lua's PDCity.JOBS, e.g. Citizen,
-- Police Officer) - same form/fields as edit_job above, but stored as an
-- override layered on top of the hardcoded job (core/sh_jobs.lua's
-- PDCity.JOB_OVERRIDES / PDCity.GetJob) rather than mutating a table
-- that doesn't survive a restart anyway. Removing one entirely (rather
-- than just editing its fields) is remove_builtin_job, below -
-- reversible via restore_builtin_job.
function Actions.edit_builtin_job(ply, p)
	local id = tonumber(p.ID)
	if not id or not PDCity.JOBS[id] then return false, "That job doesn't exist." end

	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not IsValidModelList(p.Models) then return false, "Player models, if set, must all be valid model paths (leave empty to use each character's own chosen model)." end
	if not isstring(p.Section) or not table.HasValue(PDCity.SECTIONS, p.Section) then return false, "Pick a valid category." end
	if not IsValidWholeNumber(p.Salary) then return false, "Salary must be a whole number, 0 or more." end
	do
		local weaponsOK, badWeapon = IsValidWeaponList(p.Weapons)
		if not weaponsOK then
			return false, "\"" .. tostring(badWeapon) .. "\" isn't a recognised weapon class on this server - if you're subscribed to that addon yourself, it may not be in the server's own workshop collection."
		end
	end

	local levelOK, requiredLevel = NormalizeRequiredLevel(p.RequiredLevel)
	if not levelOK then return false, "Required level must be a whole number, 0 or more." end

	local wlLevelOK, requiredWhitelistLevel = NormalizeRequiredLevel(p.RequiredWhitelistLevel)
	if not wlLevelOK then return false, "Required whitelist level must be a whole number, 0 or more." end

	-- A fresh table, not a mutation of any existing override - see
	-- sh_jobs.lua's PDCity.GetJob for why that matters (cache invalidation
	-- keys off the override table's IDENTITY, not its contents).
	PDCity.JOB_OVERRIDES[id] = {
		Name = p.Name,
		Models = NormalizeModelList(p.Models),
		Salary = math.floor(p.Salary),
		RequiredLevel = requiredLevel, -- false, not omitted, when cleared - see NormalizeRequiredLevel
		RequiredWhitelistLevel = requiredWhitelistLevel,
		Section = p.Section,
		Description = isstring(p.Description) and p.Description or "",
		Icon = isstring(p.Icon) and p.Icon or "",
		Weapons = NormalizeWeaponList(p.Weapons),
		CanRaid = NormalizeFlag(p.CanRaid),
		CanMug = NormalizeFlag(p.CanMug),
		CanKidnap = NormalizeFlag(p.CanKidnap),
		DarkWeb = NormalizeFlag(p.DarkWeb),
		DoorFactions = NormalizeDoorFactions(p.DoorFactions),
	}
	PDCity.InvalidateJobCache(id)

	team.SetUp(id, p.Name, PDCity.JOBS[id].Color)

	return true
end

function Actions.reset_builtin_job(ply, p)
	local id = tonumber(p.ID)
	if not id or not PDCity.JOBS[id] then return false, "That job doesn't exist." end
	if not PDCity.JOB_OVERRIDES[id] then return false, "That job hasn't been edited." end

	PDCity.JOB_OVERRIDES[id] = nil
	PDCity.InvalidateJobCache(id)

	team.SetUp(id, PDCity.JOBS[id].Name, PDCity.JOBS[id].Color)

	return true
end

-- Takes a built-in job out of the game entirely (still can't be truly
-- deleted - PDCity.DEFAULT_JOB below needs a real, always-resolvable job
-- at that specific ID - but every OTHER built-in job can be hidden this
-- way, reversible via restore_builtin_job). Same Removed-override-flag
-- technique as core/sv_f4_catalogue.lua's remove_builtin_entity;
-- core/sh_jobs.lua's PDCity.GetJob is what actually enforces it (returns
-- nil for a Removed job, same as if the ID never existed).
function Actions.remove_builtin_job(ply, p)
	local id = tonumber(p.ID)
	if not id or not PDCity.JOBS[id] then return false, "That job doesn't exist." end

	if id == PDCity.DEFAULT_JOB then return false, "The default job can't be removed - everyone falls back to it." end

	-- Same reassignment as remove_job (custom jobs) - the team keeps
	-- existing either way (nothing un-registers a GMod team), but
	-- PDCity.GetJob(id) returns nil for anyone still on it from this
	-- point on.
	for _, other in ipairs(player.GetAll()) do
		if IsValid(other) and other:Team() == id then
			if other:Alive() then
				PDCity.ApplyJob(other, PDCity.DEFAULT_JOB)
			else
				other:SetTeam(PDCity.DEFAULT_JOB)
			end
			other:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your job was removed by an admin - moved to the default job.")
		end
	end

	local fresh = {}
	local old = PDCity.JOB_OVERRIDES[id]
	if old then for k, v in pairs(old) do fresh[k] = v end end
	fresh.Removed = true

	PDCity.JOB_OVERRIDES[id] = fresh
	PDCity.InvalidateJobCache(id)

	return true
end

function Actions.restore_builtin_job(ply, p)
	local id = tonumber(p.ID)
	local old = id and PDCity.JOB_OVERRIDES[id]
	if not old or not old.Removed then return false, "That job isn't removed." end

	local fresh = {}
	for k, v in pairs(old) do fresh[k] = v end
	fresh.Removed = nil

	PDCity.JOB_OVERRIDES[id] = next(fresh) and fresh or nil
	PDCity.InvalidateJobCache(id)

	team.SetUp(id, PDCity.JOBS[id].Name, PDCity.JOBS[id].Color)

	return true
end

function Actions.remove_job(ply, p)
	local id = tonumber(p.ID)
	if not id or not PDCity.CUSTOM_JOBS[id] then return false, "That job no longer exists." end

	-- Anyone currently on this job needs moving off it first - the team
	-- would otherwise keep existing (nothing un-registers a GMod team)
	-- but PDCity.GetJob(id) would return nil for them from this point on.
	for _, other in ipairs(player.GetAll()) do
		if IsValid(other) and other:Team() == id then
			if other:Alive() then
				-- Full respawn, same as a normal job change.
				PDCity.ApplyJob(other, PDCity.DEFAULT_JOB)
			else
				-- PDCity.ApplyJob refuses while dead (players can't pick
				-- a new job mid-death) - that rule is for the player's
				-- own F4 choice, not this admin-forced cleanup, so a
				-- dead player just gets their team corrected directly.
				-- Their model/loadout will follow the new team
				-- automatically whenever they do respawn.
				other:SetTeam(PDCity.DEFAULT_JOB)
			end
			other:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your job was removed by an admin - moved to the default job.")
		end
	end

	PDCity.CUSTOM_JOBS[id] = nil
	return true
end

function Actions.add_category(ply, p)
	if not isstring(p.Name) or p.Name == "" then return false, "Category name can't be empty." end
	if table.HasValue(PDCity.SECTIONS, p.Name) then return false, "That category already exists." end

	table.insert(PDCity.SECTIONS, p.Name)
	return true
end

function Actions.remove_category(ply, p)
	if not table.HasValue(PDCity.SECTIONS, p.Name) then return false, "That category doesn't exist." end
	if #PDCity.SECTIONS <= 1 then return false, "At least one category has to exist." end

	-- A built-in job's Section is only a runtime default (core/sh_jobs.lua
	-- isn't persisted), so reassigning it here wouldn't survive a
	-- restart - refuse instead of leaving it orphaned after one.
	for _, job in pairs(PDCity.JOBS) do
		if job.Section == p.Name then
			return false, "A built-in job still uses that category - can't remove it."
		end
	end

	table.RemoveByValue(PDCity.SECTIONS, p.Name)
	PDCity.SECTION_WHITELIST_ONLY[p.Name] = nil

	for _, job in pairs(PDCity.CUSTOM_JOBS) do
		if job.Section == p.Name then
			job.Section = PDCity.SECTIONS[1]
		end
	end

	return true
end

-- Whitelist-only toggle (core/sh_jobs.lua's PDCity.SECTION_WHITELIST_ONLY,
-- PDCity.IsSectionWhitelistOnly) - every job in this category ignores
-- RequiredLevel and needs a matching department whitelist level instead
-- once this is on (core/sv_jobs.lua's PDCity.ApplyJob).
function Actions.set_category_whitelist(ply, p)
	if not table.HasValue(PDCity.SECTIONS, p.Name) then return false, "That category doesn't exist." end

	if p.WhitelistOnly then
		PDCity.SECTION_WHITELIST_ONLY[p.Name] = true
	else
		PDCity.SECTION_WHITELIST_ONLY[p.Name] = nil
	end

	return true
end

function Actions.reorder_categories(ply, p)
	if not istable(p.Order) then return false, "Bad order list." end
	if #p.Order ~= #PDCity.SECTIONS then return false, "Category list doesn't match." end
	for _, name in ipairs(p.Order) do
		if not table.HasValue(PDCity.SECTIONS, name) then return false, "Unknown category in order list." end
	end

	PDCity.SECTIONS = p.Order
	return true
end

net.Receive("pdcity_job_admin", function(len, ply)
	-- Owner only - re-checked here regardless of what the client's UI
	-- already hides (cl_f4_menu.lua/cl_f4_admin.lua).
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local handler = Actions[data.Action]
	if not handler then return end

	local payload = data.Payload or {}

	local ok, err = handler(ply, payload)
	if ok then
		SaveCatalogue()
		BroadcastCatalogue()
	end

	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
	end
end)
