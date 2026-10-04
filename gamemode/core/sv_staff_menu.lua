--[[---------------------------------------------------------
	Server side of the in-game Staff Menu (cl_staff_menu.lua). One net
	message, one Action string, same shape as the F4 admin editor's own
	"pdcity_f4_admin" messages - see that file's own header for why.

	Gated at PDCity.IsSuperAdminPlus (owner or superadmin) for every
	action EXCEPT "setrank", which is PDCity.IsOwner alone - assigning
	someone's actual staff role is a bigger deal than punishing a player
	and isn't delegable to superadmins by default.

	ULX is optional. When it's installed, bans go through ulx.ban and
	"setrank" through ulx.adduser, so ULX stays the single source of truth
	for bans and groups. Without it, bans use the small built-in ban list
	below (data/pdcity/bans.json, lifted with "pdcity_unban"), and staff
	roles can't be set from the menu - groups then come from whatever
	admin mod or settings/users.txt the server uses.

	Gag/mute/jail are custom (core/sh_voice.lua, core/sv_chat.lua,
	core/sv_staff_jail.lua) - nothing existed for those anywhere before
	this, so there was no existing system to defer to.

	Every action requires a reason (cl_staff_menu.lua's own reason box,
	re-checked non-empty here rather than trusted from the client) and
	logs to core/sv_gamelog.lua's "staff" category with it, same as every
	other staff-power action in the gamemode (!respawn, !hide,
	!forcename...) - always immediate, player moderation was never
	queued for review the way F4/job/inventory catalogue edits used to be.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_staff_action")

-- "user"/"operator"/"admin"/"superadmin" are already configured in
-- data/ulib/groups.txt. "owner" isn't - core/sh_permissions.lua's
-- PDCity.IsOwner grants that power via a hardcoded SteamID list, not a
-- UCL group, so historically nothing ever needed one to exist. Assigning
-- it here still works and grants real PDCity.IsOwner status too (that
-- function's second branch checks ply:GetUserGroup() == "owner"
-- directly) - EnsureOwnerGroupExists below creates the group itself,
-- inheriting from superadmin, the first time it's actually needed rather
-- than requiring it be set up by hand first.
local ASSIGNABLE_RANKS = { "user", "operator", "admin", "superadmin", "owner" }

-- ULib.ucl.addUser (which ulx.adduser calls) hard-errors if the group
-- doesn't already exist (see ULib's own ucl.lua) - unlike the other four
-- ranks, "owner" was never pre-defined in groups.txt.
local function EnsureOwnerGroupExists()
	if ULib.ucl.groups["owner"] then return end
	ULib.ucl.addGroup("owner", {}, "superadmin")
end

local function D(ply)
	return ply:Nick() .. " (" .. ply:SteamID() .. ")"
end

--[[---------------------------------------------------------
	ULX is optional. With it, bans and staff roles go through ULX (so they
	show up in its own ban list and !menu). Without it, bans use the small
	built-in list below and staff roles can't be set from here.
-----------------------------------------------------------]]
local function HasULX()
	return istable(ulx) and isfunction(ulx.ban) and isfunction(ulx.adduser) and istable(ULib)
end

-- Tells clients whether to offer the "Set staff role" controls. Set once
-- every addon has loaded, since ULX loads separately from the gamemode.
hook.Add("InitPostEntity", "pdcity_DetectULX", function()
	SetGlobalBool("PDCity_HasULX", HasULX())
end)

--[[---------------------------------------------------------
	Built-in bans, used only when ULX isn't installed. Saved to
	data/pdcity/bans.json and checked when a player tries to connect.
	  [steamID64] = { Until = os.time() expiry (0 = permanent), Reason, By }
-----------------------------------------------------------]]
local BANS_PATH = "pdcity/bans.json"
local bans = util.JSONToTable(file.Read(BANS_PATH, "DATA") or "") or {}

local function SaveBans()
	file.CreateDir("pdcity")
	file.Write(BANS_PATH, util.TableToJSON(bans, true))
end

local function BuiltinBan(target, minutes, reason, byName)
	bans[target:SteamID64()] = {
		Until = minutes > 0 and (os.time() + minutes * 60) or 0,
		Reason = reason,
		By = byName,
	}
	SaveBans()
	target:Kick("Banned: " .. reason)
end

hook.Add("CheckPassword", "pdcity_BuiltinBans", function(steamID64)
	local ban = bans[steamID64]
	if not ban then return end

	if ban.Until ~= 0 and os.time() >= ban.Until then
		bans[steamID64] = nil
		SaveBans()
		return
	end

	local remaining = ban.Until == 0 and "permanently"
		or ("for another " .. math.ceil((ban.Until - os.time()) / 60) .. " minute(s)")
	return false, "You are banned " .. remaining .. ". Reason: " .. tostring(ban.Reason)
end)

-- Owner-only console command to lift a built-in ban (ULX servers use
-- ULX's own unban instead): pdcity_unban <SteamID or SteamID64>
concommand.Add("pdcity_unban", function(ply, cmd, args)
	if IsValid(ply) and not PDCity.IsOwner(ply) then return end

	local id = string.Trim(args[1] or "")
	if string.match(id, "^STEAM_") then id = util.SteamIDTo64(id) end

	local msg = bans[id] and ("Unbanned " .. id .. ".") or ("No built-in ban found for " .. id .. ".")
	bans[id] = nil
	SaveBans()

	if IsValid(ply) then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. msg) else print(msg) end
end)

net.Receive("pdcity_staff_action", function(len, ply)
	if not IsValid(ply) then return end

	local action = net.ReadString()
	local target = net.ReadEntity()
	local extra = net.ReadString()
	local reason = string.Trim(net.ReadString() or "")

	-- Re-checked here, not just cl_staff_menu.lua's own RequireReason -
	-- that client-side check is only ever a courtesy against an accident,
	-- never trusted as the actual gate.
	if reason == "" then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a reason first.")
		return
	end

	if action == "setrank" then
		if not PDCity.IsOwner(ply) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can set staff roles.")
			return
		end
	elseif not PDCity.IsSuperAdminPlus(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can use the Staff Menu.")
		return
	end

	if not IsValid(target) or not target:IsPlayer() then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Invalid target.")
		return
	end

	if target == ply and (action == "ban" or action == "permaban") then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't ban yourself.")
		return
	end

	if action == "ban" then
		local days = tonumber(extra)
		if not days or days <= 0 then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a number of days greater than 0.")
			return
		end
		local logLine = D(ply) .. " temp-banned " .. D(target) .. " for " .. days .. " day(s) - reason: " .. reason
		if HasULX() then
			ulx.ban(ply, target, math.floor(days * 1440), "Staff Menu: " .. reason)
		else
			BuiltinBan(target, math.floor(days * 1440), reason, ply:Nick())
		end
		PDCity.GameLog("staff", logLine)

	elseif action == "permaban" then
		local logLine = D(ply) .. " permanently banned " .. D(target) .. " - reason: " .. reason
		if HasULX() then
			ulx.ban(ply, target, 0, "Staff Menu: " .. reason)
		else
			BuiltinBan(target, 0, reason, ply:Nick())
		end
		PDCity.GameLog("staff", logLine)

	elseif action == "gag" or action == "ungag" then
		local gagged = (action == "gag")
		target:SetNWBool("PDCity_Gagged", gagged)
		target:ChatPrint(gagged and "[" .. PDCity.BRAND_TAG .. "] You have been gagged." or "[" .. PDCity.BRAND_TAG .. "] You have been ungagged.")
		PDCity.GameLog("staff", D(ply) .. (gagged and " gagged " or " ungagged ") .. D(target) .. " - reason: " .. reason)

	elseif action == "mute" or action == "unmute" then
		local muted = (action == "mute")
		target:SetNWBool("PDCity_Muted", muted)
		target:ChatPrint(muted and "[" .. PDCity.BRAND_TAG .. "] You have been muted." or "[" .. PDCity.BRAND_TAG .. "] You have been unmuted.")
		PDCity.GameLog("staff", D(ply) .. (muted and " muted " or " unmuted ") .. D(target) .. " - reason: " .. reason)

	elseif action == "jail" then
		local minutes = math.floor(tonumber(extra) or 0)
		local ok, err = PDCity.StaffJailPlayer(target, minutes)
		if not ok then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. err)
			return
		end
		PDCity.GameLog("staff", D(ply) .. " jailed " .. D(target)
			.. (minutes > 0 and (" for " .. minutes .. " minute(s)") or " indefinitely") .. " - reason: " .. reason)

	elseif action == "unjail" then
		PDCity.StaffUnjailPlayer(target)
		PDCity.GameLog("staff", D(ply) .. " released " .. D(target) .. " from staff jail - reason: " .. reason)

	elseif action == "setrank" then
		if not HasULX() then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Setting staff roles needs ULX installed.")
			return
		end
		if not table.HasValue(ASSIGNABLE_RANKS, extra) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Invalid rank.")
			return
		end
		if extra == "owner" then EnsureOwnerGroupExists() end
		ulx.adduser(ply, target, extra)
		target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your staff role has been set to: " .. extra)
		PDCity.GameLog("staff", D(ply) .. " set " .. D(target) .. "'s staff role to " .. extra .. " - reason: " .. reason)
	end
end)
