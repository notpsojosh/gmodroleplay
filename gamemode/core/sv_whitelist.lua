--[[---------------------------------------------------------
	Department (job category) whitelist/blacklist - storage, permission
	checks, and the net protocol for cl_whitelist_menu.lua's panel.

	Stored per-player, in the SAME profile core/sv_profiles.lua already
	persists everything else in (profile.WhitelistLevels/
	WhitelistPromotedAt/DepartmentBans - see that file's DEFAULT_PROFILE).
	A player's own status is synced down to them on join ("pdcity_whitelist_
	sync") purely for client-side UI (F4 job card badges, gating the panel's
	own controls) - every actual mutation below re-validates from the
	server's own profile data regardless of what the client claims.

	"Managing a department" means: PDCity.IsSuperAdminPlus (every
	department, no level needed), or your OWN whitelist level in that
	department is >= PDCity.WHITELIST_MANAGE_LEVEL (6) - and even then,
	only over players whose CURRENT level is lower than yours. Nobody but
	superadmin/owner can touch someone at or above their own level.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_whitelist_sync")
util.AddNetworkString("pdcity_whitelist_roster_request")
util.AddNetworkString("pdcity_whitelist_roster")
util.AddNetworkString("pdcity_whitelist_action")
util.AddNetworkString("pdcity_whitelist_open")

--[[---------------------------------------------------------
	Accessors
-----------------------------------------------------------]]

function PDCity.GetWhitelistLevel(ply, department)
	local account = PDCity.GetAccount(ply)
	if not account then return 0 end
	return account.WhitelistLevels[department] or 0
end

function PDCity.GetDepartmentBan(ply, department)
	local account = PDCity.GetAccount(ply)
	if not account then return nil end
	return account.DepartmentBans[department]
end

function PDCity.IsDepartmentBanned(ply, department)
	local ban = PDCity.GetDepartmentBan(ply, department)
	if not ban then return false end
	if ban.Until == -1 then return true end
	return ban.Until > os.time()
end

-- PDCity.IsSuperAdminPlus bypasses every restriction below - owner/
-- superadmin manage every department regardless of their own level.
function PDCity.CanManageDepartment(ply, department)
	if PDCity.IsSuperAdminPlus(ply) then return true end
	return PDCity.GetWhitelistLevel(ply, department) >= PDCity.WHITELIST_MANAGE_LEVEL
end

-- Whether `actor` can act on `targetLevel` specifically - separate from
-- CanManageDepartment because THIS also enforces "never at or above your
-- own level", which doesn't apply to superadmin/owner.
local function CanActOnLevel(actor, department, targetLevel)
	if PDCity.IsSuperAdminPlus(actor) then return true end
	local actorLevel = PDCity.GetWhitelistLevel(actor, department)
	return actorLevel >= PDCity.WHITELIST_MANAGE_LEVEL and targetLevel < actorLevel
end

local function SyncWhitelistTo(ply)
	local account = PDCity.GetAccount(ply)
	if not account then return end

	net.Start("pdcity_whitelist_sync")
		net.WriteString(util.TableToJSON({
			Levels = account.WhitelistLevels,
			PromotedAt = account.WhitelistPromotedAt,
			Bans = account.DepartmentBans,
		}))
	net.Send(ply)
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncWhitelistStatus", function(ply)
	timer.Simple(1, function()
		if IsValid(ply) then SyncWhitelistTo(ply) end
	end)
end)

--[[---------------------------------------------------------
	Offline-target support - promote/blacklist someone who isn't
	currently connected. Whitelist is account-scoped (core/sv_accounts.lua),
	not per-character, so PDCity.GetAccount/PDCity.MarkAccountDirty both
	requiring a live Player is the only real gap - these two go around
	them directly via PDCity.LoadAccount/PDCity.MarkAccountDirtyByID when
	the target is offline.
-----------------------------------------------------------]]

local function ResolveTargetProfile(steamID64)
	local online
	for _, ply in ipairs(player.GetHumans()) do
		if ply:SteamID64() == steamID64 then online = ply break end
	end

	if online then
		return PDCity.GetAccount(online), online
	end

	return PDCity.LoadAccount(steamID64), nil
end

local function MarkTargetDirty(steamID64, onlinePly)
	if IsValid(onlinePly) then
		PDCity.MarkAccountDirty(onlinePly)
	else
		PDCity.MarkAccountDirtyByID(steamID64)
	end
end

--[[---------------------------------------------------------
	Mutations. All take (actor, targetSteamID64, department, ...) and
	return ok[, error] - actor permission is re-checked here every time,
	never trusted from the client beyond "which button did they click".
-----------------------------------------------------------]]

function PDCity.SetWhitelistLevel(actor, targetSteamID64, department, level)
	if not PDCity.IsSectionWhitelistOnly(department) then return false, "That category isn't whitelist-only." end
	if not isnumber(level) or level < 0 or level ~= math.floor(level) then return false, "Level must be a whole number, 0 or more." end

	local profile, onlinePly = ResolveTargetProfile(targetSteamID64)
	if not profile then return false, "No profile for that player." end

	local currentLevel = profile.WhitelistLevels[department] or 0
	if not CanActOnLevel(actor, department, currentLevel) then
		return false, "You can't manage someone at or above your own whitelist level."
	end
	-- Also refuse setting them TO a level at or above the actor's own
	-- (unless the actor is superadmin/owner) - otherwise a level-6 could
	-- promote someone straight past them.
	if not PDCity.IsSuperAdminPlus(actor) and level >= PDCity.GetWhitelistLevel(actor, department) then
		return false, "You can't promote someone to your own level or higher."
	end

	profile.WhitelistLevels[department] = level > 0 and level or nil
	profile.WhitelistPromotedAt[department] = os.time()
	MarkTargetDirty(targetSteamID64, onlinePly)

	if IsValid(onlinePly) then
		SyncWhitelistTo(onlinePly)
		onlinePly:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your " .. department .. " whitelist level is now " .. level .. ".")
	end

	local targetName = profile.LastKnownName ~= "" and profile.LastKnownName or targetSteamID64
	PDCity.GameLog("whitelist", actor:Nick() .. " (" .. actor:SteamID() .. ") set " .. targetName .. " (" .. targetSteamID64 .. ")'s "
		.. department .. " whitelist level to " .. level .. " (was " .. currentLevel .. ")")

	return true
end

function PDCity.SetDepartmentBan(actor, targetSteamID64, department, days, reason)
	if not isnumber(days) then return false, "Days must be a number (-1 for permanent)." end
	if not isstring(reason) or string.Trim(reason) == "" then return false, "A reason is required." end

	local profile, onlinePly = ResolveTargetProfile(targetSteamID64)
	if not profile then return false, "No profile for that player." end

	local currentLevel = profile.WhitelistLevels[department] or 0
	if not CanActOnLevel(actor, department, currentLevel) then
		return false, "You can't manage someone at or above your own whitelist level."
	end

	local until_ = (days < 0) and -1 or (os.time() + math.floor(days) * 86400)
	profile.DepartmentBans[department] = { Until = until_, Reason = reason, At = os.time() }
	MarkTargetDirty(targetSteamID64, onlinePly)

	if IsValid(onlinePly) then
		SyncWhitelistTo(onlinePly)
		onlinePly:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You've been blacklisted from " .. department .. (until_ == -1 and " permanently" or (" for " .. days .. " day(s)")) .. " - reason: " .. reason)
	end

	local targetName = profile.LastKnownName ~= "" and profile.LastKnownName or targetSteamID64
	PDCity.GameLog("whitelist", actor:Nick() .. " (" .. actor:SteamID() .. ") blacklisted " .. targetName .. " (" .. targetSteamID64 .. ") from "
		.. department .. (until_ == -1 and " permanently" or (" for " .. days .. " day(s)")) .. " - reason: " .. reason)

	return true
end

function PDCity.ClearDepartmentBan(actor, targetSteamID64, department)
	local profile, onlinePly = ResolveTargetProfile(targetSteamID64)
	if not profile then return false, "No profile for that player." end

	local ban = profile.DepartmentBans[department]
	if not ban then return false, "That player isn't blacklisted from " .. department .. "." end

	local currentLevel = profile.WhitelistLevels[department] or 0
	if not CanActOnLevel(actor, department, currentLevel) then
		return false, "You can't manage someone at or above your own whitelist level."
	end

	profile.DepartmentBans[department] = nil
	MarkTargetDirty(targetSteamID64, onlinePly)

	if IsValid(onlinePly) then
		SyncWhitelistTo(onlinePly)
		onlinePly:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your " .. department .. " blacklist has been lifted.")
	end

	local targetName = profile.LastKnownName ~= "" and profile.LastKnownName or targetSteamID64
	PDCity.GameLog("whitelist", actor:Nick() .. " (" .. actor:SteamID() .. ") lifted " .. targetName .. " (" .. targetSteamID64 .. ")'s " .. department .. " blacklist")

	return true
end

--[[---------------------------------------------------------
	Roster scan - everyone with a level>0 or a ban in a department, for
	the panel's "Whitelisted Players"/"Blacklist" tables. Checks online
	players from their live (possibly not-yet-saved) profile first, then
	falls back to reading every OTHER profile.json on disk directly - the
	only way to include offline players, since nothing keeps a queryable
	in-memory list of everyone who's ever connected.
-----------------------------------------------------------]]

local function ReadAccountFileRaw(steamID64)
	local raw = file.Read(PDCity.PlayerDataDir(steamID64) .. "/account.json", "DATA")
	return raw and util.JSONToTable(raw)
end

function PDCity.ScanDepartmentRoster(department)
	local whitelisted, blacklisted = {}, {}
	local seen = {}

	local function Consider(steamID64, account, name)
		seen[steamID64] = true

		local level = account.WhitelistLevels and account.WhitelistLevels[department]
		if level and level > 0 then
			table.insert(whitelisted, {
				SteamID64 = steamID64,
				Name = name,
				Level = level,
				PromotedAt = (account.WhitelistPromotedAt and account.WhitelistPromotedAt[department]) or 0,
			})
		end

		local ban = account.DepartmentBans and account.DepartmentBans[department]
		if ban then
			table.insert(blacklisted, {
				SteamID64 = steamID64,
				Name = name,
				Until = ban.Until,
				Reason = ban.Reason,
			})
		end
	end

	for _, ply in ipairs(player.GetHumans()) do
		local account = PDCity.GetAccount(ply)
		if account then Consider(ply:SteamID64(), account, ply:Nick()) end
	end

	local _, folders = file.Find("pdcity/players/*", "DATA")
	for _, folder in ipairs(folders) do
		if not seen[folder] then
			local account = ReadAccountFileRaw(folder)
			if account then
				Consider(folder, account, (account.LastKnownName and account.LastKnownName ~= "") and account.LastKnownName or folder)
			end
		end
	end

	table.sort(whitelisted, function(a, b) return a.Level > b.Level end)
	table.sort(blacklisted, function(a, b) return a.Until > b.Until end)

	return whitelisted, blacklisted
end

--[[---------------------------------------------------------
	Net protocol for the panel (cl_whitelist_menu.lua)
-----------------------------------------------------------]]

net.Receive("pdcity_whitelist_roster_request", function(len, ply)
	local department = net.ReadString()
	if not PDCity.CanManageDepartment(ply, department) then return end

	local whitelisted, blacklisted = PDCity.ScanDepartmentRoster(department)

	net.Start("pdcity_whitelist_roster")
		net.WriteString(department)
		net.WriteString(util.TableToJSON({ Whitelisted = whitelisted, Blacklisted = blacklisted }))
	net.Send(ply)
end)

net.Receive("pdcity_whitelist_action", function(len, ply)
	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) or not isstring(data.Department) or not isstring(data.SteamID64) then return end

	local ok, err

	if data.Action == "set_level" then
		ok, err = PDCity.SetWhitelistLevel(ply, data.SteamID64, data.Department, tonumber(data.Level) or 0)
	elseif data.Action == "blacklist" then
		ok, err = PDCity.SetDepartmentBan(ply, data.SteamID64, data.Department, tonumber(data.Days) or -1, data.Reason or "")
	elseif data.Action == "unblacklist" then
		ok, err = PDCity.ClearDepartmentBan(ply, data.SteamID64, data.Department)
	else
		return
	end

	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
		return
	end

	-- Refresh the panel's own view of this department for everyone
	-- currently managing it - simplest correct approach is just to
	-- re-send this one actor their own updated roster; other admins
	-- viewing the same department will see it next time they switch
	-- departments/reopen the panel.
	local whitelisted, blacklisted = PDCity.ScanDepartmentRoster(data.Department)
	net.Start("pdcity_whitelist_roster")
		net.WriteString(data.Department)
		net.WriteString(util.TableToJSON({ Whitelisted = whitelisted, Blacklisted = blacklisted }))
	net.Send(ply)
end)

-- Tells a client to open the panel (core/sv_whitelist_chat.lua's
-- "!whitelist"). The F4 "Manage Whitelist" button opens it directly
-- client-side instead, since that click already happens on the client.
function PDCity.OpenWhitelistPanelFor(ply)
	net.Start("pdcity_whitelist_open")
	net.Send(ply)
end
